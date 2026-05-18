import "server-only";
import { createClient } from "@supabase/supabase-js";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

function requireEnv(value, name) {
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

export function createSupabaseAdmin() {
  return createClient(
    requireEnv(supabaseUrl, "NEXT_PUBLIC_SUPABASE_URL"),
    requireEnv(supabaseServiceRoleKey, "SUPABASE_SERVICE_ROLE_KEY"),
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUrl: false,
      },
    }
  );
}

export async function requireUserContext(request) {
  const authHeader = request.headers.get("authorization") || "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : "";

  if (!token) {
    return { error: "Unauthorized", status: 401 };
  }

  const authClient = createClient(
    requireEnv(supabaseUrl, "NEXT_PUBLIC_SUPABASE_URL"),
    requireEnv(supabaseAnonKey, "NEXT_PUBLIC_SUPABASE_ANON_KEY"),
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUrl: false,
      },
      global: {
        headers: {
          Authorization: `Bearer ${token}`,
        },
      },
    }
  );

  const { data, error } = await authClient.auth.getUser(token);

  if (error || !data?.user) {
    return { error: "Unauthorized", status: 401 };
  }

  return {
    user: data.user,
    accessToken: token,
    admin: createSupabaseAdmin(),
  };
}

export async function requireCompanyMembership(request, companyId, allowedRoles = ["OWNER", "MANAGER"]) {
  if (!companyId) {
    return { error: "companyId is required", status: 400 };
  }

  const context = await requireUserContext(request);
  if (context.error) {
    return context;
  }

  const { data: membership, error } = await context.admin
    .from("company_users")
    .select("id, company_id, user_id, role, full_name, email, module_roles, must_change_password")
    .eq("company_id", companyId)
    .eq("user_id", context.user.id)
    .maybeSingle();

  if (error || !membership) {
    return { error: "Forbidden", status: 403 };
  }

  if (allowedRoles.length > 0 && !allowedRoles.includes(membership.role)) {
    return { error: "Forbidden", status: 403, ...context, membership };
  }

  return { ...context, membership };
}
