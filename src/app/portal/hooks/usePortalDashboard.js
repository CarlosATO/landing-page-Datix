import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { createBrowserClient } from '@supabase/ssr';
import { createPortalApi } from '../services/portalApi';
import { AVAILABLE_APPS, getPortalModuleState, toUpperValue } from '../utils/portalConstants';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || 'https://placeholder-url.supabase.co';
const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || 'placeholder-key';
const supabase = createBrowserClient(supabaseUrl, supabaseKey);
const api = createPortalApi(supabase);

export function usePortalDashboard() {
  const router = useRouter();
  const hasFetched = useRef(false);
  const hasProcessedHash = useRef(false);

  const [user, setUser] = useState(null);
  const [company, setCompany] = useState(null);
  const [companyId, setCompanyId] = useState(null);
  const [loading, setLoading] = useState(true);
  const [isBillingLoading, setIsBillingLoading] = useState(false);
  const [activeTab, setActiveTab] = useState('apps');
  const [userRole, setUserRole] = useState(null);
  const [teamMembers, setTeamMembers] = useState([]);
  const [companyModules, setCompanyModules] = useState([]);
  const [contractedCompanyModules, setContractedCompanyModules] = useState([]);
  const [isSavingOnboarding, setIsSavingOnboarding] = useState(false);
  const [onboardingData, setOnboardingData] = useState({ rut: '', activity: '', address: '', city: '', phone: '', fantasy_name: '' });
  const [teamViewMode, setTeamViewMode] = useState('list');
  const [isInviting, setIsInviting] = useState(false);
  const [editingUserId, setEditingUserId] = useState(null);
  const [inviteEmail, setInviteEmail] = useState('');
  const [inviteName, setInviteName] = useState('');
  const [invitePassword, setInvitePassword] = useState('');
  const [inviteRole, setInviteRole] = useState('MEMBER');
  const [moduleRoles, setModuleRoles] = useState({});
  const [needsPasswordChange, setNeedsPasswordChange] = useState(false);
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [isChangingPassword, setIsChangingPassword] = useState(false);
  const [userAppAccess, setUserAppAccess] = useState({});

  const visibleApps = useMemo(() => {
    if (!contractedCompanyModules || !contractedCompanyModules.length) return [];
    
    // Determine which apps from AVAILABLE_APPS are contracted.
    // An app is visible in "Mis módulos" if its module_key matches a contracted module.
    return AVAILABLE_APPS.filter((app) => {
      const appModuleKey = app.moduleKey || app.id.toLowerCase();
      // Farmacias exception mapping if needed, or exact match
      const matchingContract = contractedCompanyModules.find(m => 
        m.module_key_normalized === appModuleKey ||
        (appModuleKey === 'farmacias' && (m.module_key_normalized === 'farmacia' || m.module_key_normalized === 'pharmacy'))
      );
      
      if (!matchingContract) return false;
      
      // Also verify if the user has access via userAppAccess?
      // User says: "No usar `userAppAccess` para decidir contratación." 
      // User also says: "En “Mis módulos” debe aparecer SOLO lo contratado/habilitado por esa empresa."
      // Let's just return true if it's contracted. We'll enforce user-level access upon entry or handle it differently if needed,
      // but "Mis módulos" represents company's active modules.
      return true;
    });
  }, [contractedCompanyModules]);

  const upsellApps = useMemo(() => {
    if (!contractedCompanyModules) return AVAILABLE_APPS;
    
    return AVAILABLE_APPS.filter((app) => {
      const appModuleKey = app.moduleKey || app.id.toLowerCase();
      const isContracted = contractedCompanyModules.some(m => 
        m.module_key_normalized === appModuleKey ||
        (appModuleKey === 'farmacias' && (m.module_key_normalized === 'farmacia' || m.module_key_normalized === 'pharmacy'))
      );
      return !isContracted;
    });
  }, [contractedCompanyModules]);

  const bootstrap = useCallback(async () => {
    setLoading(true);
    try {
      const { data: { user: currentUser }, error: sessionError } = await supabase.auth.getUser();
      if (sessionError || !currentUser) {
        if (sessionError?.status === 429) {
          hasFetched.current = false;
          setTimeout(bootstrap, 2000);
          return;
        }
        router.push('/login');
        return;
      }

      setUser(currentUser);
      const { company_id: companyIdData, company: companyData, role, needsPasswordChange: needsChange, userAppAccess: access, teamMembers: teamData, companyModules: moduleData, contractedCompanyModules: contractedModuleData } = await api.bootstrap();

      setCompanyId(companyIdData || companyData?.id || null);
      setCompany(companyData);
      setOnboardingData({
        rut: companyData.rut || '',
        activity: companyData.activity || '',
        address: companyData.address || '',
        city: companyData.city || '',
        phone: companyData.phone || '',
        fantasy_name: companyData.fantasy_name || '',
      });
      setUserRole(role || 'MEMBER');
      setNeedsPasswordChange(Boolean(needsChange));
      setUserAppAccess(access || {});
      setTeamMembers(teamData || []);
      setCompanyModules(moduleData || []);
      setContractedCompanyModules(contractedModuleData || []);

      if (typeof window !== 'undefined' && window.location.hostname === 'localhost') {
        const moduleDiagnostics = AVAILABLE_APPS.map((app) => {
          const moduleState = getPortalModuleState(moduleData || [], app.id);

          return {
            module_key: moduleState.moduleKey || app.moduleKey || app.id.toLowerCase(),
            app_id: app.id,
            module_status: moduleState.status,
            contracted: moduleState.contracted,
            implemented: moduleState.implemented,
            enabled: moduleState.available,
            locked: !moduleState.available,
            comingSoon: moduleState.comingSoon,
            openUrl: moduleState.openUrl,
            blocked_reason: moduleState.blockedReason,
          };
        });

        console.debug('[portal bootstrap diagnostics]', {
          company_id: companyIdData || companyData?.id,
          company_name: companyData?.name,
          user_id: currentUser?.id,
          user_email: currentUser?.email,
          user_role: role || 'MEMBER',
          user_app_access: access || {},
          company_modules_raw: (moduleData || []).map((module) => ({
            module_key: module.module_key,
            status: module.status,
            enabled_at: module.enabled_at,
            disabled_at: module.disabled_at,
          })),
          company_modules_contracted: (contractedModuleData || []).map((module) => ({
            module_key: module.module_key,
            status: module.status,
          })),
          module_diagnostics: moduleDiagnostics,
        });
      }
    } catch (error) {
      console.error('Error al cargar datos:', error);
    } finally {
      setLoading(false);
    }
  }, [router]);

  useEffect(() => {
    if (hasFetched.current) return;
    hasFetched.current = true;

    const init = async () => {
      if (!hasProcessedHash.current && typeof window !== 'undefined' && window.location.hash.includes('access_token')) {
        hasProcessedHash.current = true;
        try {
          const params = new URLSearchParams(window.location.hash.substring(1));
          const access_token = params.get('access_token');
          const refresh_token = params.get('refresh_token');
          if (access_token && refresh_token) {
            window.history.replaceState(null, '', window.location.pathname);
            const { error: sessionError } = await supabase.auth.setSession({ access_token, refresh_token });
            if (sessionError) throw sessionError;
          }
        } catch (err) {
          console.error('Error sincronizando sesión en Portal:', err);
        }
      }

      await bootstrap();
    };

    init();
  }, [bootstrap]);

  const handleLogout = async () => {
    setLoading(true);
    await supabase.auth.signOut();
    router.push('/login');
  };

  const handleChangePassword = async (e) => {
    e.preventDefault();
    if (newPassword !== confirmPassword) throw new Error('Las contraseñas no coinciden');
    if (newPassword.length < 6) throw new Error('La contraseña debe tener al menos 6 caracteres');

    setIsChangingPassword(true);
    try {
      const { error: authError } = await supabase.auth.updateUser({ password: newPassword });
      if (authError) throw authError;
      await api.updateProfile(company.id, { must_change_password: false });
      alert('Contraseña actualizada con éxito.');
      setNeedsPasswordChange(false);
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
        fantasy_name: toUpperValue(onboardingData.fantasy_name) || toUpperValue(company.name),
      };
      const { company: updatedCompany } = await api.updateCompany(company.id, normalizedOnboarding);
      setCompany((prev) => ({ ...prev, ...updatedCompany }));
      setOnboardingData(normalizedOnboarding);
    } catch (error) {
      console.error('Error guardando onboarding:', error);
      alert('No se pudo guardar la configuración. Revisa los datos.');
    } finally {
      setIsSavingOnboarding(false);
    }
  };

  const openModule = async (appId) => {
    // Force refresh the session so app_metadata.company_id is present in the JWT.
    // On first login the portal creates the company and updates app_metadata server-side,
    // but the browser token is stale until a refresh is performed.
    let session;
    try {
      const { data: refreshed, error: refreshError } = await supabase.auth.refreshSession();
      if (refreshError || !refreshed?.session) {
        // Fallback: use current session even if stale
        const { data: current } = await supabase.auth.getSession();
        session = current?.session;
      } else {
        session = refreshed.session;
      }
    } catch {
      const { data: current } = await supabase.auth.getSession();
      session = current?.session;
    }

    const hostname = typeof window !== 'undefined' ? window.location.hostname : 'localhost';
    if (!session) {
      router.push('/login');
      return;
    }
    const passSessionInHash = process.env.NODE_ENV !== 'production' || hostname === 'localhost' || hostname === '127.0.0.1';
    const authHash = passSessionInHash ? `#access_token=${session.access_token}&refresh_token=${session.refresh_token}` : '';
    const urls = {
      POS: `http://${hostname}:5173/pos${authHash}`,
      LOGISTICA: `http://${hostname}:5176/${authHash}`,
      CONSTRUCCION: `http://${hostname}:5177/construccion${authHash}`,
      ADQUISICIONES: `http://${hostname}:5174/dashboard-compras${authHash}`,
      FARMACIAS: `http://${hostname}:5175${authHash}`,
    };

    if (process.env.NODE_ENV !== 'production') {
      console.debug('[portal openModule]', {
        appId,
        has_access_token: Boolean(session?.access_token),
        has_refresh_token: Boolean(session?.refresh_token),
        has_company_id_in_token: Boolean(session?.user?.app_metadata?.company_id),
        company_id_from_token: session?.user?.app_metadata?.company_id || null,
      });
    }

    if (urls[appId]) window.location.href = urls[appId];
  };

  const handleOpenApp = async (appId) => {
    if (appId === 'POS' || appId === 'LOGISTICA' || appId === 'CONSTRUCCION' || appId === 'ADQUISICIONES' || appId === 'FARMACIAS') return openModule(appId);
  };

  const handleToggleModule = (appId, defaultRole) => {
    setModuleRoles((prev) => {
      const next = { ...prev };
      if (next[appId]) delete next[appId];
      else next[appId] = defaultRole;
      return next;
    });
  };

  const handleChangeModuleRole = (appId, newRole) => {
    setModuleRoles((prev) => ({ ...prev, [appId]: newRole }));
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

  const refreshPortal = async () => {
    const { company_id: companyIdData, company: companyData, role, needsPasswordChange: needsChange, userAppAccess: access, teamMembers: teamData, companyModules: moduleData, contractedCompanyModules: contractedModuleData } = await api.bootstrap();
    setCompany(companyData);
    setCompanyId(companyIdData || companyData?.id || null);
    setUserRole(role || 'MEMBER');
    setNeedsPasswordChange(Boolean(needsChange));
    setUserAppAccess(access || {});
    setTeamMembers(teamData || []);
    setCompanyModules(moduleData || []);
    setContractedCompanyModules(contractedModuleData || []);
  };

  const handleInviteUser = async (e) => {
    e.preventDefault();
    setIsInviting(true);
    try {
      if (editingUserId) {
        await api.updateTeamMember({ companyId: company.id, userId: editingUserId, fullName: inviteName, globalRole: inviteRole, moduleRoles });
        alert('Usuario actualizado con éxito!');
      } else {
        await api.inviteTeamMember({ email: inviteEmail, password: invitePassword, fullName: inviteName, globalRole: inviteRole, companyId: company.id, moduleRoles });
        alert('Usuario invitado con éxito!');
      }
      await refreshPortal();
      setTeamViewMode('list');
      setEditingUserId(null);
      setInviteEmail('');
      setInviteName('');
      setInvitePassword('');
      setInviteRole('MEMBER');
      setModuleRoles({});
    } catch (error) {
      console.error('Error en el cliente:', error);
      alert(error.message);
    } finally {
      setIsInviting(false);
    }
  };

  const handleManageBilling = async () => {
    if (!company?.id) return;
    setIsBillingLoading(true);
    try {
      const data = await api.openBillingPortal(company.id);
      if (data.url) window.location.href = data.url;
    } finally {
      setIsBillingLoading(false);
    }
  };

  return {
    user,
    company,
    companyId,
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
    userAppAccess,
    visibleApps,
    upsellApps,
    contractedCompanyModules,
    handleLogout,
    handleChangePassword,
    handleSaveOnboarding,
    handleOpenApp,
    handleToggleModule,
    handleChangeModuleRole,
    handleEditUser,
    handleInviteUser,
    handleManageBilling,
    bootstrap,
  };
}
