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

    const hasFetched = useRef(false);

    // Cargar Usuario y Empresa
    useEffect(() => {
        const fetchUserData = async () => {
            if (hasFetched.current) return;
            hasFetched.current = true;
            
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

    const handleOpenPOS = async () => {
        const { data: { session } } = await supabase.auth.getSession();
        if (session) {
            const url = `http://localhost:5173/#access_token=${session.access_token}&refresh_token=${session.refresh_token}`;
            window.location.href = url;
        } else {
            window.location.href = '/login';
        }
    };

    const handleOpenAdquisiciones = async () => {
        const { data: { session } } = await supabase.auth.getSession();
        if (session) {
            const url = `http://localhost:5174/#access_token=${session.access_token}&refresh_token=${session.refresh_token}`;
            window.location.href = url;
        } else {
            window.location.href = '/login';
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
                    <span className="text-sm font-bold tracking-widest uppercase">
                        Portal Datix
                    </span>
                </div>

                <div className="flex items-center gap-2">
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
                                
                                {/* POS */}
                                <div className="group flex flex-col items-center gap-3">
                                    <button 
                                        onClick={handleOpenPOS}
                                        className="relative flex h-24 w-24 items-center justify-center rounded-2xl bg-white/10 shadow-xl ring-1 ring-white/20 transition-all hover:scale-105 hover:bg-white/20 hover:shadow-purple-900/40 active:scale-95 group"
                                    >
                                        <div className="absolute inset-0 rounded-2xl bg-gradient-to-br from-white/10 to-transparent"></div>
                                        <Store className="h-10 w-10 text-white opacity-90 group-hover:opacity-100" />
                                    </button>
                                    <span className="text-sm font-medium text-white/90 group-hover:text-white">Caja POS</span>
                                </div>

                                {/* Adquisiciones */}
                                <div className="group flex flex-col items-center gap-3">
                                    <button 
                                        onClick={handleOpenAdquisiciones}
                                        className="relative flex h-24 w-24 items-center justify-center rounded-2xl bg-white/10 shadow-xl ring-1 ring-white/20 transition-all hover:scale-105 hover:bg-white/20 hover:shadow-purple-900/40 active:scale-95 group"
                                    >
                                        <div className="absolute inset-0 rounded-2xl bg-gradient-to-br from-white/10 to-transparent"></div>
                                        <FileText className="h-10 w-10 text-white opacity-90 group-hover:opacity-100" />
                                    </button>
                                    <span className="text-sm font-medium text-white/90 group-hover:text-white">Adquisiciones</span>
                                </div>

                                {/* Logística */}
                                <div className="group flex flex-col items-center gap-3 opacity-50 cursor-not-allowed">
                                    <div className="relative flex h-24 w-24 items-center justify-center rounded-2xl bg-white/5 shadow-inner ring-1 ring-white/10">
                                        <Package className="h-10 w-10 text-white/40" />
                                    </div>
                                    <span className="text-xs font-medium text-white/50">Logística (Prox)</span>
                                </div>

                                {/* RRHH */}
                                <div className="group flex flex-col items-center gap-3 opacity-50 cursor-not-allowed">
                                    <div className="relative flex h-24 w-24 items-center justify-center rounded-2xl bg-white/5 shadow-inner ring-1 ring-white/10">
                                        <Users className="h-10 w-10 text-white/40" />
                                    </div>
                                    <span className="text-xs font-medium text-white/50">RRHH (Prox)</span>
                                </div>

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
                                onClick={() => setTeamViewMode('list')}
                                className={`hover:text-white transition-colors ${teamViewMode === 'list' ? 'font-bold text-white' : ''}`}
                            >
                                Mi Equipo
                            </button>
                            {teamViewMode === 'form' && (
                                <>
                                    <span>/</span>
                                    <span className="font-bold text-white">Nuevo</span>
                                </>
                            )}
                        </nav>
                        <h1 className="text-2xl font-bold tracking-tight text-white sm:text-3xl">
                            {teamViewMode === 'list' ? 'Mi Equipo' : 'Nuevo Colaborador'}
                        </h1>
                    </div>
                    
                    <div className="flex items-center gap-3">
                        {teamViewMode === 'list' ? (
                            <>
                                <button
                                    onClick={() => setTeamViewMode('form')}
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
                                            required
                                            value={inviteEmail}
                                            onChange={(e) => setInviteEmail(e.target.value)}
                                            className="col-span-2 rounded-md border-white/10 bg-white/5 py-1.5 text-sm text-white focus:ring-2 focus:ring-white/20 transition-all placeholder:text-white/20"
                                            placeholder="juan@datix.cl"
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
