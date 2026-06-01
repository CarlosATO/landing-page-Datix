"use client";

import Image from 'next/image';
import {
  LayoutDashboard,
  CreditCard,
  Settings,
  LogOut,
  Store,
  Package,
  Pill,
  Users,
  FileText,
  Check,
  Briefcase,
  Lock,
  ArrowRight,
  Building2,
  ShoppingCart,
  ShieldCheck,
  Zap,
} from 'lucide-react';
import { AVAILABLE_APPS, BRAND_PRIMARY, getPortalModuleState } from '../utils/portalConstants';

export function PortalDashboardView({
  user,
  company,
  loading,
  isBillingLoading,
  activeTab,
  setActiveTab,
  userRole,
  teamMembers,
  companyModules,
  isSavingOnboarding,
  onboardingData,
  setOnboardingData,
  teamViewMode,
  setTeamViewMode,
  isInviting,
  editingUserId,
  setEditingUserId,
  inviteEmail,
  setInviteEmail,
  inviteName,
  setInviteName,
  invitePassword,
  setInvitePassword,
  inviteRole,
  setInviteRole,
  moduleRoles,
  setModuleRoles,
  needsPasswordChange,
  newPassword,
  setNewPassword,
  confirmPassword,
  setConfirmPassword,
  isChangingPassword,
  handleLogout,
  handleChangePassword,
  handleSaveOnboarding,
  handleOpenApp,
  handleToggleModule,
  handleChangeModuleRole,
  handleEditUser,
  handleInviteUser,
  handleManageBilling,
}) {
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
            <p className="text-slate-500 text-sm">Tu empleador te ha invitado al sistema con una contraseña temporal. Por seguridad de tus accesos, debes crear tu propia contraseña permanentemente.</p>
          </div>

          <form
            onSubmit={async (e) => {
              e.preventDefault();
              try {
                await handleChangePassword(e);
              } catch (error) {
                alert(error.message);
              }
            }}
            className="space-y-4"
          >
            <div className="space-y-1 text-left">
              <label className="text-[11px] font-bold uppercase tracking-widest text-slate-400 ml-1">Nueva Contraseña</label>
              <input type="password" required value={newPassword} onChange={(e) => setNewPassword(e.target.value)} className="w-full rounded-2xl border border-slate-200 bg-slate-50 py-4 px-5 text-slate-900 focus:bg-white focus:outline-none focus:ring-2 focus:ring-purple-500/50 transition-all font-medium placeholder:text-slate-300" placeholder="Mínimo 6 caracteres" />
            </div>
            <div className="space-y-1 text-left">
              <label className="text-[11px] font-bold uppercase tracking-widest text-slate-400 ml-1">Confirmar Nueva Contraseña</label>
              <input type="password" required value={confirmPassword} onChange={(e) => setConfirmPassword(e.target.value)} className="w-full rounded-2xl border border-slate-200 bg-slate-50 py-4 px-5 text-slate-900 focus:bg-white focus:outline-none focus:ring-2 focus:ring-purple-500/50 transition-all font-medium placeholder:text-slate-300" placeholder="Repite tu contraseña..." />
            </div>

            <div className="pt-4">
              <button type="submit" disabled={isChangingPassword} style={{ backgroundColor: BRAND_PRIMARY }} className="w-full rounded-2xl px-6 py-4 text-white font-bold shadow-xl shadow-purple-900/40 hover:opacity-90 active:scale-[0.98] transition-all disabled:opacity-50 disabled:scale-100">
                {isChangingPassword ? 'Actualizando Seguridad...' : 'Guardar y Entrar al Portal'}
              </button>
            </div>
          </form>
        </div>
      </div>
    );
  }

  const isPrivilegedUser = userRole === 'OWNER' || userRole === 'MANAGER';

  // contractedApps = ONLY what company_modules reports as active|trial
  // We do NOT compute upsell — per business rule, portal shows only contracted modules.
  const portalApps = AVAILABLE_APPS.map((app) => ({
    ...app,
    state: getPortalModuleState(companyModules || [], app.id),
  }));
  const contractedApps = portalApps.filter((app) => app.state.contracted);
  const hasContractedApps = contractedApps.length > 0;

  if (typeof window !== 'undefined' && window.location.hostname === 'localhost') {
    console.debug('[portal render states]', {
      company_id: company?.id,
      company_name: company?.name,
      module_states: portalApps.map((app) => ({
        app_id: app.id,
        module_key: app.state.moduleKey,
        status: app.state.status,
        contracted: app.state.contracted,
        enabled: app.state.available,
        locked: !app.state.available,
        comingSoon: app.state.comingSoon,
        openUrl: app.state.openUrl,
        reason: app.state.blockedReason,
      })),
    });
  }

  return (
    <div className="flex flex-col h-screen font-sans" style={{ backgroundColor: '#45316D' }}>
      <nav className="flex h-12 w-full items-center justify-between px-4 text-white shadow-lg" style={{ backgroundColor: '#5B4385' }}>
        <div className="flex items-center gap-4 cursor-pointer hover:opacity-80 transition-opacity" onClick={() => setActiveTab('apps')}>
          <button className="p-1 hover:bg-white/10 rounded-md transition-colors">
            <LayoutDashboard className="h-6 w-6" />
          </button>
          <Image src="/imagen/logo_datix.png" alt="Datix Logo" width={110} height={36} className="h-7 w-auto opacity-90 transition-all hover:opacity-100" priority />
        </div>

        <div className="flex items-center gap-2">
          {(userRole === 'OWNER' || userRole === 'MANAGER') && (
            <>
              <button onClick={() => setActiveTab('team')} title="Gestión de Equipo" className={`p-2 hover:bg-white/10 rounded-md transition-colors ${activeTab === 'team' ? 'bg-white/20' : ''}`}><Users className="h-5 w-5" /></button>
              <button onClick={() => setActiveTab('billing')} title="Facturación" className={`p-2 hover:bg-white/10 rounded-md transition-colors ${activeTab === 'billing' ? 'bg-white/20' : ''}`}><CreditCard className="h-5 w-5" /></button>
              <button onClick={() => setActiveTab('settings')} title="Configuración" className={`p-2 hover:bg-white/10 rounded-md transition-colors ${activeTab === 'settings' ? 'bg-white/20' : ''}`}><Settings className="h-5 w-5" /></button>
            </>
          )}
          <div className="h-6 w-px bg-white/20 mx-2"></div>
          <div className="flex items-center gap-3">
            <span className="hidden sm:inline-block text-xs font-semibold tracking-wide uppercase opacity-90">{user?.email?.split('@')[0] || 'USUARIO'}</span>
            <div className="h-8 w-8 rounded-md bg-white/20 flex items-center justify-center font-bold text-xs ring-1 ring-white/30">{user?.email?.[0]?.toUpperCase() || 'U'}</div>
            <button onClick={handleLogout} className="p-2 hover:bg-red-500/20 rounded-md transition-colors text-red-200" title="Cerrar Sesión"><LogOut className="h-4 w-4" /></button>
          </div>
        </div>
      </nav>

      <main className="flex-1 overflow-y-auto">
        {activeTab === 'apps' ? (
          <div className="p-6 sm:p-10">
            <div className="mx-auto max-w-6xl">

              {/* Onboarding: Empresa incompleta */}
              {(!company?.rut || !company?.address || !company?.activity) ? (
                <div className="animate-in fade-in zoom-in duration-500">
                  <div className="mx-auto max-w-2xl overflow-hidden rounded-3xl border border-white/10 bg-white/5 shadow-2xl backdrop-blur-xl">
                    <div className="bg-gradient-to-r from-purple-600/20 to-blue-600/20 p-8 border-b border-white/5">
                      <div className="flex items-center gap-4 mb-2">
                        <div className="p-3 bg-white/10 rounded-2xl"><Briefcase className="h-8 w-8 text-white" /></div>
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
                          <input required placeholder="76.xxx.xxx-x" value={onboardingData.rut} onChange={(e) => setOnboardingData({ ...onboardingData, rut: e.target.value.toUpperCase() })} className="w-full rounded-xl border-white/10 bg-white/5 px-4 py-3 text-white placeholder:text-white/20 focus:ring-2 focus:ring-purple-500/50 outline-none transition-all" />
                        </div>
                        <div className="space-y-2">
                          <label className="text-xs font-bold uppercase tracking-widest text-white/40">Giro / Actividad *</label>
                          <input required placeholder="Ej: Construcción..." value={onboardingData.activity} onChange={(e) => setOnboardingData({ ...onboardingData, activity: e.target.value.toUpperCase() })} className="w-full rounded-xl border-white/10 bg-white/5 px-4 py-3 text-white placeholder:text-white/20 focus:ring-2 focus:ring-purple-500/50 outline-none transition-all" />
                        </div>
                        <div className="space-y-2 md:col-span-2">
                          <label className="text-xs font-bold uppercase tracking-widest text-white/40">Dirección Comercial *</label>
                          <input required placeholder="Calle, Número, Ciudad" value={onboardingData.address} onChange={(e) => setOnboardingData({ ...onboardingData, address: e.target.value.toUpperCase() })} className="w-full rounded-xl border-white/10 bg-white/5 px-4 py-3 text-white placeholder:text-white/20 focus:ring-2 focus:ring-purple-500/50 outline-none transition-all" />
                        </div>
                        <div className="space-y-2">
                          <label className="text-xs font-bold uppercase tracking-widest text-white/40">Teléfono</label>
                          <input placeholder="+56 9 ..." value={onboardingData.phone} onChange={(e) => setOnboardingData({ ...onboardingData, phone: e.target.value.toUpperCase() })} className="w-full rounded-xl border-white/10 bg-white/5 px-4 py-3 text-white placeholder:text-white/20 focus:ring-2 focus:ring-purple-500/50 outline-none transition-all" />
                        </div>
                        <div className="space-y-2">
                          <label className="text-xs font-bold uppercase tracking-widest text-white/40">Ciudad</label>
                          <input placeholder="Santiago, Concepción..." value={onboardingData.city} onChange={(e) => setOnboardingData({ ...onboardingData, city: e.target.value.toUpperCase() })} className="w-full rounded-xl border-white/10 bg-white/5 px-4 py-3 text-white placeholder:text-white/20 focus:ring-2 focus:ring-purple-500/50 outline-none transition-all" />
                        </div>
                      </div>
                      <button type="submit" disabled={isSavingOnboarding} style={{ backgroundColor: BRAND_PRIMARY }} className="w-full mt-4 rounded-2xl px-6 py-4 text-white font-bold shadow-lg hover:opacity-90 active:scale-[0.98] transition-all disabled:opacity-50">
                        {isSavingOnboarding ? 'Guardando...' : 'Finalizar Configuración e Ingresar'}
                      </button>
                    </form>
                  </div>
                </div>
              ) : (
                <>
                  {/* Header de bienvenida */}
                  <div className="mb-8">
                    <p className="text-white/40 text-xs font-bold uppercase tracking-widest mb-1">Portal Operacional</p>
                    <h1 className="text-2xl font-extrabold text-white">{company?.name || 'Mi Empresa'}</h1>
                    <p className="text-white/50 text-sm mt-1">Selecciona un módulo para comenzar tu sesión de trabajo.</p>
                  </div>

                  {/* Grid de Módulos en Cards */}
                  <section className="mb-8">
                    <div className="mb-4 flex items-center justify-between gap-3">
                      <div>
                        <h2 className="text-lg font-extrabold text-white">Mis módulos</h2>
                        <p className="text-xs font-medium uppercase tracking-widest text-white/35">Solo contratos activos o trial</p>
                      </div>
                      <div className="text-xs font-semibold uppercase tracking-widest text-white/35">{contractedApps.length} encontrados</div>
                    </div>

                    {!hasContractedApps ? (
                      <div className="py-16 text-center animate-in fade-in duration-700 rounded-2xl border border-white/10 bg-white/5">
                        <div className="mx-auto mb-6 flex h-20 w-20 items-center justify-center rounded-full bg-white/5 ring-1 ring-white/10">
                          <Lock className="h-10 w-10 text-white/20" />
                        </div>
                        <h3 className="text-xl font-bold text-white mb-2">Sin módulos contratados</h3>
                        <p className="text-white/40 max-w-sm mx-auto text-sm">
                          {isPrivilegedUser
                            ? 'Activa al menos un módulo en company_modules para comenzar.'
                            : 'Tu empresa aún no tiene módulos habilitados. Contacta al administrador.'}
                        </p>
                      </div>
                    ) : (
                      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5">
                        {contractedApps.map((app) => {
                        const iconMap = { POS: Store, ADQUISICIONES: ShoppingCart, FARMACIAS: Pill, LOGISTICA: Package, RRHH: Users, CONSTRUCCION: Building2 };
                        const colorMap = {
                          POS:          { accent: 'from-violet-500/30 to-purple-600/10', iconBg: 'bg-violet-500/20', iconColor: 'text-violet-300', badge: 'bg-violet-500/20 text-violet-300' },
                          ADQUISICIONES:{ accent: 'from-teal-500/20 to-teal-600/5',    iconBg: 'bg-teal-500/20',    iconColor: 'text-teal-300',    badge: 'bg-teal-500/20 text-teal-300' },
                          FARMACIAS:    { accent: 'from-pink-500/20 to-pink-600/5',    iconBg: 'bg-pink-500/20',    iconColor: 'text-pink-300',    badge: 'bg-pink-500/20 text-pink-300' },
                          LOGISTICA:    { accent: 'from-indigo-500/20 to-indigo-600/5',iconBg: 'bg-indigo-500/20', iconColor: 'text-indigo-300', badge: 'bg-indigo-500/20 text-indigo-300' },
                          RRHH:         { accent: 'from-amber-500/20 to-amber-600/5',  iconBg: 'bg-amber-500/20',  iconColor: 'text-amber-300',  badge: 'bg-amber-500/20 text-amber-300' },
                          CONSTRUCCION: { accent: 'from-orange-500/20 to-orange-600/5',iconBg: 'bg-orange-500/20',iconColor: 'text-orange-300', badge: 'bg-orange-500/20 text-orange-300' },
                        };
                        const descMap = {
                          POS:          'Gestión de ventas, caja y tickets en punto de venta.',
                          ADQUISICIONES:'Órdenes de compra, proveedores y control presupuestario.',
                          FARMACIAS:    'Trazabilidad farmacéutica, stock y dispensación.',
                          LOGISTICA:    'Control de pañol, bodegas, herramientas y kardex.',
                          RRHH:         'Gestión de personal, contratos y asistencia.',
                          CONSTRUCCION: 'Avances de obra, cubicaciones y control de subcontratos.',
                        };
                        const featureMap = {
                          POS:          ['Ventas en tiempo real', 'Cierre de caja', 'Auditoría'],
                          ADQUISICIONES:['Control de OC', 'Proveedores', 'Trazabilidad'],
                          FARMACIAS:    ['Stock por lote', 'Recetas', 'Auditoría FEFO'],
                          LOGISTICA:    ['Kardex', 'Multi-bodega', 'Despacho nominal'],
                          RRHH:         ['Nómina', 'Contratos', 'Asistencia'],
                          CONSTRUCCION: ['Avance físico', 'Candado financiero', 'Cubicaciones'],
                        };
                        const Icon = iconMap[app.id] || Package;
                        const colors = colorMap[app.id] || colorMap.LOGISTICA;
                        const { available, contractedButPreparing, blockedReason } = app.state;
                        const statusLabel = available
                          ? 'Activo'
                          : contractedButPreparing
                            ? 'En preparación'
                            : 'Bloqueado';
                        const desc = descMap[app.id] || 'Módulo operacional Datix.';
                        const features = featureMap[app.id] || [];

                        return (
                          <div
                            key={app.id}
                            className={`group relative overflow-hidden rounded-2xl border transition-all duration-300 ${
                              available
                                ? 'border-white/15 bg-white/5 hover:bg-white/10 hover:border-white/25 hover:shadow-2xl hover:shadow-black/30 cursor-pointer'
                                : 'border-white/8 bg-white/3 opacity-65 cursor-not-allowed'
                            }`}
                            onClick={() => available && handleOpenApp(app.id)}
                          >
                            {/* Accent gradient top */}
                            <div className={`absolute inset-x-0 top-0 h-32 bg-gradient-to-b ${colors.accent} pointer-events-none`} />

                            <div className="relative p-6">
                              {/* Header de la card */}
                              <div className="flex items-start justify-between mb-5">
                                <div className={`h-14 w-14 rounded-2xl ${colors.iconBg} flex items-center justify-center ring-1 ring-white/10`}>
                                  <Icon className={`h-7 w-7 ${colors.iconColor}`} />
                                </div>
                                <span className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[10px] font-bold uppercase tracking-wider ring-1 ring-white/10 ${
                                  available ? colors.badge : 'bg-white/5 text-white/30'
                                }`}>
                                  {available ? (
                                    <><span className="h-1.5 w-1.5 rounded-full bg-current animate-pulse" />Activo</>
                                  ) : (
                                    statusLabel
                                  )}
                                </span>
                              </div>

                              {/* Nombre y descripción */}
                              <h3 className={`text-lg font-extrabold mb-1.5 ${available ? 'text-white' : 'text-white/40'}`}>
                                {app.name}
                              </h3>
                              <p className="text-white/50 text-xs font-medium leading-relaxed mb-2">{desc}</p>
                              <p className="text-white/35 text-[11px] font-semibold uppercase tracking-widest mb-5">
                                {available ? 'Contratado y habilitado' : blockedReason}
                              </p>

                              {/* Features */}
                              <div className="flex flex-wrap gap-2 mb-6">
                                {features.map((f, fi) => (
                                  <span key={fi} className="flex items-center gap-1 text-[10px] font-semibold text-white/40 bg-white/5 border border-white/8 rounded-full px-2.5 py-1">
                                    <Check className="h-2.5 w-2.5 text-white/30" />{f}
                                  </span>
                                ))}
                              </div>

                              {/* CTA */}
                              {available ? (
                                <button
                                  onClick={(e) => { e.stopPropagation(); handleOpenApp(app.id); }}
                                  className={`flex w-full items-center justify-center gap-2 rounded-xl py-3 text-sm font-bold transition-all ${colors.iconBg} ${colors.iconColor} ring-1 ring-white/10 group-hover:ring-white/20 group-hover:brightness-110`}
                                >
                                  Abrir Módulo <ArrowRight className="h-4 w-4 group-hover:translate-x-0.5 transition-transform" />
                                </button>
                              ) : (
                                <div className="flex w-full items-center justify-center gap-2 rounded-xl py-3 text-sm font-bold bg-white/5 text-white/20 ring-1 ring-white/5">
                                  <Lock className="h-4 w-4" /> {statusLabel}
                                </div>
                              )}
                            </div>
                          </div>
                        );
                        })}
                      </div>
                    )}
                  </section>

                  {/* Footer de trazabilidad */}
                  <div className="mt-10 flex items-center justify-center gap-2 text-white/20 text-xs font-medium">
                    <ShieldCheck className="h-4 w-4" />
                    Trazabilidad total activa · Auditoría perpetua · Aislamiento multi-empresa
                  </div>
                </>
              )}
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

  function renderTeamTab() {
    return (
      <div className="mx-auto max-w-6xl">
        <header className="mb-8 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <nav className="flex items-center gap-2 text-sm text-white/50 mb-1">
              <button onClick={() => { setEditingUserId(null); setTeamViewMode('list'); }} className={`hover:text-white transition-colors ${teamViewMode === 'list' ? 'font-bold text-white' : ''}`}>Mi Equipo</button>
              {teamViewMode === 'form' && (<><span>/</span><span className="font-bold text-white">{editingUserId ? 'Editar' : 'Nuevo'}</span></>)}
            </nav>
            <h1 className="text-2xl font-bold tracking-tight text-white sm:text-3xl">{teamViewMode === 'list' ? 'Mi Equipo' : (editingUserId ? 'Editar Colaborador' : 'Nuevo Colaborador')}</h1>
          </div>

          <div className="flex items-center gap-3">
            {teamViewMode === 'list' ? (
              <>
                <button onClick={() => { setEditingUserId(null); setInviteEmail(''); setInviteName(''); setInvitePassword(''); setInviteRole('MEMBER'); setModuleRoles({}); setTeamViewMode('form'); }} style={{ backgroundColor: BRAND_PRIMARY }} className="inline-flex items-center justify-center gap-2 rounded-lg text-white shadow-sm hover:bg-brand-accent transition-colors px-4 py-2 text-sm font-semibold">+ Invitar Miembro</button>
                <button onClick={() => setActiveTab('apps')} className="inline-flex items-center justify-center gap-2 rounded-lg bg-white/10 border border-white/20 text-white shadow-sm hover:bg-white/20 transition-colors px-4 py-2 text-sm font-semibold">Cerrar</button>
              </>
            ) : (
              <>
                <button onClick={handleInviteUser} disabled={isInviting} style={{ backgroundColor: BRAND_PRIMARY }} className="inline-flex items-center justify-center gap-2 rounded-lg text-white shadow-sm hover:bg-white/20 transition-colors px-6 py-2 text-sm font-semibold">{isInviting ? 'Invitando...' : 'Guardar'}</button>
                <button onClick={() => setTeamViewMode('list')} className="inline-flex items-center justify-center gap-2 rounded-lg bg-white/5 border border-white/10 text-white/70 shadow-sm hover:bg-white/10 hover:text-white transition-colors px-6 py-2 text-sm font-semibold">Descartar</button>
              </>
            )}
          </div>
        </header>

        {teamViewMode === 'list' ? (
          <div className="rounded-xl border border-white/10 bg-white/5 overflow-hidden shadow-xl backdrop-blur-sm">
            <table className="w-full text-left text-sm whitespace-nowrap">
              <thead className="bg-white/5 text-white/50 border-b border-white/10"><tr><th className="px-6 py-4 font-semibold text-white/70">Nombre</th><th className="px-6 py-4 font-semibold text-white/70">Rol</th><th className="px-6 py-4 font-semibold text-white/70">Acceso Apps</th><th className="px-6 py-4 font-semibold text-right text-white/70">Acciones</th></tr></thead>
              <tbody className="divide-y divide-white/5 text-white">
                {teamMembers.map((member) => (
                  <tr key={member.user_id || member.id} className="hover:bg-white/5 transition-colors">
                    <td className="px-6 py-4 font-medium">{member.full_name || 'Desconocido'}</td>
                    <td className="px-6 py-4"><span className={`inline-flex items-center rounded-md px-2.5 py-1 text-xs font-semibold ring-1 ring-inset ${member.role === 'OWNER' ? 'bg-white/20 text-white ring-white/30' : member.role === 'MANAGER' ? 'bg-white/10 text-white/80 ring-white/20' : 'bg-green-500/20 text-green-300 ring-green-500/30'}`}>{member.role || 'CASHIER'}</span></td>
                    <td className="px-6 py-4"><div className="flex items-center gap-1.5 flex-wrap">{member.module_roles && Object.entries(member.module_roles).map(([appId, role]) => (<span key={appId} className="inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-bold ring-1 ring-inset uppercase tracking-wider bg-white/10 text-white/70 border border-white/5">{appId}: {role}</span>))}{(!member.module_roles || Object.keys(member.module_roles).length === 0) && <span className="text-white/30 italic text-xs">Sin acceso</span>}</div></td>
                    <td className="px-6 py-4 text-right"><button onClick={() => handleEditUser(member)} className="text-white/50 hover:text-white font-medium transition-colors focus:outline-none">Editar</button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="rounded-xl border border-white/10 bg-white/5 shadow-xl overflow-hidden p-8 animate-in fade-in slide-in-from-bottom-2 duration-300 backdrop-blur-md">
            <form onSubmit={handleInviteUser} className="max-w-5xl">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-x-16 gap-y-8">
                <div className="space-y-6">
                  <h3 className="text-xs font-bold uppercase tracking-widest text-white/40 border-b border-white/5 pb-2 mb-6">Datos del Colaborador</h3>
                  <div className="grid grid-cols-3 items-center gap-4"><label className="text-sm font-medium text-white/50 text-right">Nombre</label><input type="text" required value={inviteName} onChange={(e) => setInviteName(e.target.value)} className="col-span-2 rounded-md border-white/10 bg-white/5 py-1.5 text-sm text-white focus:ring-2 focus:ring-white/20 transition-all placeholder:text-white/20" placeholder="ej. Juan Pérez" /></div>
                  <div className="grid grid-cols-3 items-center gap-4"><label className="text-sm font-medium text-white/50 text-right">Email</label><input type="email" required={!editingUserId} disabled={!!editingUserId} value={inviteEmail} onChange={(e) => setInviteEmail(e.target.value)} className="col-span-2 rounded-md border-white/10 bg-white/5 py-1.5 text-sm text-white focus:ring-2 focus:ring-white/20 transition-all placeholder:text-white/20 disabled:opacity-50 disabled:cursor-not-allowed" placeholder={editingUserId ? 'Correo no especificado o reservado' : 'juan@datix.cl'} /></div>
                  <div className="grid grid-cols-3 items-center gap-4"><label className="text-sm font-medium text-white/50 text-right">Contraseña Inicial</label><input type="text" required={!editingUserId} disabled={!!editingUserId} value={invitePassword} onChange={(e) => setInvitePassword(e.target.value)} className="col-span-2 rounded-md border-white/10 bg-white/5 py-1.5 text-sm text-white focus:ring-2 focus:ring-white/20 transition-all placeholder:text-white/20 disabled:opacity-50 disabled:cursor-not-allowed" placeholder={editingUserId ? 'No modificable desde aquí' : 'Ej: Temporal123!'} /></div>
                  <div className="grid grid-cols-3 items-center gap-4"><label className="text-sm font-medium text-white/50 text-right">Rol Portal</label><select value={inviteRole} onChange={(e) => setInviteRole(e.target.value)} className="col-span-2 rounded-md border-white/10 bg-[#5B4385] py-1.5 text-sm text-white focus:ring-2 focus:ring-white/20 transition-all"><option value="MEMBER">Miembro / Empleado Base</option><option value="OWNER">Dueño / Admin Total</option></select></div>
                </div>
                <div className="space-y-4">
                  <h3 className="text-xs font-bold uppercase tracking-widest text-white/40 border-b border-white/5 pb-2 mb-6">Permisos por Módulo</h3>
                  <div className="grid grid-cols-1 gap-3">
                    {AVAILABLE_APPS.map((app) => (
                      <div key={app.id} className={`p-3 rounded-lg border transition-all ${moduleRoles[app.id] ? 'bg-white/10 border-white/20 shadow-lg' : 'border-white/5 bg-white/5'}`}>
                        <div className="flex items-center justify-between cursor-pointer" onClick={() => handleToggleModule(app.id, app.roles[0].v)}>
                          <div className="flex items-center gap-3"><div className={`flex h-4 w-4 shrink-0 items-center justify-center rounded border transition-colors ${moduleRoles[app.id] ? 'bg-white text-[#45316D] border-white' : 'border-white/20 bg-transparent'}`}>{moduleRoles[app.id] && <Check className="h-2.5 w-2.5 stroke-[3px]" />}</div><span className={`text-sm font-bold ${moduleRoles[app.id] ? 'text-white' : 'text-white/40'}`}>{app.name}</span></div>
                          {moduleRoles[app.id] && (<select value={moduleRoles[app.id]} onClick={(e) => e.stopPropagation()} onChange={(e) => handleChangeModuleRole(app.id, e.target.value)} className="rounded-md border-white/10 bg-[#5B4385] px-2 py-0.5 text-xs font-medium text-white focus:ring-2 focus:ring-white/20 transition-all ml-4">{app.roles.map((r) => (<option key={r.v} value={r.v}>{r.l}</option>))}</select>)}
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
          <div><h1 className="text-2xl font-bold tracking-tight text-white sm:text-3xl">Facturación</h1><p className="mt-1 text-sm text-white/60">Gestiona tu suscripción y métodos de pago.</p></div>
          <button onClick={() => setActiveTab('apps')} className="inline-flex items-center justify-center gap-2 rounded-lg bg-white/10 border border-white/20 text-white shadow-sm hover:bg-white/20 transition-colors px-4 py-2 text-sm font-semibold">Cerrar</button>
        </header>
        <div className="space-y-6">
          <section className="overflow-hidden rounded-xl border border-white/10 bg-white/5 shadow-xl p-6 backdrop-blur-sm"><h3 className="text-sm font-semibold text-white mb-1">Plan de Suscripción</h3><p className="text-sm text-white/50 mb-6">Actualmente estás en el <strong className="text-white">Plan Base POS</strong>.</p><div className="bg-white/5 rounded-lg p-4 flex justify-between items-center border border-white/5"><div className="w-1/2"><p className="text-sm font-medium text-white/80">Uso de Base de Datos</p><p className="text-xs text-white/40">0.5GB / 1GB utilizado.</p></div><div className="w-1/3 bg-white/10 rounded-full h-2"><div className="h-2 rounded-full" style={{ width: '50%', backgroundColor: BRAND_PRIMARY }}></div></div></div></section>
          <section className="overflow-hidden rounded-xl border border-white/10 bg-white/5 shadow-xl pb-0 backdrop-blur-sm"><div className="p-6"><h3 className="text-sm font-semibold text-white mb-1">Historial de Facturación</h3><p className="text-sm text-white/50 mb-6">Tus últimos pagos realizados.</p><div className="overflow-x-auto"><table className="w-full text-left text-sm"><thead className="bg-white/5 text-white/40 border-b border-white/5"><tr><th className="px-6 py-4 font-semibold">Fecha</th><th className="px-6 py-4 font-semibold">Monto</th><th className="px-6 py-4 font-semibold">Factura</th><th className="px-6 py-4 font-semibold">Estado</th><th className="px-6 py-4 font-semibold text-right">Acción</th></tr></thead><tbody className="divide-y divide-white/5 italic text-white/30"><tr><td colSpan="5" className="px-6 py-8 text-center text-white/20">No hay facturas recientes.</td></tr></tbody></table></div></div></section>
          <button onClick={handleManageBilling} disabled={isBillingLoading} style={{ backgroundColor: BRAND_PRIMARY }} className="w-full rounded-xl px-6 py-3 text-white font-bold shadow-lg hover:opacity-90 transition-all active:scale-[0.98] disabled:opacity-50">{isBillingLoading ? 'Cargando...' : 'Gestionar en Stripe Billing'}</button>
        </div>
      </div>
    );
  }

  function renderSettingsTab() {
    return (
      <div className="mx-auto max-w-4xl">
        <header className="mb-8 flex items-center justify-between"><div><h1 className="text-2xl font-bold tracking-tight text-white sm:text-3xl">Configuración de la Cuenta</h1><p className="mt-1 text-sm text-white/60">Administra los detalles generales de tu empresa y perfiles.</p></div><button onClick={() => setActiveTab('apps')} className="inline-flex items-center justify-center gap-2 rounded-lg bg-white/10 border border-white/20 text-white shadow-sm hover:bg-white/20 transition-colors px-4 py-2 text-sm font-semibold">Cerrar</button></header>
        <div className="space-y-6"><section className="rounded-xl border border-white/10 bg-white/5 shadow-xl p-6 backdrop-blur-sm"><div className="flex items-center gap-4 mb-6"><div className="h-16 w-16 rounded-xl bg-white/5 flex items-center justify-center text-2xl font-bold text-white/30 border border-white/5">{company?.name?.[0].toUpperCase() || 'E'}</div><div><h2 className="text-lg font-bold text-white">{company?.name || 'Cargando empresa...'}</h2><p className="text-sm text-white/40">ID: {company?.id}</p></div></div><div className="grid grid-cols-1 md:grid-cols-2 gap-6 pt-4 border-t border-white/5"><div><label className="block text-xs font-bold uppercase tracking-wider text-white/40 mb-1">Nombre Legal</label><p className="text-sm font-medium text-white">{company?.name || 'Sin definir'}</p></div><div><label className="block text-xs font-bold uppercase tracking-wider text-white/40 mb-1">RUT Empresa</label><p className="text-sm font-medium text-white">76.000.000-0</p></div><div><label className="block text-xs font-bold uppercase tracking-wider text-white/40 mb-1">Tu Rol</label><p className="text-sm font-medium text-white font-bold">{userRole}</p></div><div><label className="block text-xs font-bold uppercase tracking-wider text-white/40 mb-1">Correo de Usuario</label><p className="text-sm font-medium text-white">{user?.email}</p></div></div></section></div>
      </div>
    );
  }
}
