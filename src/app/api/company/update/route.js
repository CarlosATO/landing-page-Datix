import { NextResponse } from "next/server";
import { requireCompanyMembership } from "@/lib/server/supabase";

const normalize = (value) => (value ?? "").toString().trim().toUpperCase();

export async function POST(request) {
  try {
    const body = await request.json();
    const companyId = body?.companyId;
    const payload = body?.data || {};

    const context = await requireCompanyMembership(request, companyId, ["OWNER", "MANAGER"]);
    if (context.error) {
      return NextResponse.json({ error: context.error }, { status: context.status || 400 });
    }

    const updates = {};
    if (payload.rut !== undefined) updates.rut = normalize(payload.rut);
    if (payload.activity !== undefined) updates.activity = normalize(payload.activity);
    if (payload.address !== undefined) updates.address = normalize(payload.address);
    if (payload.city !== undefined) updates.city = normalize(payload.city);
    if (payload.phone !== undefined) updates.phone = normalize(payload.phone);
    if (payload.fantasy_name !== undefined) updates.fantasy_name = normalize(payload.fantasy_name);

    if (Object.keys(updates).length === 0) {
      return NextResponse.json({ error: "No valid company fields provided" }, { status: 400 });
    }

    const { data, error } = await context.admin
      .from("companies")
      .update(updates)
      .eq("id", companyId)
      .select("*")
      .single();

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }

    return NextResponse.json({ success: true, company: data });
  } catch (error) {
    console.error("Company update error:", error);
    return NextResponse.json({ error: "Internal Server Error" }, { status: 500 });
  }
}
