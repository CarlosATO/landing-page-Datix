"use client";

import React, { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { createBrowserClient } from "@supabase/ssr";
import {
    LayoutDashboard,
    CreditCard,
    Settings,
    LogOut,
    Store,
    Package,
    Users,
    ExternalLink,
    FileText,
    Check
} from "lucide-react";

const BRAND_PRIMARY = '#4C3073';

const AVAILABLE_APPS = [
    { id: 'POS', name: 'Caja POS', reversed: false, roles: [{ v: 'CASHIER', l: 'Cajero' }, { v: 'MANAGER', l: 'Jefe de Local' }] },
    { id: 'LOGISTICA', name: 'Logística', roles: [{ v: 'STOCKER', l: 'Bodeguero' }, { v: 'MANAGER', l: 'Jefe de Operaciones' }] },
    { id: 'RRHH', name: 'Recursos Humanos', roles: [{ v: 'ASSISTANT', l: 'Asistente' }, { v: 'ADMIN', l: 'Administrador' }] },
    { id: 'ADQUISICIONES', name: 'Adquisiciones', roles: [{ v: 'BUYER', l: 'Comprador' }, { v: 'MANAGER', l: 'Jefe de Compras' }] }
];

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

    // Estados para Gestión de Equipo
    const [teamMembers, setTeamMembers] = useState([]);
    const [teamViewMode, setTeamViewMode] = useState('list'); // 'list' | 'form'
    const [isInviting, setIsInviting] = useState(false);

    // Formulario de Invitación
    const [inviteEmail, setInviteEmail] = useState('');
    const [inviteName, setInviteName] = useState('');
    const [invitePassword, setInvitePassword] = useState('');
    const [inviteRole, setInviteRole] = useState('MEMBER');
    const [moduleRoles, setModuleRoles] = useState({});

    // Cargar Usuario y Empresa
    useEffect(() => {
        const fetchUserData = async () => {
            setLoading(true);
            try {
                const { data: { user: currentUser }, error: sessionError } = await supabase.auth.getUser();

                if (sessionError || !currentUser) {
                    console.error("No hay sesión activa.", sessionError);
                    router.push('/login');
                    return;
                }

                setUser(currentUser);

                // Buscar a qué empresa pertenece
                const { data: linkData, error: linkError } = await supabase
                    .from("company_users")
                    .select("company_id, role")
                    .eq("user_id", currentUser.id)
                    .single();

                if (!linkError && linkData) {
                    setUserRole(linkData.role || 'Cajero');
                    const { data: compData } = await supabase
                        .from("companies")
                        .select("*")
                        .eq("id", linkData.company_id)
                        .single();

                    if (compData) {
                        setCompany(compData);

                        // Si es Owner o Manager, cargar equipo
                        if (linkData.role === 'OWNER' || linkData.role === 'MANAGER') {
                            const { data: teamData } = await supabase
                                .from('company_users')
                                .select('*')
                                .eq('company_id', linkData.company_id);
                            if (teamData) setTeamMembers(teamData);
                        }
                    }
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

    const handleOpenPOS = async (e) => {
        e.preventDefault();
        const { data } = await supabase.auth.getSession();
        if (data?.session) {
            window.location.href = "http://localhost:5173/pos#access_token=" + data.session.access_token + "&refresh_token=" + data.session.refresh_token;
        } else {
            console.error('No se pudo establecer la sesión SSO');
            router.push('/login');
        }
    };

    const handleOpenAdquisiciones = async (e) => {
        e.preventDefault();
        const { data } = await supabase.auth.getSession();
        if (data?.session) {
            window.location.href = "http://localhost:5174/#access_token=" + data.session.access_token + "&refresh_token=" + data.session.refresh_token;
        } else {
            console.error('No se pudo establecer la sesión SSO');
            router.push('/login');
        }
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

    const handleInviteUser = async (e) => {
        e.preventDefault();
        try {
            const payload = {
                email: inviteEmail,
                password: invitePassword,
                fullName: inviteName,
                globalRole: inviteRole,
                companyId: company.id,
                moduleRoles: moduleRoles
            };

            console.log("Enviando payload:", payload);

            const res = await fetch('/api/team/invite', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload),
            });

            const data = await res.json();

            if (!res.ok) throw new Error(data.error || 'Error al crear usuario');

            // Recargar lista si el componente tiene acceso a la función de carga
            const { data: teamData } = await supabase
                .from('company_users')
                .select('*')
                .eq('company_id', company.id);
            if (teamData) setTeamMembers(teamData);

            alert("Usuario invitado con éxito!");
            setTeamViewMode('list');
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
            <div className="flex min-h-screen items-center justify-center bg-slate-50">
                <div 
                  style={{ borderTopColor: BRAND_PRIMARY }}
                  className="h-8 w-8 animate-spin rounded-full border-4 border-slate-200"
                ></div>
            </div>
        );
    }

    const isSubscriptionActive = company?.subscription_status === 'active' || company?.subscription_status === 'trialing';

    return (
        <div className="flex h-screen bg-slate-50 font-sans text-slate-900">
            {/* Sidebar (Barra Lateral Izquierda) */}
            <aside className="flex w-64 flex-col border-r border-slate-200 bg-white">
                <div className="flex h-16 items-center px-6 border-b border-slate-100">
                    <span 
                      style={{ color: BRAND_PRIMARY }}
                      className="text-2xl font-black tracking-tighter"
                    >
                        Datix
                    </span>
                </div>

                <nav className="flex-1 space-y-1 p-4">
                    <button
                        onClick={() => setActiveTab('apps')}
                        className={`flex w-full items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors ${activeTab === 'apps' ? 'bg-brand-light/20 text-brand-primary' : 'text-slate-600 hover:bg-slate-50 hover:text-slate-900'}`}
                    >
                        <LayoutDashboard className={`h-4 w-4 ${activeTab === 'apps' ? 'text-brand-primary/70' : 'text-slate-400'}`} />
                        Inicio
                    </button>
                    {userRole !== 'Cajero' && (
                        <>
                            <button
                                onClick={() => setActiveTab('team')}
                                className={`flex w-full items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors ${activeTab === 'team' ? 'bg-brand-light/20 text-brand-primary' : 'text-slate-600 hover:bg-slate-50 hover:text-slate-900'}`}
                            >
                                <Users className={`h-4 w-4 ${activeTab === 'team' ? 'text-brand-primary/70' : 'text-slate-400'}`} />
                                Mi Equipo
                            </button>
                            <button
                                onClick={() => setActiveTab('billing')}
                                className={`flex w-full items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors ${activeTab === 'billing' ? 'bg-brand-light/20 text-brand-primary' : 'text-slate-600 hover:bg-slate-50 hover:text-slate-900'}`}
                            >
                                <CreditCard className={`h-4 w-4 ${activeTab === 'billing' ? 'text-brand-primary/70' : 'text-slate-400'}`} />
                                Facturación
                            </button>
                        </>
                    )}
                    <button className="flex w-full items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50 hover:text-slate-900 transition-colors">
                        <Settings className="h-4 w-4 text-slate-400" />
                        Ajustes
                    </button>
                </nav>

                <div className="border-t border-slate-100 p-4">
                    <div className="mb-4 truncate px-3 text-xs text-slate-500 font-medium">
                        {user?.email}
                    </div>
                    <button
                        onClick={handleLogout}
                        className="flex w-full items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium text-slate-600 shadow-sm ring-1 ring-slate-200 hover:bg-red-50 hover:text-red-700 hover:ring-red-200 transition-all"
                    >
                        <LogOut className="h-4 w-4" />
                        Cerrar Sesión
                    </button>
                </div>
            </aside>

            {/* Área Principal (Main Content) */}
            <main className="flex-1 overflow-y-auto">
                <div className="mx-auto max-w-6xl p-8 lg:p-12 border-b border-transparent">
                    {/* Renderizado de Pestañas */}
                    {activeTab === 'apps' && (
                        <>
                            {/* Cabecera Apps */}
                            <header className="mb-10 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
                                <div>
                                    <h1 className="text-2xl font-bold tracking-tight text-slate-900 sm:text-3xl">
                                        Panel de Control
                                    </h1>
                                    <p className="mt-1 text-sm text-slate-500">
                                        Bienvenido, {company?.name || "Empresa"}
                                    </p>
                                </div>
                            </header>

                            {/* Grid de Aplicaciones */}
                            <div className="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3">
                                {/* Tarjeta 1: Datix POS */}
                                <div className={`group relative flex flex-col justify-between overflow-hidden rounded-xl border p-6 shadow-sm transition-all hover:shadow-md ${isSubscriptionActive ? 'border-slate-200 bg-white' : 'border-red-300 bg-red-50/50'}`}>
                                    <div>
                                        <div className="mb-4 flex items-center justify-between">
                                            <div className="flex items-center gap-3">
                                                <div 
                                                  style={isSubscriptionActive ? { backgroundColor: `${BRAND_PRIMARY}1a`, color: BRAND_PRIMARY, borderColor: `${BRAND_PRIMARY}33` } : {}}
                                                  className={`flex h-10 w-10 items-center justify-center rounded-lg ring-1 ring-inset ${isSubscriptionActive ? '' : 'bg-red-100 text-red-600 ring-red-500/30'}`}
                                                >
                                                    <Store className="h-5 w-5" />
                                                </div>
                                                <h3 className="font-semibold text-slate-900">Datix POS</h3>
                                            </div>
                                            {!isSubscriptionActive && (
                                                <span className="inline-flex items-center rounded-full bg-red-100 px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-wide text-red-800 border border-red-200">
                                                    Suscripción Inactiva
                                                </span>
                                            )}
                                        </div>
                                        <p className="text-sm text-slate-500 line-clamp-2">
                                            Punto de venta y control de inventario.
                                        </p>
                                    </div>
                                    <div className="mt-6">
                                        {isSubscriptionActive ? (
                                            <a
                                                href="#"
                                                onClick={handleOpenPOS}
                                                target="_blank"
                                                rel="noopener noreferrer"
                                                style={{ backgroundColor: BRAND_PRIMARY }}
                                                className="inline-flex w-full items-center justify-center gap-2 rounded-lg text-white shadow-sm hover:bg-brand-accent transition-colors px-4 py-2 text-sm font-semibold"
                                            >
                                                Abrir Caja <ExternalLink className="h-4 w-4 opacity-70" />
                                            </a>
                                        ) : (
                                            userRole === 'OWNER' || userRole === 'MANAGER' ? (
                                                <button
                                                    onClick={handleManageBilling}
                                                    className="inline-flex w-full items-center justify-center gap-2 rounded-lg bg-red-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-500 transition-colors"
                                                >
                                                    Actualizar Método de Pago <CreditCard className="h-4 w-4 opacity-70" />
                                                </button>
                                            ) : (
                                                <div className="flex flex-col gap-2">
                                                    <button
                                                        disabled
                                                        className="inline-flex w-full items-center justify-center gap-2 rounded-lg bg-slate-200 px-4 py-2 text-sm font-semibold text-slate-400 cursor-not-allowed"
                                                    >
                                                        Abrir Caja <ExternalLink className="h-4 w-4 opacity-50" />
                                                    </button>
                                                    <p className="text-[10px] text-red-600 font-medium text-center leading-tight">
                                                        Sistema bloqueado por falta de pago.<br/>Contacte al administrador de su local.
                                                    </p>
                                                </div>
                                            )
                                        )}
                                    </div>
                                </div>

                                {/* Tarjeta 2: Datix Logística */}
                                <div className="group relative flex flex-col justify-between overflow-hidden rounded-xl border border-slate-200 bg-white p-6 shadow-sm opacity-70 hover:opacity-100 transition-all">
                                    <div>
                                        <div className="mb-4 flex items-center gap-3">
                                            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-slate-100 text-slate-500 ring-1 ring-inset ring-slate-500/10">
                                                <Package className="h-5 w-5" />
                                            </div>
                                            <h3 className="font-semibold text-slate-900">Datix Logística</h3>
                                        </div>
                                        <p className="text-sm text-slate-500 line-clamp-2">
                                            Gestión avanzada de almacenes y rutas.
                                        </p>
                                    </div>
                                    <div className="mt-6 flex justify-center">
                                        <span className="inline-flex items-center rounded-md bg-slate-50 px-2 py-1 text-xs font-medium text-slate-600 ring-1 ring-inset ring-slate-500/10">
                                            Próximamente
                                        </span>
                                    </div>
                                </div>

                                {/* Tarjeta 3: Datix RRHH */}
                                <div className="group relative flex flex-col justify-between overflow-hidden rounded-xl border border-slate-200 bg-white p-6 shadow-sm opacity-70 hover:opacity-100 transition-all">
                                    <div>
                                        <div className="mb-4 flex items-center gap-3">
                                            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-slate-100 text-slate-500 ring-1 ring-inset ring-slate-500/10">
                                                <Users className="h-5 w-5" />
                                            </div>
                                            <h3 className="font-semibold text-slate-900">Datix RRHH</h3>
                                        </div>
                                        <p className="text-sm text-slate-500 line-clamp-2">
                                            Control de turnos, remuneraciones y capacitaciones.
                                        </p>
                                    </div>
                                    <div className="mt-6 flex justify-center">
                                        <span className="inline-flex items-center rounded-md bg-slate-50 px-2 py-1 text-xs font-medium text-slate-600 ring-1 ring-inset ring-slate-500/10">
                                            Próximamente
                                        </span>
                                    </div>
                                </div>

                                {/* Tarjeta 4: Datix Adquisiciones */}
                                <div className={`group relative flex flex-col justify-between overflow-hidden rounded-xl border p-6 shadow-sm transition-all hover:shadow-md ${isSubscriptionActive ? 'border-slate-200 bg-white' : 'border-red-300 bg-red-50/50'}`}>
                                    <div>
                                        <div className="mb-4 flex items-center justify-between">
                                            <div className="flex items-center gap-3">
                                                <div 
                                                  style={isSubscriptionActive ? { backgroundColor: `${BRAND_PRIMARY}1a`, color: BRAND_PRIMARY, borderColor: `${BRAND_PRIMARY}33` } : {}}
                                                  className={`flex h-10 w-10 items-center justify-center rounded-lg ring-1 ring-inset ${isSubscriptionActive ? '' : 'bg-red-100 text-red-600 ring-red-500/30'}`}>
                                                    <FileText className="h-5 w-5" />
                                                </div>
                                                <h3 className="font-semibold text-slate-900">Datix Adquisiciones</h3>
                                            </div>
                                            {!isSubscriptionActive && (
                                                <span className="inline-flex items-center rounded-full bg-red-100 px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-wide text-red-800 border border-red-200">
                                                    Suscripción Inactiva
                                                </span>
                                            )}
                                        </div>
                                        <p className="text-sm text-slate-500 line-clamp-2">
                                            Gestión de compras y proveedores.
                                        </p>
                                    </div>
                                    <div className="mt-6">
                                        {isSubscriptionActive ? (
                                            <a
                                                href="#"
                                                onClick={handleOpenAdquisiciones}
                                                target="_blank"
                                                rel="noopener noreferrer"
                                                style={{ backgroundColor: BRAND_PRIMARY }}
                                                className="inline-flex w-full items-center justify-center gap-2 rounded-lg text-white shadow-sm hover:bg-brand-accent transition-colors px-4 py-2 text-sm font-semibold"
                                            >
                                                Abrir Adquisiciones <ExternalLink className="h-4 w-4 opacity-70" />
                                            </a>
                                        ) : (
                                            userRole === 'OWNER' || userRole === 'MANAGER' ? (
                                                <button
                                                    onClick={handleManageBilling}
                                                    className="inline-flex w-full items-center justify-center gap-2 rounded-lg bg-red-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-500 transition-colors"
                                                >
                                                    Actualizar Método de Pago <CreditCard className="h-4 w-4 opacity-70" />
                                                </button>
                                            ) : (
                                                <div className="flex flex-col gap-2">
                                                    <button
                                                        disabled
                                                        className="inline-flex w-full items-center justify-center gap-2 rounded-lg bg-slate-200 px-4 py-2 text-sm font-semibold text-slate-400 cursor-not-allowed"
                                                    >
                                                        Abrir Adquisiciones <ExternalLink className="h-4 w-4 opacity-50" />
                                                    </button>
                                                    <p className="text-[10px] text-red-600 font-medium text-center leading-tight">
                                                        Sistema bloqueado por falta de pago.<br/>Contacte al administrador de su local.
                                                    </p>
                                                </div>
                                            )
                                        )}
                                    </div>
                                </div>
                            </div>
                        </>
                    )}


                    {activeTab === 'team' && (
                        <div className="mx-auto max-w-6xl">
                            {/* Odoo Style Control Panel */}
                            <header className="mb-8 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
                                <div>
                                    <nav className="flex items-center gap-2 text-sm text-slate-500 mb-1">
                                        <button 
                                          onClick={() => setTeamViewMode('list')}
                                          className={`hover:text-brand-primary transition-colors ${teamViewMode === 'list' ? 'font-bold' : ''}`}
                                          style={teamViewMode === 'list' ? { color: BRAND_PRIMARY } : {}}
                                        >
                                            Mi Equipo
                                        </button>
                                        {teamViewMode === 'form' && (
                                            <>
                                                <span>/</span>
                                                <span className="font-bold" style={{ color: BRAND_PRIMARY }}>Nuevo</span>
                                            </>
                                        )}
                                    </nav>
                                    <h1 className="text-2xl font-bold tracking-tight text-slate-900 sm:text-3xl">
                                        {teamViewMode === 'list' ? 'Mi Equipo' : 'Nuevo Colaborador'}
                                    </h1>
                                </div>
                                
                                <div className="flex items-center gap-3">
                                    {teamViewMode === 'list' ? (
                                        <button
                                            onClick={() => setTeamViewMode('form')}
                                            style={{ backgroundColor: BRAND_PRIMARY }}
                                            className="inline-flex items-center justify-center gap-2 rounded-lg text-white shadow-sm hover:hover:bg-brand-accent transition-colors px-4 py-2 text-sm font-semibold"
                                        >
                                            + Invitar Miembro
                                        </button>
                                    ) : (
                                        <>
                                            <button
                                              onClick={handleInviteUser}
                                              disabled={isInviting}
                                              style={{ backgroundColor: BRAND_PRIMARY }}
                                              className="inline-flex items-center justify-center gap-2 rounded-lg text-white shadow-sm hover:bg-brand-accent transition-colors px-6 py-2 text-sm font-semibold"
                                            >
                                              {isInviting ? "Invitando..." : "Guardar"}
                                            </button>
                                            <button
                                              onClick={() => setTeamViewMode('list')}
                                              className="inline-flex items-center justify-center gap-2 rounded-lg bg-white border border-slate-200 text-slate-600 shadow-sm hover:bg-slate-50 transition-colors px-6 py-2 text-sm font-semibold"
                                            >
                                              Descartar
                                            </button>
                                        </>
                                    )}
                                </div>
                            </header>

                            {teamViewMode === 'list' ? (
                                <div className="rounded-xl border border-slate-200 bg-white overflow-hidden shadow-sm">
                                    <table className="w-full text-left text-sm whitespace-nowrap">
                                        <thead className="bg-slate-50 text-slate-500 border-b border-slate-200">
                                            <tr>
                                                <th className="px-6 py-4 font-semibold">Nombre</th>
                                                <th className="px-6 py-4 font-semibold">Rol</th>
                                                <th className="px-6 py-4 font-semibold">Acceso Apps</th>
                                                <th className="px-6 py-4 font-semibold text-right">Acciones</th>
                                            </tr>
                                        </thead>
                                        <tbody className="divide-y divide-slate-100 text-slate-900">
                                            {teamMembers.map((member, idx) => (
                                                <tr key={idx} className="hover:bg-slate-50/80 transition-colors">
                                                    <td className="px-6 py-4 font-medium">{member.full_name || 'Desconocido'}</td>
                                                    <td className="px-6 py-4">
                                                        <span className={`inline-flex items-center rounded-md px-2.5 py-1 text-xs font-semibold ring-1 ring-inset ${member.role === 'OWNER' ? 'bg-purple-50 text-purple-700 ring-purple-600/20' :
                                                            member.role === 'MANAGER' ? 'bg-brand-light/20 text-brand-primary ring-brand-primary/20' :
                                                                'bg-green-50 text-green-700 ring-green-600/20'
                                                            }`}>
                                                            {member.role || 'CASHIER'}
                                                        </span>
                                                    </td>
                                                    <td className="px-6 py-4">
                                                        <div className="flex items-center gap-1.5 flex-wrap">
                                                            {member.module_roles && Object.entries(member.module_roles).map(([appId, role]) => (
                                                                <span 
                                                                  key={appId} 
                                                                  style={{ backgroundColor: `${BRAND_PRIMARY}1a`, color: BRAND_PRIMARY, borderColor: `${BRAND_PRIMARY}1a` }}
                                                                  className="inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-bold ring-1 ring-inset uppercase tracking-wider"
                                                                >
                                                                    {appId}: {role}
                                                                </span>
                                                            ))}
                                                            {(!member.module_roles || Object.keys(member.module_roles).length === 0) && <span className="text-slate-400 italic text-xs">Sin acceso</span>}
                                                        </div>
                                                    </td>
                                                    <td className="px-6 py-4 text-right">
                                                        <button 
                                                          style={{ color: BRAND_PRIMARY }}
                                                          className="hover:opacity-80 font-medium transition-colors focus:outline-none"
                                                        >
                                                            Editar
                                                        </button>
                                                    </td>
                                                </tr>
                                            ))}
                                            {teamMembers.length === 0 && (
                                                <tr>
                                                    <td colSpan="4" className="px-6 py-12 text-center">
                                                        <Users className="mx-auto h-12 w-12 text-slate-300 mb-3" />
                                                        <p className="text-slate-500">No hay empleados registrados en tu equipo.</p>
                                                    </td>
                                                </tr>
                                            )}
                                        </tbody>
                                    </table>
                                </div>
                            ) : (
                                /* Odoo Style Form View */
                                <div className="rounded-xl border border-slate-200 bg-white shadow-sm overflow-hidden animate-in fade-in slide-in-from-bottom-2 duration-300">
                                    <div className="p-8">
                                        <form className="max-w-5xl">
                                            <div className="grid grid-cols-1 md:grid-cols-2 gap-x-16 gap-y-8">
                                                {/* Sección Izquierda */}
                                                <div className="space-y-6">
                                                    <h3 className="text-xs font-bold uppercase tracking-widest text-slate-400 border-b border-slate-100 pb-2 mb-6">Datos del Colaborador</h3>
                                                    
                                                    {/* Campo Odoo Style: Label a la izquierda, Input a la derecha */}
                                                    <div className="grid grid-cols-3 items-center gap-4">
                                                        <label className="text-sm font-medium text-slate-500 text-right">Nombre</label>
                                                        <input
                                                            type="text"
                                                            required
                                                            value={inviteName}
                                                            onChange={(e) => setInviteName(e.target.value)}
                                                            className="col-span-2 rounded-md border-slate-200 bg-white py-1.5 text-sm focus:border-brand-primary focus:ring-brand-primary transition-all"
                                                            placeholder="ej. Juan Pérez"
                                                        />
                                                    </div>

                                                    <div className="grid grid-cols-3 items-center gap-4">
                                                        <label className="text-sm font-medium text-slate-500 text-right">Email</label>
                                                        <input
                                                            type="email"
                                                            required
                                                            value={inviteEmail}
                                                            onChange={(e) => setInviteEmail(e.target.value)}
                                                            className="col-span-2 rounded-md border-slate-200 bg-white py-1.5 text-sm focus:border-brand-primary focus:ring-brand-primary transition-all"
                                                            placeholder="juan@datix.cl"
                                                        />
                                                    </div>

                                                    <div className="grid grid-cols-3 items-center gap-4">
                                                        <label className="text-sm font-medium text-slate-500 text-right">Contraseña</label>
                                                        <input
                                                            type="password"
                                                            required
                                                            value={invitePassword}
                                                            onChange={(e) => setInvitePassword(e.target.value)}
                                                            className="col-span-2 rounded-md border-slate-200 bg-white py-1.5 text-sm focus:border-brand-primary focus:ring-brand-primary transition-all"
                                                            placeholder="••••••••"
                                                        />
                                                    </div>

                                                    <div className="grid grid-cols-3 items-center gap-4">
                                                        <label className="text-sm font-medium text-slate-500 text-right">Rol Portal</label>
                                                        <select
                                                            value={inviteRole}
                                                            onChange={(e) => setInviteRole(e.target.value)}
                                                            className="col-span-2 rounded-md border-slate-200 bg-white py-1.5 text-sm focus:border-brand-primary focus:ring-brand-primary transition-all"
                                                        >
                                                            <option value="MEMBER">Miembro / Empleado Base</option>
                                                            <option value="OWNER">Dueño / Admin Total</option>
                                                        </select>
                                                    </div>
                                                </div>

                                                {/* Sección Derecha: Accesos */}
                                                <div className="space-y-4">
                                                    <h3 className="text-xs font-bold uppercase tracking-widest text-slate-400 border-b border-slate-100 pb-2 mb-6">Permisos por Módulo</h3>
                                                    <div className="grid grid-cols-1 gap-3">
                                                        {AVAILABLE_APPS.map((app) => (
                                                            <div
                                                                key={app.id}
                                                                className={`p-3 rounded-lg border transition-all ${moduleRoles[app.id]
                                                                    ? 'bg-brand-light/5 border-brand-primary/30 shadow-sm'
                                                                    : 'border-slate-100 bg-slate-50/30'
                                                                    }`}
                                                            >
                                                                <div
                                                                    className="flex items-center justify-between cursor-pointer"
                                                                    onClick={() => handleToggleModule(app.id, app.roles[0].v)}
                                                                >
                                                                    <div className="flex items-center gap-3">
                                                                        <div 
                                                                          style={moduleRoles[app.id] ? { backgroundColor: BRAND_PRIMARY, borderColor: BRAND_PRIMARY } : {}}
                                                                          className={`flex h-4 w-4 shrink-0 items-center justify-center rounded border transition-colors ${moduleRoles[app.id] ? 'text-white' : 'border-slate-300 bg-white'}`}
                                                                        >
                                                                            {moduleRoles[app.id] && <Check className="h-2.5 w-2.5 stroke-[3px]" />}
                                                                        </div>
                                                                        <span className={`text-sm font-bold ${moduleRoles[app.id] ? 'text-brand-primary' : 'text-slate-600'}`}>{app.name}</span>
                                                                    </div>
                                                                    
                                                                    {moduleRoles[app.id] && (
                                                                        <select
                                                                            value={moduleRoles[app.id]}
                                                                            onClick={(e) => e.stopPropagation()}
                                                                            onChange={(e) => handleChangeModuleRole(app.id, e.target.value)}
                                                                            className="rounded-md border-slate-200 bg-white px-2 py-0.5 text-xs font-medium text-slate-800 focus:border-brand-primary focus:ring-brand-primary transition-all ml-4"
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
                                </div>
                            )}
                        </div>
                    )}

                    {activeTab === 'billing' && (
                        <div className="mx-auto max-w-4xl">
                            <header className="mb-8">
                                <h1 className="text-2xl font-bold tracking-tight text-slate-900 sm:text-3xl">
                                    Facturación
                                </h1>
                                <p className="mt-1 text-sm text-slate-500">
                                    Gestiona tu plan de suscripción, métodos de pago y facturas de manera segura.
                                </p>
                            </header>

                            <div className="space-y-6">
                                {/* Plan de Suscripción */}
                                <section className="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm pb-0">
                                    <div className="p-6">
                                        <h3 className="text-sm font-semibold text-slate-900 mb-1">Plan de Suscripción</h3>
                                        <p className="text-sm text-slate-500 mb-6">Actualmente estás en el <strong>Plan Base POS</strong>.</p>

                                        <div className="flex justify-between items-center rounded-lg border border-slate-100 bg-slate-50 p-4">
                                            <div className="w-1/2">
                                                <p className="text-sm font-medium text-slate-900">Uso de Base de Datos</p>
                                                <p className="text-xs text-slate-500">Dentro de los límites del plan (0.5GB / 1GB).</p>
                                            </div>
                                            <div className="w-1/3 bg-slate-200 rounded-full h-2">
                                                <div 
                                                  style={{ backgroundColor: BRAND_PRIMARY }}
                                                  className="h-2 rounded-full" 
                                                  style={{ width: '50%', backgroundColor: BRAND_PRIMARY }}
                                                ></div>
                                            </div>
                                        </div>
                                    </div>
                                    <div className="bg-slate-50 px-6 py-4 flex justify-between items-center border-t border-slate-200">
                                        <p className="text-xs text-slate-500">El pago se procesa de forma segura a través de Stripe.</p>
                                        <button onClick={handleManageBilling} disabled={isBillingLoading} className="rounded-lg bg-white px-3 py-1.5 text-sm font-medium text-slate-700 shadow-sm ring-1 ring-inset ring-slate-300 hover:bg-slate-100 disabled:opacity-50 transition-colors">
                                            Cambiar plan de suscripción
                                        </button>
                                    </div>
                                </section>

                                {/* Control de Costos */}
                                <section className="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm p-6">
                                    <h3 className="text-sm font-semibold text-slate-900 mb-1">Control de Costos</h3>
                                    <p className="text-sm text-slate-500 mb-4">Evita cargos sorpresa limitando los usos adicionales (por encima del plan base).</p>
                                    <div className="flex items-center gap-3">
                                        {/* Toggle switch visual */}
                                        <div 
                                          style={{ backgroundColor: BRAND_PRIMARY }}
                                          className="relative inline-block h-5 w-9 shrink-0 cursor-not-allowed rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out"
                                        >
                                            <span className="translate-x-4 pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out"></span>
                                        </div>
                                        <span className="text-sm font-medium text-slate-900">Spend cap is enabled</span>
                                    </div>
                                </section>

                                {/* Próxima Factura */}
                                <section className="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm p-6">
                                    <h3 className="text-sm font-semibold text-slate-900 mb-1">Próxima Factura</h3>
                                    <p className="text-sm text-slate-500 mb-4">Estimación del cobro recurrente para tu próximo ciclo.</p>
                                    <div className="flex items-baseline gap-2 mb-2">
                                        <span className="text-3xl font-bold text-slate-900">$25.00</span>
                                        <span className="text-sm font-medium text-slate-500">USD</span>
                                    </div>
                                    <p className="text-xs text-slate-500">La facturación se procesará el 15 de Abril, 2026.</p>
                                </section>

                                {/* Facturas Anteriores */}
                                <section className="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
                                    <div className="p-6 border-b border-slate-200 flex justify-between items-center">
                                        <div>
                                            <h3 className="text-sm font-semibold text-slate-900 mb-1">Facturas Anteriores</h3>
                                            <p className="text-sm text-slate-500">Revisa o descarga tus recibos mensuales.</p>
                                        </div>
                                    </div>
                                    <div className="overflow-x-auto">
                                        <table className="w-full text-left text-sm whitespace-nowrap">
                                            <thead className="bg-slate-50 text-slate-500">
                                                <tr>
                                                    <th className="px-6 py-3 font-medium">Fecha</th>
                                                    <th className="px-6 py-3 font-medium">Monto</th>
                                                    <th className="px-6 py-3 font-medium">Factura</th>
                                                    <th className="px-6 py-3 font-medium">Estado</th>
                                                    <th className="px-6 py-3 font-medium text-right">Acciones</th>
                                                </tr>
                                            </thead>
                                            <tbody className="divide-y divide-slate-200 bg-white text-slate-900">
                                                {[
                                                    { date: '15 Mar, 2026', amount: '$25.00', invoice: '#INV-003' },
                                                    { date: '15 Feb, 2026', amount: '$25.00', invoice: '#INV-002' },
                                                    { date: '15 Ene, 2026', amount: '$25.00', invoice: '#INV-001' }
                                                ].map((item, idx) => (
                                                    <tr key={idx} className="hover:bg-slate-50 transition-colors">
                                                        <td className="px-6 py-4">{item.date}</td>
                                                        <td className="px-6 py-4">{item.amount}</td>
                                                        <td className="px-6 py-4">{item.invoice}</td>
                                                        <td className="px-6 py-4">
                                                            <span className="inline-flex items-center rounded-full bg-green-50 px-2.5 py-0.5 text-xs font-medium text-green-700 ring-1 ring-inset ring-green-600/20">
                                                                Pagado
                                                            </span>
                                                        </td>
                                                        <td className="px-6 py-4 text-right">
                                                            <button 
                                                              onClick={handleManageBilling} 
                                                              style={{ color: BRAND_PRIMARY }}
                                                              className="hover:opacity-80 font-medium transition-colors"
                                                            >
                                                                Descargar
                                                            </button>
                                                        </td>
                                                    </tr>
                                                ))}
                                            </tbody>
                                        </table>
                                    </div>
                                </section>

                                {/* Métodos de Pago */}
                                <section className="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm p-6">
                                    <div className="flex justify-between items-center mb-4">
                                        <div>
                                            <h3 className="text-sm font-semibold text-slate-900 mb-1">Método de Pago</h3>
                                            <p className="text-sm text-slate-500">Tarjetas de crédito o débito vinculadas.</p>
                                        </div>
                                        <button onClick={handleManageBilling} disabled={isBillingLoading} className="rounded-lg bg-white px-3 py-1.5 text-sm font-medium text-slate-700 shadow-sm ring-1 ring-inset ring-slate-300 hover:bg-slate-100 disabled:opacity-50 transition-colors">
                                            Añadir nueva tarjeta
                                        </button>
                                    </div>
                                    <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 rounded-lg border border-slate-200 p-4 bg-slate-50/50">
                                        <div className="flex items-center gap-4">
                                            <div className="flex h-10 w-14 shrink-0 items-center justify-center rounded bg-white shadow-sm border border-slate-200">
                                                <span className="text-[10px] font-black italic text-blue-900 leading-none">VISA</span>
                                            </div>
                                            <div>
                                                <p className="text-sm font-semibold text-slate-900">Visa terminada en 4242</p>
                                                <p className="text-xs text-slate-500">Expira en 12/28</p>
                                            </div>
                                        </div>
                                        <span 
                                           style={{ backgroundColor: BRAND_PRIMARY + '1a', color: BRAND_PRIMARY, borderColor: BRAND_PRIMARY + '33' }}
                                           className="inline-flex shrink-0 items-center rounded-full px-2.5 py-0.5 text-xs font-medium ring-1 ring-inset"
                                         >
                                             Principal activa
                                         </span>
                                    </div>
                                </section>

                                {/* Datos de Facturación */}
                                <section className="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm pb-0">
                                    <div className="p-6">
                                        <h3 className="text-sm font-semibold text-slate-900 mb-1">Datos de Facturación</h3>
                                        <p className="text-sm text-slate-500 mb-6">Información fiscal para la emisión de tus recibos.</p>

                                        <div className="grid grid-cols-1 gap-6 sm:grid-cols-2 max-w-2xl">
                                            <div className="col-span-1 sm:col-span-2">
                                                <label className="block text-sm font-medium text-slate-700 mb-1">Correo Electrónico (Recibos)</label>
                                                <input type="email" disabled value={user?.email || "cargando..."} className="block w-full rounded-md border-slate-300 bg-slate-50 px-3 py-2 text-sm text-slate-500 shadow-sm ring-1 ring-inset ring-slate-200 cursor-not-allowed" />
                                            </div>
                                            <div className="col-span-1">
                                                <label className="block text-sm font-medium text-slate-700 mb-1">Dirección de facturación</label>
                                                <input type="text" disabled value="Avenida Providencia 1234, Santiago" className="block w-full rounded-md border-slate-300 bg-slate-50 px-3 py-2 text-sm text-slate-500 shadow-sm ring-1 ring-inset ring-slate-200 cursor-not-allowed" />
                                            </div>
                                            <div className="col-span-1">
                                                <label className="block text-sm font-medium text-slate-700 mb-1">RUT / Identificación Fiscal</label>
                                                <input type="text" disabled value="76.123.456-K" className="block w-full rounded-md border-slate-300 bg-slate-50 px-3 py-2 text-sm text-slate-500 shadow-sm ring-1 ring-inset ring-slate-200 cursor-not-allowed" />
                                            </div>
                                        </div>
                                    </div>
                                    <div className="bg-slate-50 px-6 py-4 flex justify-end border-t border-slate-200">
                                        <button 
                                          onClick={handleManageBilling} 
                                          disabled={isBillingLoading} 
                                          style={{ backgroundColor: BRAND_PRIMARY }}
                                          className="rounded-lg px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-accent disabled:opacity-50 transition-colors"
                                        >
                                            Actualizar datos
                                        </button>
                                    </div>
                                </section>
                            </div>
                        </div>
                    )}
                </div>
            </main >
        </div >
    );
}
