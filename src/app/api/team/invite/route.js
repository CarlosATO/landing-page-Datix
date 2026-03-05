import { createClient } from '@supabase/supabase-js';
import { NextResponse } from 'next/server';

export async function POST(request) {
    try {
        const { email, password, fullName, globalRole, companyId, moduleRoles } = await request.json();

        // 1. Inicializar cliente Admin (ignora RLS)
        const supabaseAdmin = createClient(
            process.env.NEXT_PUBLIC_SUPABASE_URL,
            process.env.SUPABASE_SERVICE_ROLE_KEY,
            { auth: { autoRefreshToken: false, persistSession: false } }
        );

        // 2. Crear usuario en Auth de Supabase
        const { data: authData, error: authError } = await supabaseAdmin.auth.admin.createUser({
            email: email,
            password: password,
            email_confirm: true,
            user_metadata: { full_name: fullName }
        });

        if (authError) throw authError;

        // 3. Vincular usuario a la empresa con sus permisos y roles por módulo
        const { error: dbError } = await supabaseAdmin
            .from('company_users')
            .insert([{
                company_id: companyId,
                user_id: authData.user.id,
                role: globalRole,
                full_name: fullName,
                module_roles: moduleRoles // Objeto JSON, ej: {"POS": "CASHIER"}
            }]);

        if (dbError) throw dbError;

        return NextResponse.json({ success: true, user: authData.user }, { status: 200 });

    } catch (error) {
        console.error('Error invitando usuario:', error);
        return NextResponse.json({ error: error.message }, { status: 400 });
    }
}
