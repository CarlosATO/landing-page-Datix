import { createClient } from '@supabase/supabase-js';
import { NextResponse } from 'next/server';

export async function POST(request) {
    try {
        const body = await request.json();
        const { email, password, fullName, globalRole, companyId, moduleRoles } = body;

        if (!email || !password || !companyId) {
            throw new Error("Faltan campos obligatorios (email, password o companyId)");
        }

        const supabaseAdmin = createClient(
            process.env.NEXT_PUBLIC_SUPABASE_URL,
            process.env.SUPABASE_SERVICE_ROLE_KEY,
            { auth: { autoRefreshToken: false, persistSession: false } }
        );

        const { data: authData, error: authError } = await supabaseAdmin.auth.admin.createUser({
            email: email,
            password: password,
            email_confirm: true,
            user_metadata: { full_name: fullName }
        });

        if (authError) throw authError;

        const { error: dbError } = await supabaseAdmin
            .from('company_users')
            .insert([{
                company_id: companyId,
                user_id: authData.user.id,
                role: globalRole || 'MEMBER',
                full_name: fullName,
                module_roles: moduleRoles || {}
            }]);

        if (dbError) throw dbError;

        return NextResponse.json({ success: true, user: authData.user }, { status: 200 });

    } catch (error) {
        console.error('🔥 Error invitando usuario:', error.message || error);
        return NextResponse.json({ error: error.message }, { status: 400 });
    }
}
