import { NextResponse } from "next/server";
import { requireCompanyMembership } from "@/lib/server/supabase";

const MODULE_METADATA_TO_ROLE = {
  pos: { POS: "MANAGER" },
  adquisiciones: { ADQUISICIONES: "MANAGER" },
  farmacias: { FARMACIAS: "PHARMACIST" },
  logistica: { LOGISTICA: "MANAGER" },
  rrhh: { RRHH: "ADMIN" },
};

export async function POST(request) {
  try {
    const body = await request.json();
    const companyId = body?.companyId;

    const context = await requireCompanyMembership(request, companyId, []);
    if (context.error) {
      return NextResponse.json({ error: context.error }, { status: context.status || 400 });
    }

    const updates = {};
    const inferred = MODULE_METADATA_TO_ROLE[context.user.user_metadata?.modulo_inicial];
    const moduleRoles = context.membership.module_roles || {};

    if (Object.keys(moduleRoles).length === 0 && inferred) {
      updates.module_roles = inferred;
    }

    if (context.membership.role === "OWNER" && (!context.membership.full_name || !context.membership.email)) {
      updates.full_name = context.user.user_metadata?.full_name || "Dueño Registrado";
      updates.email = context.user.email;
    }

    if (Object.keys(updates).length > 0) {
      const { data, error } = await context.admin
        .from("company_users")
        .update(updates)
        .eq("company_id", companyId)
        .eq("user_id", context.user.id)
        .select("id, company_id, user_id, role, full_name, email, module_roles, must_change_password")
        .single();

      if (error) {
        return NextResponse.json({ error: error.message }, { status: 400 });
      }

      return NextResponse.json({ success: true, membership: data, repaired: true });
    }

    return NextResponse.json({ success: true, membership: context.membership, repaired: false });
  } catch (error) {
    console.error("Repair roles error:", error);
    return NextResponse.json({ error: "Internal Server Error" }, { status: 500 });
  }
}
