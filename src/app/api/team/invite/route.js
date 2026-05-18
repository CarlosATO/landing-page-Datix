import { createClient } from '@supabase/supabase-js';
import { NextResponse } from 'next/server';
import { requireCompanyMembership } from '@/lib/server/supabase';

const normalizeRoleMap = (value) => {
    if (!value || typeof value !== 'object') return {};
    return Object.fromEntries(
        Object.entries(value).map(([key, role]) => [key, (role ?? '').toString().toUpperCase()])
    );
};

export async function POST(request) {
    try {
        const body = await request.json();
        const { email, password, fullName, globalRole, companyId, moduleRoles } = body;

        if (!email || !password || !companyId) {
            throw new Error("Faltan campos obligatorios (email, password o companyId)");
        }

        if (password.length < 6) {
            throw new Error('La contraseña debe tener al menos 6 caracteres');
        }

        const normalizedGlobalRole = (globalRole || 'MEMBER').toString().toUpperCase();

        if (normalizedGlobalRole === 'OWNER' && context.membership.role !== 'OWNER') {
            return NextResponse.json({ error: 'Solo el dueño puede asignar rol OWNER' }, { status: 403 });
        }

        const context = await requireCompanyMembership(request, companyId, ['OWNER', 'MANAGER']);
        if (context.error) {
            return NextResponse.json({ error: context.error }, { status: context.status || 400 });
        }

        const supabaseAdmin = createClient(
            process.env.NEXT_PUBLIC_SUPABASE_URL,
            process.env.SUPABASE_SERVICE_ROLE_KEY,
            { auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false } }
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
                email: email,
                role: normalizedGlobalRole,
                full_name: fullName,
                module_roles: normalizeRoleMap(moduleRoles)
            }]);

        if (dbError) throw dbError;

        return NextResponse.json({ success: true, user: authData.user }, { status: 200 });

    } catch (error) {
        console.error('🔥 Error invitando usuario:', error.message || error);
        return NextResponse.json({ error: error.message }, { status: 400 });
    }
}

export async function PATCH(request) {
    try {
        const body = await request.json();
        const { companyId, userId, fullName, globalRole, moduleRoles } = body;

        if (!companyId || !userId) {
            throw new Error('Faltan campos obligatorios (companyId o userId)');
        }

        const context = await requireCompanyMembership(request, companyId, ['OWNER', 'MANAGER']);
        if (context.error) {
            return NextResponse.json({ error: context.error }, { status: context.status || 400 });
        }

        const supabaseAdmin = createClient(
            process.env.NEXT_PUBLIC_SUPABASE_URL,
            process.env.SUPABASE_SERVICE_ROLE_KEY,
            { auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false } }
        );

        const { data: targetMember, error: targetError } = await supabaseAdmin
            .from('company_users')
            .select('id, user_id, role')
            .eq('company_id', companyId)
            .eq('user_id', userId)
            .maybeSingle();

        if (targetError || !targetMember) {
            return NextResponse.json({ error: 'Miembro no encontrado' }, { status: 404 });
        }

        if (targetMember.role === 'OWNER' && context.membership.role !== 'OWNER') {
            return NextResponse.json({ error: 'No puedes modificar al dueño de la empresa' }, { status: 403 });
        }

        const payload = {};
        if (typeof fullName === 'string') payload.full_name = fullName;
        if (typeof globalRole === 'string') payload.role = globalRole;
        if (moduleRoles && typeof moduleRoles === 'object') payload.module_roles = normalizeRoleMap(moduleRoles);

        if ((payload.role || '').toString().toUpperCase() === 'OWNER' && context.membership.role !== 'OWNER') {
            return NextResponse.json({ error: 'Solo el dueño puede asignar rol OWNER' }, { status: 403 });
        }

        if (Object.keys(payload).length === 0) {
            return NextResponse.json({ error: 'No valid update fields provided' }, { status: 400 });
        }

        const { data, error: updateError } = await supabaseAdmin
            .from('company_users')
            .update(payload)
            .eq('company_id', companyId)
            .eq('user_id', userId)
            .select('id, company_id, user_id, role, full_name, email, module_roles, must_change_password')
            .single();

        if (updateError) throw updateError;

        return NextResponse.json({ success: true, member: data }, { status: 200 });

    } catch (error) {
        console.error('🔥 Error actualizando usuario:', error.message || error);
        return NextResponse.json({ error: error.message }, { status: 400 });
    }
}
