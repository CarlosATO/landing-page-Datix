import { NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { requireUserContext } from '@/lib/server/supabase';

// ──────────────────────────────────────────────────────────────────────────────
// Constants
// ──────────────────────────────────────────────────────────────────────────────

const MODULE_METADATA_TO_ROLE = {
  pos:          { POS: 'MANAGER' },
  adquisiciones:{ ADQUISICIONES: 'MANAGER' },
  farmacias:    { FARMACIAS: 'PHARMACIST' },
  farmacia:     { FARMACIAS: 'PHARMACIST' },
  pharmacy:     { FARMACIAS: 'PHARMACIST' },
  logistica:    { LOGISTICA: 'MANAGER' },
  construccion: { CONSTRUCCION: 'MANAGER' },
  rrhh:         { RRHH: 'ADMIN' },
};

const CONTRACTED_STATUSES = new Set(['active', 'trial']);

// ──────────────────────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────────────────────

/**
 * Normalises a raw module_key from the DB to a canonical key.
 * - 'pharmacy' | 'farmacia' → 'farmacias'
 * - everything else: lowercase + trim
 * Returns null for empty/null values so callers can distinguish "nothing" from a key.
 */
const normalizeModuleKey = (value) => {
  if (!value) return null;
  const n = String(value).trim().toLowerCase();
  if (n === 'pharmacy' || n === 'farmacia') return 'farmacias';
  return n;
};

const getInitialModuleKey = (user) => {
  const key =
    user?.user_metadata?.selected_module ||
    user?.user_metadata?.module_key ||
    user?.user_metadata?.modulo_inicial;
  return normalizeModuleKey(key) || 'logistica';
};

const normalizeCompanyModule = (m) => ({
  ...m,
  module_key_normalized: normalizeModuleKey(m?.module_key) ?? m?.module_key,
  status_normalized:     String(m?.status || '').toLowerCase(),
});

// ──────────────────────────────────────────────────────────────────────────────
// Route
// ──────────────────────────────────────────────────────────────────────────────

export async function POST(request) {
  try {
    const context = await requireUserContext(request);
    if (context.error) {
      return NextResponse.json({ error: context.error }, { status: context.status || 401 });
    }

    const admin = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL,
      process.env.SUPABASE_SERVICE_ROLE_KEY,
      { auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false } },
    );

    // ── Step 1: resolve company_id ──────────────────────────────────────────
    // Primary source: company_users (the ground truth for membership).
    // app_metadata.company_id is used as a preference/hint, not as the only source.

    const { data: userMemberships } = await admin
      .from('company_users')
      .select('id, company_id, user_id, role, full_name, email, module_roles, must_change_password')
      .eq('user_id', context.user.id)
      .order('created_at', { ascending: true });

    const memberships = userMemberships || [];

    let companyId = null;
    let membership = null;

    if (memberships.length > 0) {
      // Prefer the company_id from app_metadata if the user actually belongs to it.
      const preferred = context.user.app_metadata?.company_id;
      const preferredMatch = preferred
        ? memberships.find((m) => m.company_id === preferred)
        : null;

      // Priority: app_metadata match → OWNER membership → first membership
      const ownerMatch = memberships.find((m) => m.role === 'OWNER');
      const chosen = preferredMatch ?? ownerMatch ?? memberships[0];

      companyId  = chosen.company_id;
      membership = chosen;
    }

    if (process.env.NODE_ENV !== 'production') {
      console.info('[portal/bootstrap] company resolution', {
        user_id:               context.user.id,
        user_email:            context.user.email,
        app_metadata_company_id: context.user.app_metadata?.company_id ?? null,
        memberships_found:     memberships.map((m) => ({ company_id: m.company_id, role: m.role })),
        resolved_company_id:   companyId,
        source:                companyId
          ? (context.user.app_metadata?.company_id === companyId ? 'app_metadata_validated' : 'company_users')
          : 'none',
      });
    }

    // ── Step 2: first-time user — create company + module if needed ──────────
    if (!companyId) {
      const initialModuleKey = getInitialModuleKey(context.user);
      const ownerName = (
        context.user.user_metadata?.full_name ||
        context.user.user_metadata?.empresa_nombre ||
        context.user.email ||
        'Empresa'
      ).toString().trim();

      const { data: createdCompany, error: companyCreateError } = await admin
        .from('companies')
        .insert({
          name:                ownerName,
          fantasy_name:        context.user.user_metadata?.empresa_nombre || ownerName,
          subscription_status: 'trial',
        })
        .select('id, name, fantasy_name, subscription_status')
        .single();

      if (companyCreateError || !createdCompany) {
        return NextResponse.json(
          { error: companyCreateError?.message || 'No se pudo crear la empresa' },
          { status: 400 },
        );
      }

      companyId = createdCompany.id;

      const ownerModuleRoles = MODULE_METADATA_TO_ROLE[initialModuleKey] || MODULE_METADATA_TO_ROLE.logistica;
      const now = new Date().toISOString();

      const { error: cuError } = await admin.from('company_users').insert({
        company_id:          companyId,
        user_id:             context.user.id,
        email:               context.user.email,
        role:                'OWNER',
        full_name:           context.user.user_metadata?.full_name || ownerName,
        module_roles:        ownerModuleRoles,
        must_change_password: false,
      });
      if (cuError) return NextResponse.json({ error: cuError.message }, { status: 400 });

      const { error: urError } = await admin.from('user_roles').insert({
        company_id: companyId,
        user_id:    context.user.id,
        role_key:   'OWNER',
        module_key: null,
      });
      if (urError) return NextResponse.json({ error: urError.message }, { status: 400 });

      const { error: cmError } = await admin.from('company_modules').insert({
        company_id:  companyId,
        module_key:  initialModuleKey,
        status:      'trial',
        enabled_at:  now,
        disabled_at: null,
      });
      if (cmError) return NextResponse.json({ error: cmError.message }, { status: 400 });

      const { error: authError } = await admin.auth.admin.updateUserById(context.user.id, {
        app_metadata: {
          ...(context.user.app_metadata || {}),
          company_id: companyId,
          role:       'OWNER',
        },
      });
      if (authError) return NextResponse.json({ error: authError.message }, { status: 400 });

      // Re-fetch membership after creation
      const { data: newMembership } = await admin
        .from('company_users')
        .select('id, company_id, user_id, role, full_name, email, module_roles, must_change_password')
        .eq('company_id', companyId)
        .eq('user_id', context.user.id)
        .maybeSingle();
      membership = newMembership;
    }

    // ── Step 3: load company data ────────────────────────────────────────────
    const [{ data: company, error: companyError }, { data: rawModules }] = await Promise.all([
      admin.from('companies').select('*').eq('id', companyId).single(),
      admin.from('company_modules').select('module_key, status, enabled_at, disabled_at').eq('company_id', companyId),
    ]);

    if (companyError || !company) {
      return NextResponse.json({ error: 'Company not found' }, { status: 404 });
    }

    // ── Step 4: derive role & modules ────────────────────────────────────────
    const role               = membership?.role || context.user.app_metadata?.role || 'MEMBER';
    const needsPasswordChange = Boolean(membership?.must_change_password && role !== 'OWNER');

    let effectiveModuleRoles = membership?.module_roles || context.user.app_metadata?.module_roles || {};

    if (Object.keys(effectiveModuleRoles).length === 0) {
      const inferredKey = getInitialModuleKey(context.user);
      const inferred    = MODULE_METADATA_TO_ROLE[inferredKey] || MODULE_METADATA_TO_ROLE.logistica;
      if (inferred && membership?.id) {
        const { error: repairError } = await admin
          .from('company_users')
          .update({ module_roles: inferred })
          .eq('id', membership.id);
        if (!repairError) effectiveModuleRoles = inferred;
      }
    }

    if (role === 'OWNER' && membership && (!membership.full_name || !membership.email)) {
      await admin.from('company_users').update({
        full_name: context.user.user_metadata?.full_name || 'Dueño Registrado',
        email:     context.user.email,
      }).eq('id', membership.id);
    }

    const teamMembers = (role === 'OWNER' || role === 'MANAGER')
      ? await admin.from('company_users').select('*').eq('company_id', companyId)
      : { data: [] };

    const normalizedCompanyModules  = (rawModules || []).map(normalizeCompanyModule);
    const contractedCompanyModules  = normalizedCompanyModules.filter(
      (m) => CONTRACTED_STATUSES.has(m.status_normalized),
    );

    if (process.env.NODE_ENV !== 'production') {
      console.info('[portal/bootstrap] result', {
        company_id:   companyId,
        company_name: company?.name,
        user_id:      context.user.id,
        user_email:   context.user.email,
        role,
        company_modules_raw: (rawModules || []).map((m) => ({
          module_key: m.module_key,
          status:     m.status,
        })),
        contracted_modules: contractedCompanyModules.map((m) => ({
          module_key_normalized: m.module_key_normalized,
          status:                m.status_normalized,
        })),
      });
    }

    return NextResponse.json({
      company_id:             companyId,
      user:                   context.user,
      company,
      role,
      needsPasswordChange,
      userAppAccess:          effectiveModuleRoles,
      companyModules:         normalizedCompanyModules,
      contractedCompanyModules,
      teamMembers:            teamMembers.data || [],
    });
  } catch (error) {
    console.error('Portal bootstrap error:', error);
    return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
  }
}
