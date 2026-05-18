import { NextResponse } from "next/server";
import { requireCompanyMembership } from "@/lib/server/supabase";

export async function PATCH(request) {
  try {
    const body = await request.json();
    const companyId = body?.companyId;
    const updates = body?.updates || {};

    const context = await requireCompanyMembership(request, companyId, []);
    if (context.error) {
      return NextResponse.json({ error: context.error }, { status: context.status || 400 });
    }

    const allowed = {};
    if (typeof updates.full_name === "string") allowed.full_name = updates.full_name.trim();
    if (typeof updates.must_change_password === "boolean") allowed.must_change_password = updates.must_change_password;
    if (updates.module_roles && typeof updates.module_roles === "object") allowed.module_roles = updates.module_roles;

    if (Object.keys(allowed).length === 0) {
      return NextResponse.json({ error: "No valid profile fields provided" }, { status: 400 });
    }

    const { data, error } = await context.admin
      .from("company_users")
      .update(allowed)
      .eq("company_id", companyId)
      .eq("user_id", context.user.id)
      .select("id, company_id, user_id, role, full_name, email, module_roles, must_change_password")
      .single();

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }

    return NextResponse.json({ success: true, profile: data });
  } catch (error) {
    console.error("Profile update error:", error);
    return NextResponse.json({ error: "Internal Server Error" }, { status: 500 });
  }
}
