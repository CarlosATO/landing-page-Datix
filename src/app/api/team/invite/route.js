import { NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

// Inicializa Supabase con la Service Role Key para tener privilegios de administrador
const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
    auth: {
        autoRefreshToken: false,
        persistSession: false
    }
});

export async function POST(req) {
    try {
        const { email, password, fullName, role, companyId, appAccess } = await req.json();

        // Validaciones básicas
        if (!email || !password || !companyId || !role) {
            return NextResponse.json({ error: 'Faltan campos obligatorios' }, { status: 400 });
        }

        // 1. Crear el usuario en la tabla de auth de Supabase
        const { data: authData, error: authError } = await supabaseAdmin.auth.admin.createUser({
            email,
            password,
            email_confirm: true,
            user_metadata: { full_name: fullName }
        });

        if (authError) {
            console.error('Error creando usuario Auth:', authError);
            return NextResponse.json({ error: authError.message }, { status: 400 });
        }

        const newUserId = authData.user.id;

        // 2. Insertar el perfil en la tabla pivot company_users
        const { error: insertError } = await supabaseAdmin
            .from('company_users')
            .insert({
                company_id: companyId,
                user_id: newUserId,
                role: role,
                full_name: fullName,
                app_access: appAccess || []
            });

        if (insertError) {
            console.error('Error vinculando usuario a empresa:', insertError);
            // Opcional: Podríamos eliminar el usuario de auth si falla la inserción para mantener consistencia
            return NextResponse.json({ error: insertError.message }, { status: 500 });
        }

        return NextResponse.json({ success: true, user: authData.user }, { status: 200 });

    } catch (error) {
        console.error('Error interno API invite:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}
