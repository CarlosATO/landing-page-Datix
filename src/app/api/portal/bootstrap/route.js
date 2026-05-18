import { NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { requireUserContext } from '@/lib/server/supabase';

const MODULE_METADATA_TO_ROLE = {
  pos: { POS: 'MANAGER' },
  adquisiciones: { ADQUISICIONES: 'MANAGER' },
  farmacias: { FARMACIAS: 'PHARMACIST' },
  logistica: { LOGISTICA: 'MANAGER' },
  rrhh: { RRHH: 'ADMIN' },
};

export async function POST(request) {
  try {
    const context = await requireUserContext(request);
    if (context.error) {
      return NextResponse.json({ error: context.error }, { status: context.status || 401 });
    }

    const companyId = context.user.app_metadata?.company_id;
    if (!companyId) {
      return NextResponse.json({ error: 'company_id not found in session' }, { status: 400 });
    }

    const admin = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL,
      process.env.SUPABASE_SERVICE_ROLE_KEY,
      { auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false } }
    );

    const [{ data: company, error: companyError }, { data: membership }] = await Promise.all([
      admin.from('companies').select('*').eq('id', companyId).single(),
      admin
        .from('company_users')
        .select('id, company_id, user_id, role, full_name, email, module_roles, must_change_password')
        .eq('company_id', companyId)
        .eq('user_id', context.user.id)
        .maybeSingle(),
    ]);

    if (companyError || !company) {
      return NextResponse.json({ error: 'Company not found' }, { status: 404 });
    }

    const role = context.user.app_metadata?.role || membership?.role || 'MEMBER';
    const needsPasswordChange = Boolean(membership?.must_change_password && role !== 'OWNER');

    let effectiveModuleRoles = membership?.module_roles || context.user.app_metadata?.module_roles || {};

    if (Object.keys(effectiveModuleRoles).length === 0) {
      const inferred = MODULE_METADATA_TO_ROLE[context.user.user_metadata?.modulo_inicial];
      if (inferred && membership?.id) {
        const { error: repairError } = await admin
          .from('company_users')
          .update({ module_roles: inferred })
          .eq('id', membership.id);
        if (!repairError) {
          effectiveModuleRoles = inferred;
        }
      }
    }

    if (role === 'OWNER' && membership && (!membership.full_name || !membership.email)) {
      await admin
        .from('company_users')
        .update({
          full_name: context.user.user_metadata?.full_name || 'Dueño Registrado',
          email: context.user.email,
        })
        .eq('id', membership.id);
    }

    const teamMembers = role === 'OWNER' || role === 'MANAGER'
      ? await admin.from('company_users').select('*').eq('company_id', companyId)
      : { data: [] };

    return NextResponse.json({
      user: context.user,
      company,
      role,
      needsPasswordChange,
      userAppAccess: effectiveModuleRoles,
      teamMembers: teamMembers.data || [],
    });
  } catch (error) {
    console.error('Portal bootstrap error:', error);
    return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
  }
}
