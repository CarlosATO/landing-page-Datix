import { NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { requireUserContext } from '@/lib/server/supabase';

const CONTRACTED_STATUSES = new Set(['active', 'trial']);
const normalizeKey = (value) => String(value || '').trim().toLowerCase();
const ALLOWED_DEV_ORIGINS = new Set([
  'http://localhost:5176',
  'http://127.0.0.1:5176',
]);

const isDev = process.env.NODE_ENV !== 'production';

function getCorsOrigin(request) {
  if (!isDev) return null;
  const origin = request.headers.get('origin');
  if (!origin || !ALLOWED_DEV_ORIGINS.has(origin)) return null;
  return origin;
}

function getCorsHeaders(request) {
  const origin = getCorsOrigin(request);
  if (!origin) return {};

  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Allow-Credentials': 'true',
    Vary: 'Origin',
  };
}

function jsonWithCors(request, body, init = {}) {
  return NextResponse.json(body, {
    ...init,
    headers: {
      ...(init.headers || {}),
      ...getCorsHeaders(request),
    },
  });
}

function noContentWithCors(request) {
  return new NextResponse(null, {
    status: 204,
    headers: getCorsHeaders(request),
  });
}

async function handleBootstrap(request) {
  try {
    const context = await requireUserContext(request);
    if (context.error) {
      return jsonWithCors(request, { error: context.error }, { status: context.status || 401 });
    }

    const admin = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL,
      process.env.SUPABASE_SERVICE_ROLE_KEY,
      { auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false } }
    );

    // 1. Get company_id — try app_metadata first, fallback to company_users table
    //    (JWT can be stale if the session token was minted before app_metadata was updated)
    const appMetadataCompanyId = context.user.app_metadata?.company_id || null;
    let companyId = appMetadataCompanyId;
    let fallbackCompanyId = null;
    let companyIdSource = appMetadataCompanyId ? 'app_metadata' : null;

    if (!companyId) {
      const { data: cu } = await admin
        .from('company_users')
        .select('company_id')
        .eq('user_id', context.user.id)
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle();
      fallbackCompanyId = cu?.company_id || null;
      companyId = fallbackCompanyId;
      companyIdSource = companyId ? 'company_users_fallback' : null;
    }

    if (isDev) {
      console.info('[logistica/bootstrap] company_id resolution', {
        user_id: context.user.id,
        user_email: context.user.email,
        app_metadata_company_id: appMetadataCompanyId,
        fallback_company_id: fallbackCompanyId,
        resolved_company_id: companyId,
        source: companyIdSource || 'none',
      });
    }

    if (!companyId) {
      return jsonWithCors(request, { error: 'company_id not found — usuario sin empresa asignada', reason: 'no_company_id' }, { status: 400 });
    }

    const { data: membership } = await admin
      .from('company_users')
      .select('id, company_id, user_id, role, full_name, email')
      .eq('company_id', companyId)
      .eq('user_id', context.user.id)
      .maybeSingle();

    // Allow entry even if membership not found yet (race condition on first login)
    // but log it as warning
    if (!membership) {
      console.warn('[logistica/bootstrap] user not in company_users', {
        user_id: context.user.id, company_id: companyId
      });
    }

    const [{ data: company }, { data: companyModules }] = await Promise.all([
      admin.from('companies').select('id, name, fantasy_name, subscription_status').eq('id', companyId).single(),
      admin
        .from('company_modules').select('module_key, status, enabled_at, disabled_at').eq('company_id', companyId),
    ]);

    const normalizedCompanyModules = (companyModules || []).map((module) => ({
      ...module,
      module_key_normalized: normalizeKey(module.module_key),
      status_normalized: normalizeKey(module.status),
    }));
    const logisticaModule = normalizedCompanyModules.find((m) => m.module_key_normalized === 'logistica') || null;
    const moduleEnabled = Boolean(logisticaModule && CONTRACTED_STATUSES.has(logisticaModule.status_normalized));
    const reason = !logisticaModule
      ? 'sin fila en company_modules'
      : CONTRACTED_STATUSES.has(logisticaModule.status_normalized)
        ? null
        : `status=${logisticaModule.status}`;

    if (isDev) {
      console.info('[logistica/bootstrap]', {
        user_id: context.user.id,
        user_email: context.user.email,
        company_id: companyId,
        company_name: company?.name,
        company_modules_raw: normalizedCompanyModules.map((module) => ({
          module_key: module.module_key,
          module_key_normalized: module.module_key_normalized,
          status: module.status,
          status_normalized: module.status_normalized,
        })),
        module_key: 'logistica',
        status: logisticaModule?.status || null,
        enabled: moduleEnabled,
        locked: !moduleEnabled,
        openUrl: null,
        reason,
      });
    }

    return jsonWithCors(request, {
      company_id: companyId,
      company_id_source: companyIdSource || 'none',
      app_metadata_company_id: appMetadataCompanyId,
      fallback_company_id: fallbackCompanyId,
      company,
      role: membership?.role || 'MEMBER',
      companyModules: normalizedCompanyModules,
      moduleEnabled,
      moduleStatus: logisticaModule?.status || 'inactive',
      canEnter: moduleEnabled,
      reason,
    });
  } catch (error) {
    console.error('Logistica bootstrap error:', error);
    return jsonWithCors(request, { error: 'Internal Server Error' }, { status: 500 });
  }
}

export async function GET(request) {
  return handleBootstrap(request);
}

export async function POST(request) {
  return handleBootstrap(request);
}

export async function OPTIONS(request) {
  return noContentWithCors(request);
}
