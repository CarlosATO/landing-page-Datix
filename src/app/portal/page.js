"use client";

import React, { useState, useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import { createBrowserClient } from "@supabase/ssr";
import {
    LayoutDashboard,
    CreditCard,
    Settings,
    LogOut,
    Store,
    Package,
    Pill,
    Users,
    ExternalLink,
    FileText,
    Check,
    Briefcase,
    Lock
} from "lucide-react";

const BRAND_PRIMARY = '#4C3073';

const AVAILABLE_APPS = [
    { id: 'POS', name: 'Caja POS', reversed: false, roles: [{ v: 'CASHIER', l: 'Cajero' }, { v: 'MANAGER', l: 'Jefe de Local' }] },
    { id: 'LOGISTICA', name: 'Logística', roles: [{ v: 'STOCKER', l: 'Bodeguero' }, { v: 'MANAGER', l: 'Jefe de Operaciones' }] },
    { id: 'RRHH', name: 'Recursos Humanos', roles: [{ v: 'ASSISTANT', l: 'Asistente' }, { v: 'ADMIN', l: 'Administrador' }] },
    { id: 'ADQUISICIONES', name: 'Adquisiciones', roles: [{ v: 'BUYER', l: 'Comprador' }, { v: 'MANAGER', l: 'Jefe de Compras' }] },
    { id: 'FARMACIAS', name: 'Farmacias', roles: [{ v: 'PHARMACIST', l: 'Químico Farmacéutico' }, { v: 'ASSISTANT', l: 'Asistente de Farmacia' }] }
];

const APP_OPENERS = {
    POS: { label: 'Caja POS', port: 5173, path: '/pos' },
    ADQUISICIONES: { label: 'Adquisiciones', port: 5174, path: '/dashboard-compras' },
    FARMACIAS: { label: 'Farmacias', port: 5175, path: '' }
};

const MODULE_METADATA_TO_ROLE = {
    pos: { POS: 'MANAGER' },
    adquisiciones: { ADQUISICIONES: 'MANAGER' },
    farmacias: { FARMACIAS: 'PHARMACIST' },
    logistica: { LOGISTICA: 'MANAGER' },
    rrhh: { RRHH: 'ADMIN' }
};

const toUpperValue = (value) => (value ?? '').toString().toUpperCase();

// Inicializa el cliente de Supabase
const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || "https://placeholder-url.supabase.co";
const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || "placeholder-key";
const supabase = createBrowserClient(supabaseUrl, supabaseKey);

export default function PortalDashboard() {
    const router = useRouter();

    const [user, setUser] = useState(null);
    const [company, setCompany] = useState(null);
    const [loading, setLoading] = useState(true);
    const [isBillingLoading, setIsBillingLoading] = useState(false);
    const [activeTab, setActiveTab] = useState('apps');
    const [userRole, setUserRole] = useState(null);
    const [team, setTeam] = useState([]);
    const [isSavingOnboarding, setIsSavingOnboarding] = useState(false);
    const [onboardingData, setOnboardingData] = useState({
        rut: '',
        activity: '',
        address: '',
        city: '',
        phone: '',
        fantasy_name: ''
    });

    // Estados para Gestión de Equipo
    const [teamMembers, setTeamMembers] = useState([]);
    const [teamViewMode, setTeamViewMode] = useState('list'); // 'list' | 'form'
    const [isInviting, setIsInviting] = useState(false);
    const [editingUserId, setEditingUserId] = useState(null);

    // Formulario de Invitación
    const [inviteEmail, setInviteEmail] = useState('');
    const [inviteName, setInviteName] = useState('');
    const [invitePassword, setInvitePassword] = useState('');
    const [inviteRole, setInviteRole] = useState('MEMBER');
    const [moduleRoles, setModuleRoles] = useState({});

    // Estado para forzar cambio de password al inicio
    const [needsPasswordChange, setNeedsPasswordChange] = useState(false);
    const [newPassword, setNewPassword] = useState('');
    const [confirmPassword, setConfirmPassword] = useState('');
    const [isChangingPassword, setIsChangingPassword] = useState(false);

    // Estado para saber a qué módulos tiene acceso el usuario base
    const [userAppAccess, setUserAppAccess] = useState({});

    const hasFetched = useRef(false);

    // Cargar Usuario y Empresa
    const hasProcessedHash = useRef(false);

    useEffect(() => {
        const fetchUserData = async () => {
            if (hasFetched.current) return;
            
            // 🔥 NUEVA ARQUITECTURA: Soporte SSO vía Hash en el Portal (Evita parpadeo de Login)
            if (!hasProcessedHash.current && typeof window !== 'undefined' && window.location.hash.includes('access_token')) {
                hasProcessedHash.current = true;
                try {
                    const hash = window.location.hash.substring(1);
                    const params = new URLSearchParams(hash);
                    const access_token = params.get('access_token');
                    const refresh_token = params.get('refresh_token');

                    if (access_token && refresh_token) {
                        window.history.replaceState(null, '', window.location.pathname);
                        const { error: sessionError } = await supabase.auth.setSession({ access_token, refresh_token });
                        if (sessionError) throw sessionError;
                        // No refrescamos manualmente aquí para evitar 429 (Rate Limit)
                    }
                } catch (err) {
                    console.error("Error sincronizando sesión en Portal:", err);
                }
            }

            hasFetched.current = true;
            
            setLoading(true);
            try {
                const { data: { user: currentUser }, error: sessionError } = await supabase.auth.getUser();

                if (sessionError || !currentUser) {
                    // Si el error es 429 (Rate Limit), no sacamos al usuario, esperamos reintento
                    if (sessionError?.status === 429) {
                        console.warn("Rate limit en Auth, reintentando en 2 segundos...");
                        setTimeout(fetchUserData, 2000);
                        return;
                    }
                    console.error("No hay sesión activa.", sessionError);
                    router.push('/login');
                    return;
                }

                setUser(currentUser);

                // 🔥 NUEVA ARQUITECTURA: Extraemos el company_id directamente del JWT (app_metadata)
                const jwtCompanyId = currentUser.app_metadata?.company_id;

                if (jwtCompanyId) {
                    // Cargar detalles de la empresa (RLS nos permitirá verla si el ID coincide)
                    const { data: compData, error: compError } = await supabase
                        .from("companies")
                        .select("*")
                        .single();

                    if (!compError && compData) {
                        setCompany(compData);
                        
                        // Sincronizamos onboarding data con lo que ya tenga la empresa
                        setOnboardingData({
                            rut: compData.rut || '',
                            activity: compData.activity || '',
                            address: compData.address || '',
                            city: compData.city || '',
                            phone: compData.phone || '',
                            fantasy_name: compData.fantasy_name || ''
                        });

                        // 🔥 NUEVA ARQUITECTURA: Extraemos Rol y Plan directamente del JWT
                        // Ya no necesitamos hacer el select a 'company_users' para el rol
                        const role = currentUser.app_metadata?.role || 'MEMBER';
                        setUserRole(role);
                        setUserAppAccess(currentUser.app_metadata?.module_roles || {});

                        // Cargar settings del usuario como módulo_roles y must_change_password
                        const { data: myUserRel } = await supabase
                            .from('company_users')
                            .select('id, module_roles, must_change_password, full_name, email')
                            .eq('user_id', currentUser.id)
                            .eq('company_id', jwtCompanyId)
                            .single();

                        let effectiveModuleRoles = myUserRel?.module_roles || currentUser.app_metadata?.module_roles || {};

                        // Auto-repair: si el usuario nuevo quedó sin módulos, intentamos inferir desde user_metadata.modulo_inicial
                        if (Object.keys(effectiveModuleRoles).length === 0) {
                            const inferred = MODULE_METADATA_TO_ROLE[currentUser.user_metadata?.modulo_inicial];
                            if (inferred && myUserRel?.id) {
                                const { error: repairError } = await supabase
                                    .from('company_users')
                                    .update({ module_roles: inferred })
                                    .eq('id', myUserRel.id);
                                if (!repairError) {
                                    effectiveModuleRoles = inferred;
                                }
                            }
                        }
                        
                        // AUTO-HEALING: El trigger de DB original no graba nombre ni correo para el Dueño.
                        // Reparamos este registro en tiempo real de forma silenciosa la primera vez.
                        if (role === 'OWNER' && myUserRel && (!myUserRel.full_name || !myUserRel.email)) {
                            const nameFromAuth = currentUser.user_metadata?.full_name || 'Dueño Registrado';
                            const emailFromAuth = currentUser.email;
                            await supabase
                                .from('company_users')
                                .update({ full_name: nameFromAuth, email: emailFromAuth })
                                .eq('id', myUserRel.id);
                        }
                        
                        // Los dueños NUNCA deben cambiar obligatoriamente su contraseña por esta vía.
                        if (role !== 'OWNER' && myUserRel?.must_change_password) {
                            setNeedsPasswordChange(true);
                        }

                        // Si es Owner o Manager, cargar equipo
                        if (role === 'OWNER' || role === 'MANAGER') {
                            const { data: teamData } = await supabase
                                .from('company_users')
                                .select('*');
                            if (teamData) setTeamMembers(teamData);
                        }
                        setUserAppAccess(effectiveModuleRoles);
                    } else {
                        console.error("No se pudo cargar la configuración de la empresa vinculada al JWT.");
                    }
                } else {
                    console.warn("El token del usuario no tiene un company_id asignado.");
                    // Fallback: Si no hay company_id, intentamos ver si tiene una empresa creada por él
                    const { data: fallbackComp } = await supabase
                        .from("companies")
                        .select("*")
                        .limit(1)
                        .single();
                    if (fallbackComp) setCompany(fallbackComp);
                }
            } catch (err) {
                console.error("Error al cargar datos:", err);
            } finally {
                setLoading(false);
            }
        };

        fetchUserData();
    }, [router]);

    const handleLogout = async () => {
        setLoading(true);
        await supabase.auth.signOut();
        router.push('/login');
    };

    const handleChangePassword = async (e) => {
        e.preventDefault();
        if (newPassword !== confirmPassword) {
            alert("Las contraseñas no coinciden");
            return;
        }
        if (newPassword.length < 6) {
            alert("La contraseña debe tener al menos 6 caracteres");
            return;
        }

        setIsChangingPassword(true);
        try {
            // Actualizar contraseña en el sistema Auth
            const { error: authError } = await supabase.auth.updateUser({
                password: newPassword
            });
            if (authError) throw authError;

            // Actualizar bandera relacional
            const { error: dbError } = await supabase
                .from('company_users')
                .update({ must_change_password: false })
                .eq('user_id', user.id)
                .eq('company_id', company.id);
            if (dbError) throw dbError;

            alert("Contraseña actualizada con éxito.");
            setNeedsPasswordChange(false);
        } catch (error) {
            console.error("Error al cambiar contraseña:", error);
            alert("Error: " + error.message);
        } finally {
            setIsChangingPassword(false);
        }
    };

    const handleSaveOnboarding = async (e) => {
        e.preventDefault();
        setIsSavingOnboarding(true);
        try {
            const normalizedOnboarding = {
                rut: toUpperValue(onboardingData.rut),
                activity: toUpperValue(onboardingData.activity),
                address: toUpperValue(onboardingData.address),
                city: toUpperValue(onboardingData.city),
                phone: toUpperValue(onboardingData.phone),
                fantasy_name: toUpperValue(onboardingData.fantasy_name) || toUpperValue(company.name)
            };
            const { error } = await supabase
                .from('companies')
                .update({
                    rut: normalizedOnboarding.rut,
                    activity: normalizedOnboarding.activity,
                    address: normalizedOnboarding.address,
                    city: normalizedOnboarding.city,
                    phone: normalizedOnboarding.phone,
                    fantasy_name: normalizedOnboarding.fantasy_name
                })
                .eq('id', company.id);

            if (error) throw error;
             
            // Actualizamos la empresa en el estado local para desbloquear instantáneamente la UI
            setCompany(prev => ({
                ...prev,
                rut: normalizedOnboarding.rut,
                activity: normalizedOnboarding.activity,
                address: normalizedOnboarding.address,
                city: normalizedOnboarding.city,
                phone: normalizedOnboarding.phone,
                fantasy_name: normalizedOnboarding.fantasy_name
            }));
            setOnboardingData(normalizedOnboarding);
        } catch (err) {
            console.error("Error guardando onboarding:", err);
            alert("No se pudo guardar la configuración. Revisa los datos.");
        } finally {
            setIsSavingOnboarding(false);
        }
    };

    const handleOpenPOS = async () => {
        const { data: { session } } = await supabase.auth.getSession();
        const hostname = typeof window !== 'undefined' ? window.location.hostname : 'localhost';
        if (session) {
            const url = `http://${hostname}:5173/pos#access_token=${session.access_token}&refresh_token=${session.refresh_token}`;
            window.location.href = url;
        } else {
            window.location.href = '/login';
        }
    };

    const handleOpenAdquisiciones = async () => {
        const { data: { session } } = await supabase.auth.getSession();
        const hostname = typeof window !== 'undefined' ? window.location.hostname : 'localhost';
        if (session) {
            const url = `http://${hostname}:5174/dashboard-compras#access_token=${session.access_token}&refresh_token=${session.refresh_token}`;
            window.location.href = url;
        } else {
            window.location.href = '/login';
        }
    };

    const handleOpenFarmacias = async () => {
        const { data: { session } } = await supabase.auth.getSession();
        const hostname = typeof window !== 'undefined' ? window.location.hostname : 'localhost';
        if (session) {
            const url = `http://${hostname}:5175#access_token=${session.access_token}&refresh_token=${session.refresh_token}`;
            window.location.href = url;
        } else {
            window.location.href = '/login';
        }
    };

    const handleOpenApp = async (appId) => {
        if (appId === 'POS') return handleOpenPOS();
        if (appId === 'ADQUISICIONES') return handleOpenAdquisiciones();
        if (appId === 'FARMACIAS') return handleOpenFarmacias();
        alert('Este módulo estará disponible próximamente.');
    };

    const handleToggleModule = (appId, defaultRole) => {
        setModuleRoles(prev => {
            const next = { ...prev };
            if (next[appId]) {
                delete next[appId];
            } else {
                next[appId] = defaultRole;
            }
            return next;
        });
    };

    const handleChangeModuleRole = (appId, newRole) => {
        setModuleRoles(prev => ({
            ...prev,
            [appId]: newRole
        }));
    };

    const handleEditUser = (member) => {
        setEditingUserId(member.user_id);
        setInviteEmail(member.email || ''); 
        setInviteName(member.full_name || '');
        setInvitePassword(''); 
        setInviteRole(member.role || 'MEMBER');
        setModuleRoles(member.module_roles || {});
        setTeamViewMode('form');
    };

    const handleInviteUser = async (e) => {
        e.preventDefault();
        setIsInviting(true);
        try {
            if (editingUserId) {
                // MODO EDICIÓN: Actualizar company_users
                const { error: updateError } = await supabase
                    .from('company_users')
                    .update({
                        full_name: inviteName,
                        role: inviteRole,
                        module_roles: moduleRoles
                    })
                    .eq('user_id', editingUserId)
                    .eq('company_id', company.id);
                
                if (updateError) throw new Error(updateError.message);
                alert("Usuario actualizado con éxito!");
            } else {
                // MODO CREACIÓN: Llamar API de Invitación Admin
                const payload = {
                    email: inviteEmail,
                    password: invitePassword,
                    fullName: inviteName,
                    globalRole: inviteRole,
                    companyId: company.id,
                    moduleRoles: moduleRoles
                };

                const res = await fetch('/api/team/invite', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(payload),
                });

                const data = await res.json();
                if (!res.ok) throw new Error(data.error || 'Error al crear usuario');
                alert("Usuario invitado con éxito!");
            }

            // Recargar lista
            const { data: teamData } = await supabase
                .from('company_users')
                .select('*');
            if (teamData) setTeamMembers(teamData);

            setTeamViewMode('list');
            setEditingUserId(null);
            setInviteEmail('');
            setInviteName('');
            setInvitePassword('');
            setInviteRole('MEMBER');
            setModuleRoles({});
        } catch (error) {
            console.error("Error en el cliente:", error);
            alert(error.message);
        } finally {
            setIsInviting(false);
        }
    };

    const handleManageBilling = async () => {
        if (!company?.id) {
            alert("No se pudo detectar tu Empresa.");
            return;
        }

        setIsBillingLoading(true);
        try {
            const response = await fetch('/api/stripe/portal', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ companyId: company.id })
            });
            const data = await response.json();

            if (data.url) {
                window.location.href = data.url;
            } else {
                console.error("No se recibió URL de Stripe", data);
                setIsBillingLoading(false);
            }
        } catch (error) {
            console.error("Error abriendo portal:", error);
            setIsBillingLoading(false);
        }
    };

    if (loading) {
        return (
            <div className="flex min-h-screen items-center justify-center bg-white p-8">
                <div className="text-center">
                    <div className="h-10 w-10 animate-spin rounded-full border-4 border-[#4C3073] border-t-transparent mx-auto mb-4"></div>
                    <p className="text-slate-500 font-medium">Buscando permisos en tu ecosistema...</p>
                </div>
            </div>
        );
    }

    if (needsPasswordChange) {
        return (
            <div className="flex flex-col h-screen items-center justify-center font-sans tracking-tight" style={{ backgroundColor: '#45316D' }}>
                <div className="w-full max-w-md p-10 bg-white rounded-[2rem] shadow-2xl mx-4 animate-in fade-in duration-500">
                    <div className="flex justify-center mb-6">
                        <div className="p-4 bg-purple-50 rounded-2xl shadow-inner border border-purple-100">
                            <Lock className="h-8 w-8 text-[#5B4385]" />
                        </div>
                    </div>
                    <div className="text-center mb-8">
                        <h2 className="text-2xl font-black text-slate-900 mb-2">Paso de Seguridad</h2>
                        <p className="text-slate-500 text-sm">
                            Tu empleador te ha invitado al sistema con una contraseña temporal. Por seguridad de tus accesos, debes crear tu propia contraseña permanentemente.
                        </p>
                    </div>

                    <form onSubmit={handleChangePassword} className="space-y-4">
                        <div className="space-y-1 text-left">
                            <label className="text-[11px] font-bold uppercase tracking-widest text-slate-400 ml-1">Nueva Contraseña</label>
                            <input 
                                type="password"
                                required
                                value={newPassword}
                                onChange={(e) => setNewPassword(e.target.value)}
                                className="w-full rounded-2xl border border-slate-200 bg-slate-50 py-4 px-5 text-slate-900 focus:bg-white focus:outline-none focus:ring-2 focus:ring-purple-500/50 transition-all font-medium placeholder:text-slate-300"
                                placeholder="Mínimo 6 caracteres"
                            />
                        </div>
                        <div className="space-y-1 text-left">
                            <label className="text-[11px] font-bold uppercase tracking-widest text-slate-400 ml-1">Confirmar Nueva Contraseña</label>
                            <input 
                                type="password"
                                required
                                value={confirmPassword}
                                onChange={(e) => setConfirmPassword(e.target.value)}
                                className="w-full rounded-2xl border border-slate-200 bg-slate-50 py-4 px-5 text-slate-900 focus:bg-white focus:outline-none focus:ring-2 focus:ring-purple-500/50 transition-all font-medium placeholder:text-slate-300"
                                placeholder="Repite tu contraseña..."
                            />
                        </div>

                        <div className="pt-4">
                            <button 
                                type="submit"
                                disabled={isChangingPassword}
                                style={{ backgroundColor: BRAND_PRIMARY }}
                                className="w-full rounded-2xl px-6 py-4 text-white font-bold shadow-xl shadow-purple-900/40 hover:opacity-90 active:scale-[0.98] transition-all disabled:opacity-50 disabled:scale-100"
                            >
                                {isChangingPassword ? "Actualizando Seguridad..." : "Guardar y Entrar al Portal"}
                            </button>
                        </div>
                    </form>
                </div>
            </div>
        );
    }

    const isSubscriptionActive = company?.subscription_status === 'active' || company?.subscription_status === 'trialing';
    const isPrivilegedUser = userRole === 'OWNER' || userRole === 'MANAGER';
    const enabledAppIds = new Set(
        Object.entries(userAppAccess || {})
            .filter(([, role]) => Boolean(role))
            .map(([appId]) => appId)
    );
    const visibleApps = AVAILABLE_APPS.filter((app) => enabledAppIds.has(app.id));
    const noModuleAccess = visibleApps.length === 0;

    return (
        <div className="flex flex-col h-screen font-sans" style={{ backgroundColor: '#45316D' }}>
            {/* Navbar Superior (Estilo Odoo/ERP) */}
            <nav className="flex h-12 w-full items-center justify-between px-4 text-white shadow-lg" style={{ backgroundColor: '#5B4385' }}>
                <div 
                    className="flex items-center gap-4 cursor-pointer hover:opacity-80 transition-opacity"
                    onClick={() => setActiveTab('apps')}
                >
                    <button className="p-1 hover:bg-white/10 rounded-md transition-colors">
                        <LayoutDashboard className="h-6 w-6" />
                    </button>
                    <img
                        src="/imagen/logo_datix.png"
                        alt="Datix Logo"
                        className="h-8 w-auto brightness-0 invert opacity-90 transition-all hover:opacity-100"
                    />
                </div>

                <div className="flex items-center gap-2">
                    {(userRole === 'OWNER' || userRole === 'MANAGER') && (
                        <>
                            <button 
                                onClick={() => setActiveTab('team')}
                                title="Gestión de Equipo"
                                className={`p-2 hover:bg-white/10 rounded-md transition-colors ${activeTab === 'team' ? 'bg-white/20' : ''}`}
                            >
                                <Users className="h-5 w-5" />
                            </button>
                            <button 
                                onClick={() => setActiveTab('billing')}
                                title="Facturación"
                                className={`p-2 hover:bg-white/10 rounded-md transition-colors ${activeTab === 'billing' ? 'bg-white/20' : ''}`}
                            >
                                <CreditCard className="h-5 w-5" />
                            </button>
                            <button 
                                onClick={() => setActiveTab('settings')}
                                title="Configuración"
                                className={`p-2 hover:bg-white/10 rounded-md transition-colors ${activeTab === 'settings' ? 'bg-white/20' : ''}`}
                            >
                                <Settings className="h-5 w-5" />
                            </button>
                        </>
                    )}
                    
                    <div className="h-6 w-px bg-white/20 mx-2"></div>

                    <div className="flex items-center gap-3">
                        <span className="hidden sm:inline-block text-xs font-semibold tracking-wide uppercase opacity-90">
                            {user?.email?.split('@')[0] || "USUARIO"}
                        </span>
                        <div className="h-8 w-8 rounded-md bg-white/20 flex items-center justify-center font-bold text-xs ring-1 ring-white/30">
                            {user?.email?.[0].toUpperCase() || "U"}
                        </div>
                        <button onClick={handleLogout} className="p-2 hover:bg-red-500/20 rounded-md transition-colors text-red-200" title="Cerrar Sesión">
                            <LogOut className="h-4 w-4" />
                        </button>
                    </div>
                </div>
            </nav>

            {/* Área de Contenido Dinámico (Estilo ERP) */}
            <main className="flex-1 overflow-y-auto">
                {activeTab === 'apps' ? (
                    <div className="p-8 sm:p-16">
                        <div className="mx-auto max-w-5xl">
                            <div className="grid grid-cols-2 gap-8 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 text-center">
                                
                                {/* Onboarding Check: Si faltan datos clave, bloqueamos las Apps */}
                                {(!company?.rut || !company?.address || !company?.activity) ? (
                                    <div className="col-span-full animate-in fade-in zoom-in duration-500">
                                        <div className="mx-auto max-w-2xl overflow-hidden rounded-3xl border border-white/10 bg-white/5 shadow-2xl backdrop-blur-xl">
                                            <div className="bg-gradient-to-r from-purple-600/20 to-blue-600/20 p-8 border-b border-white/5">
                                                <div className="flex items-center gap-4 mb-2">
                                                    <div className="p-3 bg-white/10 rounded-2xl">
                                                        <Briefcase className="h-8 w-8 text-white" />
                                                    </div>
                                                    <div>
                                                        <h2 className="text-2xl font-bold text-white">¡Bienvenido a Datix!</h2>
                                                        <p className="text-white/60 text-sm">Completa el perfil de tu empresa para habilitar los módulos.</p>
                                                    </div>
                                                </div>
                                            </div>

                                            <form onSubmit={handleSaveOnboarding} className="p-8 space-y-6">
                                                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                                                    <div className="space-y-2">
                                                        <label className="text-xs font-bold uppercase tracking-widest text-white/40">RUT Empresa *</label>
                                                        <input 
                                                            required
                                                            placeholder="76.xxx.xxx-x"
                                                            value={onboardingData.rut}
                                                            onChange={(e) => setOnboardingData({...onboardingData, rut: toUpperValue(e.target.value)})}
                                                            className="w-full rounded-xl border-white/10 bg-white/5 px-4 py-3 text-white placeholder:text-white/20 focus:ring-2 focus:ring-purple-500/50 outline-none transition-all"
                                                        />
                                                    </div>
                                                    <div className="space-y-2">
                                                        <label className="text-xs font-bold uppercase tracking-widest text-white/40">Giro / Actividad *</label>
                                                        <input 
                                                            required
                                                            placeholder="Ej: Retail, Ferretería..."
                                                            value={onboardingData.activity}
                                                            onChange={(e) => setOnboardingData({...onboardingData, activity: toUpperValue(e.target.value)})}
                                                            className="w-full rounded-xl border-white/10 bg-white/5 px-4 py-3 text-white placeholder:text-white/20 focus:ring-2 focus:ring-purple-500/50 outline-none transition-all"
                                                        />
                                                    </div>
                                                    <div className="space-y-2 md:col-span-2">
                                                        <label className="text-xs font-bold uppercase tracking-widest text-white/40">Dirección Comercial *</label>
                                                        <input 
                                                            required
                                                            placeholder="Calle, Número, Ciudad"
                                                            value={onboardingData.address}
                                                            onChange={(e) => setOnboardingData({...onboardingData, address: toUpperValue(e.target.value)})}
                                                            className="w-full rounded-xl border-white/10 bg-white/5 px-4 py-3 text-white placeholder:text-white/20 focus:ring-2 focus:ring-purple-500/50 outline-none transition-all"
                                                        />
                                                    </div>
                                                    <div className="space-y-2">
                                                        <label className="text-xs font-bold uppercase tracking-widest text-white/40">Teléfono</label>
                                                        <input 
                                                            placeholder="+56 9 ..."
                                                            value={onboardingData.phone}
                                                            onChange={(e) => setOnboardingData({...onboardingData, phone: toUpperValue(e.target.value)})}
                                                            className="w-full rounded-xl border-white/10 bg-white/5 px-4 py-3 text-white placeholder:text-white/20 focus:ring-2 focus:ring-purple-500/50 outline-none transition-all"
                                                        />
                                                    </div>
                                                    <div className="space-y-2">
                                                        <label className="text-xs font-bold uppercase tracking-widest text-white/40">Ciudad</label>
                                                        <input 
                                                            placeholder="Santiago, Concepción..."
                                                            value={onboardingData.city}
                                                            onChange={(e) => setOnboardingData({...onboardingData, city: toUpperValue(e.target.value)})}
                                                            className="w-full rounded-xl border-white/10 bg-white/5 px-4 py-3 text-white placeholder:text-white/20 focus:ring-2 focus:ring-purple-500/50 outline-none transition-all"
                                                        />
                                                    </div>
                                                </div>

                                                <button 
                                                    type="submit"
                                                    disabled={isSavingOnboarding}
                                                    style={{ backgroundColor: BRAND_PRIMARY }}
                                                    className="w-full mt-4 rounded-2xl px-6 py-4 text-white font-bold shadow-lg hover:opacity-90 active:scale-[0.98] transition-all disabled:opacity-50"
                                                >
                                                    {isSavingOnboarding ? "Guardando..." : "Finalizar Configuración e Ingresar"}
                                                </button>
                                            </form>
                                        </div>
                                    </div>
                                ) : (
                                    <>
                                        {visibleApps.map((app) => {
                                            const Icon = app.id === 'POS'
                                                ? Store
                                                : app.id === 'ADQUISICIONES'
                                                    ? FileText
                                                    : app.id === 'FARMACIAS'
                                                        ? Pill
                                                        : app.id === 'LOGISTICA'
                                                            ? Package
                                                            : Users;
                                            const opener = APP_OPENERS[app.id];
                                            const isAvailable = Boolean(opener);

                                            return (
                                                <div key={app.id} className={`group flex flex-col items-center gap-3 ${isAvailable ? '' : 'opacity-50'}`}>
                                                    <button
                                                        onClick={() => handleOpenApp(app.id)}
                                                        className={`relative flex h-24 w-24 items-center justify-center rounded-2xl ring-1 transition-all ${isAvailable
                                                            ? 'bg-white/10 shadow-xl ring-white/20 hover:scale-105 hover:bg-white/20 hover:shadow-purple-900/40 active:scale-95'
                                                            : 'bg-white/5 shadow-inner ring-white/10 cursor-not-allowed'
                                                            }`}
                                                    >
                                                        <div className="absolute inset-0 rounded-2xl bg-gradient-to-br from-white/10 to-transparent"></div>
                                                        <Icon className={`h-10 w-10 ${isAvailable ? 'text-white opacity-90 group-hover:opacity-100' : 'text-white/40'}`} />
                                                    </button>
                                                    <span className={`text-sm font-medium ${isAvailable ? 'text-white/90 group-hover:text-white' : 'text-white/50'}`}>
                                                        {isAvailable ? app.name : `${app.name} (Prox)`}
                                                    </span>
                                                </div>
                                            );
                                        })}

                                        {/* Estado Vacío: sin módulos asignados */}
                                        {noModuleAccess && (
                                            <div className="col-span-full py-20 text-center animate-in fade-in duration-700">
                                                <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-white/5 ring-1 ring-white/10">
                                                    <Lock className="h-8 w-8 text-white/20" />
                                                </div>
                                                <h3 className="text-xl font-bold text-white">Sin módulos asignados</h3>
                                                <p className="mt-2 text-white/40 max-w-sm mx-auto">
                                                    {isPrivilegedUser
                                                        ? 'Debes asignar al menos un módulo para comenzar la prueba.'
                                                        : 'Tu cuenta aún no tiene permisos para acceder a módulos. Contacta al administrador de tu empresa para que te asigne un rol.'}
                                                </p>
                                            </div>
                                        )}
                                    </>
                                )}

                                {/* Separador visual para próximos lanzamientos si es necesario */}
                            </div>
                        </div>
                    </div>
                ) : (
                    <div className="min-h-full p-6 sm:p-12 animate-in fade-in duration-300">
                        <div className="mx-auto max-w-7xl">
                            {activeTab === 'team' && renderTeamTab()}
                            {activeTab === 'billing' && renderBillingTab()}
                            {activeTab === 'settings' && renderSettingsTab()}
                        </div>
                    </div>
                )}
            </main>

        </div>
    );

    // Funciones de renderizado para simplificar el componente principal
    function renderTeamTab() {
        return (
            <div className="mx-auto max-w-6xl">
                {/* Odoo Style Control Panel */}
                <header className="mb-8 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
                    <div>
                        <nav className="flex items-center gap-2 text-sm text-white/50 mb-1">
                            <button 
                                onClick={() => {
                                    setEditingUserId(null);
                                    setTeamViewMode('list');
                                }}
                                className={`hover:text-white transition-colors ${teamViewMode === 'list' ? 'font-bold text-white' : ''}`}
                            >
                                Mi Equipo
                            </button>
                            {teamViewMode === 'form' && (
                                <>
                                    <span>/</span>
                                    <span className="font-bold text-white">{editingUserId ? 'Editar' : 'Nuevo'}</span>
                                </>
                            )}
                        </nav>
                        <h1 className="text-2xl font-bold tracking-tight text-white sm:text-3xl">
                            {teamViewMode === 'list' ? 'Mi Equipo' : (editingUserId ? 'Editar Colaborador' : 'Nuevo Colaborador')}
                        </h1>
                    </div>
                    
                    <div className="flex items-center gap-3">
                        {teamViewMode === 'list' ? (
                            <>
                                <button
                                    onClick={() => {
                                        setEditingUserId(null);
                                        setInviteEmail('');
                                        setInviteName('');
                                        setInvitePassword('');
                                        setInviteRole('MEMBER');
                                        setModuleRoles({});
                                        setTeamViewMode('form');
                                    }}
                                    style={{ backgroundColor: BRAND_PRIMARY }}
                                    className="inline-flex items-center justify-center gap-2 rounded-lg text-white shadow-sm hover:bg-brand-accent transition-colors px-4 py-2 text-sm font-semibold"
                                >
                                    + Invitar Miembro
                                </button>
                                <button
                                    onClick={() => setActiveTab('apps')}
                                    className="inline-flex items-center justify-center gap-2 rounded-lg bg-white/10 border border-white/20 text-white shadow-sm hover:bg-white/20 transition-colors px-4 py-2 text-sm font-semibold"
                                >
                                    Cerrar
                                </button>
                            </>
                        ) : (
                            <>
                                <button
                                    onClick={handleInviteUser}
                                    disabled={isInviting}
                                    style={{ backgroundColor: BRAND_PRIMARY }}
                                    className="inline-flex items-center justify-center gap-2 rounded-lg text-white shadow-sm hover:bg-white/20 transition-colors px-6 py-2 text-sm font-semibold"
                                >
                                    {isInviting ? "Invitando..." : "Guardar"}
                                </button>
                                <button
                                    onClick={() => setTeamViewMode('list')}
                                    className="inline-flex items-center justify-center gap-2 rounded-lg bg-white/5 border border-white/10 text-white/70 shadow-sm hover:bg-white/10 hover:text-white transition-colors px-6 py-2 text-sm font-semibold"
                                >
                                    Descartar
                                </button>
                            </>
                        )}
                    </div>
                </header>

                {teamViewMode === 'list' ? (
                    <div className="rounded-xl border border-white/10 bg-white/5 overflow-hidden shadow-xl backdrop-blur-sm">
                        <table className="w-full text-left text-sm whitespace-nowrap">
                            <thead className="bg-white/5 text-white/50 border-b border-white/10">
                                <tr>
                                    <th className="px-6 py-4 font-semibold text-white/70">Nombre</th>
                                    <th className="px-6 py-4 font-semibold text-white/70">Rol</th>
                                    <th className="px-6 py-4 font-semibold text-white/70">Acceso Apps</th>
                                    <th className="px-6 py-4 font-semibold text-right text-white/70">Acciones</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-white/5 text-white">
                                {teamMembers.map((member, idx) => (
                                    <tr key={idx} className="hover:bg-white/5 transition-colors">
                                        <td className="px-6 py-4 font-medium">{member.full_name || 'Desconocido'}</td>
                                        <td className="px-6 py-4">
                                            <span className={`inline-flex items-center rounded-md px-2.5 py-1 text-xs font-semibold ring-1 ring-inset ${member.role === 'OWNER' ? 'bg-white/20 text-white ring-white/30' :
                                                member.role === 'MANAGER' ? 'bg-white/10 text-white/80 ring-white/20' :
                                                    'bg-green-500/20 text-green-300 ring-green-500/30'
                                                }`}>
                                                {member.role || 'CASHIER'}
                                            </span>
                                        </td>
                                        <td className="px-6 py-4">
                                            <div className="flex items-center gap-1.5 flex-wrap">
                                                {member.module_roles && Object.entries(member.module_roles).map(([appId, role]) => (
                                                    <span 
                                                        key={appId} 
                                                        className="inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-bold ring-1 ring-inset uppercase tracking-wider bg-white/10 text-white/70 border border-white/5"
                                                    >
                                                        {appId}: {role}
                                                    </span>
                                                ))}
                                                {(!member.module_roles || Object.keys(member.module_roles).length === 0) && <span className="text-white/30 italic text-xs">Sin acceso</span>}
                                            </div>
                                        </td>
                                        <td className="px-6 py-4 text-right">
                                            <button 
                                                onClick={() => handleEditUser(member)}
                                                className="text-white/50 hover:text-white font-medium transition-colors focus:outline-none"
                                            >
                                                Editar
                                            </button>
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                ) : (
                    /* Form View */
                    <div className="rounded-xl border border-white/10 bg-white/5 shadow-xl overflow-hidden p-8 animate-in fade-in slide-in-from-bottom-2 duration-300 backdrop-blur-md">
                        <form className="max-w-5xl">
                            <div className="grid grid-cols-1 md:grid-cols-2 gap-x-16 gap-y-8">
                                <div className="space-y-6">
                                    <h3 className="text-xs font-bold uppercase tracking-widest text-white/40 border-b border-white/5 pb-2 mb-6">Datos del Colaborador</h3>
                                    <div className="grid grid-cols-3 items-center gap-4">
                                        <label className="text-sm font-medium text-white/50 text-right">Nombre</label>
                                        <input
                                            type="text"
                                            required
                                            value={inviteName}
                                            onChange={(e) => setInviteName(e.target.value)}
                                            className="col-span-2 rounded-md border-white/10 bg-white/5 py-1.5 text-sm text-white focus:ring-2 focus:ring-white/20 transition-all placeholder:text-white/20"
                                            placeholder="ej. Juan Pérez"
                                        />
                                    </div>
                                    <div className="grid grid-cols-3 items-center gap-4">
                                        <label className="text-sm font-medium text-white/50 text-right">Email</label>
                                        <input
                                            type="email"
                                            required={!editingUserId}
                                            disabled={!!editingUserId}
                                            value={inviteEmail}
                                            onChange={(e) => setInviteEmail(e.target.value)}
                                            className="col-span-2 rounded-md border-white/10 bg-white/5 py-1.5 text-sm text-white focus:ring-2 focus:ring-white/20 transition-all placeholder:text-white/20 disabled:opacity-50 disabled:cursor-not-allowed"
                                            placeholder={editingUserId ? "Correo no especificado o reservado" : "juan@datix.cl"}
                                        />
                                    </div>
                                    <div className="grid grid-cols-3 items-center gap-4">
                                        <label className="text-sm font-medium text-white/50 text-right">Contraseña Inicial</label>
                                        <input
                                            type="text"
                                            required={!editingUserId}
                                            disabled={!!editingUserId}
                                            value={invitePassword}
                                            onChange={(e) => setInvitePassword(e.target.value)}
                                            className="col-span-2 rounded-md border-white/10 bg-white/5 py-1.5 text-sm text-white focus:ring-2 focus:ring-white/20 transition-all placeholder:text-white/20 disabled:opacity-50 disabled:cursor-not-allowed"
                                            placeholder={editingUserId ? "No modificable desde aquí" : "Ej: Temporal123!"}
                                        />
                                    </div>
                                    <div className="grid grid-cols-3 items-center gap-4">
                                        <label className="text-sm font-medium text-white/50 text-right">Rol Portal</label>
                                        <select
                                            value={inviteRole}
                                            onChange={(e) => setInviteRole(e.target.value)}
                                            className="col-span-2 rounded-md border-white/10 bg-[#5B4385] py-1.5 text-sm text-white focus:ring-2 focus:ring-white/20 transition-all"
                                        >
                                            <option value="MEMBER">Miembro / Empleado Base</option>
                                            <option value="OWNER">Dueño / Admin Total</option>
                                        </select>
                                    </div>
                                </div>
                                <div className="space-y-4">
                                    <h3 className="text-xs font-bold uppercase tracking-widest text-white/40 border-b border-white/5 pb-2 mb-6">Permisos por Módulo</h3>
                                    <div className="grid grid-cols-1 gap-3">
                                        {AVAILABLE_APPS.map((app) => (
                                            <div
                                                key={app.id}
                                                className={`p-3 rounded-lg border transition-all ${moduleRoles[app.id]
                                                    ? 'bg-white/10 border-white/20 shadow-lg'
                                                    : 'border-white/5 bg-white/5'
                                                    }`}
                                            >
                                                <div
                                                    className="flex items-center justify-between cursor-pointer"
                                                    onClick={() => handleToggleModule(app.id, app.roles[0].v)}
                                                >
                                                    <div className="flex items-center gap-3">
                                                        <div 
                                                            className={`flex h-4 w-4 shrink-0 items-center justify-center rounded border transition-colors ${moduleRoles[app.id] ? 'bg-white text-[#45316D] border-white' : 'border-white/20 bg-transparent'}`}
                                                        >
                                                            {moduleRoles[app.id] && <Check className="h-2.5 w-2.5 stroke-[3px]" />}
                                                        </div>
                                                        <span className={`text-sm font-bold ${moduleRoles[app.id] ? 'text-white' : 'text-white/40'}`}>{app.name}</span>
                                                    </div>
                                                    {moduleRoles[app.id] && (
                                                        <select
                                                            value={moduleRoles[app.id]}
                                                            onClick={(e) => e.stopPropagation()}
                                                            onChange={(e) => handleChangeModuleRole(app.id, e.target.value)}
                                                            className="rounded-md border-white/10 bg-[#5B4385] px-2 py-0.5 text-xs font-medium text-white focus:ring-2 focus:ring-white/20 transition-all ml-4"
                                                        >
                                                            {app.roles.map(r => (
                                                                <option key={r.v} value={r.v}>{r.l}</option>
                                                            ))}
                                                        </select>
                                                    )}
                                                </div>
                                            </div>
                                        ))}
                                    </div>
                                </div>
                            </div>
                        </form>
                    </div>
                )}
            </div>
        );
    }

    function renderBillingTab() {
        return (
            <div className="mx-auto max-w-4xl">
                <header className="mb-8 flex items-center justify-between">
                    <div>
                        <h1 className="text-2xl font-bold tracking-tight text-white sm:text-3xl">Facturación</h1>
                        <p className="mt-1 text-sm text-white/60">Gestiona tu suscripción y métodos de pago.</p>
                    </div>
                    <button
                        onClick={() => setActiveTab('apps')}
                        className="inline-flex items-center justify-center gap-2 rounded-lg bg-white/10 border border-white/20 text-white shadow-sm hover:bg-white/20 transition-colors px-4 py-2 text-sm font-semibold"
                    >
                        Cerrar
                    </button>
                </header>

                <div className="space-y-6">
                    <section className="overflow-hidden rounded-xl border border-white/10 bg-white/5 shadow-xl p-6 backdrop-blur-sm">
                        <h3 className="text-sm font-semibold text-white mb-1">Plan de Suscripción</h3>
                        <p className="text-sm text-white/50 mb-6">Actualmente estás en el <strong className="text-white">Plan Base POS</strong>.</p>
                        <div className="bg-white/5 rounded-lg p-4 flex justify-between items-center border border-white/5">
                            <div className="w-1/2">
                                <p className="text-sm font-medium text-white/80">Uso de Base de Datos</p>
                                <p className="text-xs text-white/40">0.5GB / 1GB utilizado.</p>
                            </div>
                            <div className="w-1/3 bg-white/10 rounded-full h-2">
                                <div className="h-2 rounded-full" style={{ width: '50%', backgroundColor: BRAND_PRIMARY }}></div>
                            </div>
                        </div>
                    </section>

                    <section className="overflow-hidden rounded-xl border border-white/10 bg-white/5 shadow-xl pb-0 backdrop-blur-sm">
                        <div className="p-6">
                            <h3 className="text-sm font-semibold text-white mb-1">Historial de Facturación</h3>
                            <p className="text-sm text-white/50 mb-6">Tus últimos pagos realizados.</p>
                            
                            <div className="overflow-x-auto">
                                <table className="w-full text-left text-sm">
                                    <thead className="bg-white/5 text-white/40 border-b border-white/5">
                                        <tr>
                                            <th className="px-6 py-4 font-semibold">Fecha</th>
                                            <th className="px-6 py-4 font-semibold">Monto</th>
                                            <th className="px-6 py-4 font-semibold">Factura</th>
                                            <th className="px-6 py-4 font-semibold">Estado</th>
                                            <th className="px-6 py-4 font-semibold text-right">Acción</th>
                                        </tr>
                                    </thead>
                                    <tbody className="divide-y divide-white/5 italic text-white/30">
                                        <tr>
                                            <td colSpan="5" className="px-6 py-8 text-center text-white/20">No hay facturas recientes.</td>
                                        </tr>
                                    </tbody>
                                </table>
                            </div>
                        </div>
                    </section>

                    <button 
                        onClick={handleManageBilling} 
                        disabled={isBillingLoading}
                        style={{ backgroundColor: BRAND_PRIMARY }}
                        className="w-full rounded-xl px-6 py-3 text-white font-bold shadow-lg hover:opacity-90 transition-all active:scale-[0.98] disabled:opacity-50"
                    >
                        {isBillingLoading ? "Cargando..." : "Gestionar en Stripe Billing"}
                    </button>
                </div>
            </div>
        );
    }

    function renderSettingsTab() {
        return (
            <div className="mx-auto max-w-4xl">
                <header className="mb-8 flex items-center justify-between">
                    <div>
                        <h1 className="text-2xl font-bold tracking-tight text-white sm:text-3xl">Configuración de la Cuenta</h1>
                        <p className="mt-1 text-sm text-white/60">Administra los detalles generales de tu empresa y perfiles.</p>
                    </div>
                    <button
                        onClick={() => setActiveTab('apps')}
                        className="inline-flex items-center justify-center gap-2 rounded-lg bg-white/10 border border-white/20 text-white shadow-sm hover:bg-white/20 transition-colors px-4 py-2 text-sm font-semibold"
                    >
                        Cerrar
                    </button>
                </header>

                <div className="space-y-6">
                    <section className="rounded-xl border border-white/10 bg-white/5 shadow-xl p-6 backdrop-blur-sm">
                        <div className="flex items-center gap-4 mb-6">
                            <div className="h-16 w-16 rounded-xl bg-white/5 flex items-center justify-center text-2xl font-bold text-white/30 border border-white/5">
                                {company?.name?.[0].toUpperCase() || "E"}
                            </div>
                            <div>
                                <h2 className="text-lg font-bold text-white">{company?.name || "Cargando empresa..."}</h2>
                                <p className="text-sm text-white/40">ID: {company?.id}</p>
                            </div>
                        </div>

                        <div className="grid grid-cols-1 md:grid-cols-2 gap-6 pt-4 border-t border-white/5">
                            <div>
                                <label className="block text-xs font-bold uppercase tracking-wider text-white/40 mb-1">Nombre Legal</label>
                                <p className="text-sm font-medium text-white">{company?.name || "Sin definir"}</p>
                            </div>
                            <div>
                                <label className="block text-xs font-bold uppercase tracking-wider text-white/40 mb-1">RUT Empresa</label>
                                <p className="text-sm font-medium text-white">76.000.000-0</p>
                            </div>
                            <div>
                                <label className="block text-xs font-bold uppercase tracking-wider text-white/40 mb-1">Tu Rol</label>
                                <p className="text-sm font-medium text-white font-bold">{userRole}</p>
                            </div>
                            <div>
                                <label className="block text-xs font-bold uppercase tracking-wider text-white/40 mb-1">Correo de Usuario</label>
                                <p className="text-sm font-medium text-white">{user?.email}</p>
                            </div>
                        </div>
                    </section>
                </div>
            </div>
        );
    }
}
