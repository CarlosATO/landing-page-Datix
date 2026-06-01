export const BRAND_PRIMARY = '#4C3073';

export const AVAILABLE_APPS = [
  { id: 'POS', moduleKey: 'pos', name: 'Caja POS', reversed: false, roles: [{ v: 'CASHIER', l: 'Cajero' }, { v: 'MANAGER', l: 'Jefe de Local' }] },
  { id: 'LOGISTICA', moduleKey: 'logistica', name: 'Logística', roles: [{ v: 'STOCKER', l: 'Bodeguero' }, { v: 'MANAGER', l: 'Jefe de Operaciones' }] },
  { id: 'CONSTRUCCION', moduleKey: 'construccion', name: 'Construcción', roles: [{ v: 'ENGINEER', l: 'Jefe de Obra' }, { v: 'MANAGER', l: 'Administrador' }] },
  { id: 'RRHH', moduleKey: 'rrhh', name: 'Recursos Humanos', roles: [{ v: 'ASSISTANT', l: 'Asistente' }, { v: 'ADMIN', l: 'Administrador' }] },
  { id: 'ADQUISICIONES', moduleKey: 'adquisiciones', name: 'Adquisiciones', roles: [{ v: 'BUYER', l: 'Comprador' }, { v: 'MANAGER', l: 'Jefe de Compras' }] },
  { id: 'FARMACIAS', moduleKey: 'pharmacy', name: 'Farmacias', roles: [{ v: 'PHARMACIST', l: 'Químico Farmacéutico' }, { v: 'ASSISTANT', l: 'Asistente de Farmacia' }] }
];

export const APP_OPENERS = {
  POS: { label: 'Caja POS', port: 5173, path: '/pos' },
  LOGISTICA: { label: 'Logística', port: null, path: '/logistica' },
  CONSTRUCCION: { label: 'Construcción', port: null, path: '/construccion' },
  ADQUISICIONES: { label: 'Adquisiciones', port: 5174, path: '/dashboard-compras' },
  FARMACIAS: { label: 'Farmacias', port: 5175, path: '' }
};

export const PORTAL_MODULE_KEY_ALIASES = {
  POS: ['pos'],
  LOGISTICA: ['logistica'],
  CONSTRUCCION: ['construccion'],
  ADQUISICIONES: ['adquisiciones'],
  FARMACIAS: ['farmacias', 'farmacia', 'pharmacy'],
  RRHH: ['rrhh'],
};

export const normalizeModuleKey = (value) => (value ?? '').toString().trim().toLowerCase();

export const getModuleKeyAliases = (appId) => PORTAL_MODULE_KEY_ALIASES[appId] || [normalizeModuleKey(appId)];

export const findCompanyModuleForApp = (companyModules = [], appId) => {
  const aliases = getModuleKeyAliases(appId);
  return (companyModules || []).find((module) => aliases.includes(normalizeModuleKey(module?.module_key))) || null;
};

export const getPortalModuleState = (companyModules = [], appId) => {
  const companyModule = findCompanyModuleForApp(companyModules, appId);
  const moduleKey = companyModule?.module_key || null;
  const status = normalizeModuleKey(companyModule?.status || '');
  const contracted = ['active', 'trial'].includes(status);
  const implemented = Boolean(APP_OPENERS[appId]);
  const available = contracted && implemented;
  const contractedButPreparing = contracted && !implemented;
  const comingSoon = !contracted && !implemented;
  const noContract = !contracted && implemented;

  let blockedReason = null;
  if (available) blockedReason = null;
  else if (contractedButPreparing) blockedReason = 'contratado pero app en preparación';
  else if (comingSoon) blockedReason = 'próximamente';
  else if (noContract) blockedReason = 'no contratado';
  else if (!companyModule) blockedReason = 'sin fila en company_modules';
  else blockedReason = `status=${companyModule.status}`;

  return {
    moduleKey,
    status: companyModule?.status || null,
    contracted,
    implemented,
    available,
    contractedButPreparing,
    comingSoon,
    noContract,
    blockedReason,
    openUrl: implemented ? (APP_OPENERS[appId]?.path ?? null) : null,
  };
};

export const MODULE_METADATA_TO_ROLE = {
  pos: { POS: 'MANAGER' },
  adquisiciones: { ADQUISICIONES: 'MANAGER' },
  farmacias: { FARMACIAS: 'PHARMACIST' },
  logistica: { LOGISTICA: 'MANAGER' },
  construccion: { CONSTRUCCION: 'MANAGER' },
  rrhh: { RRHH: 'ADMIN' }
};

export const toUpperValue = (value) => (value ?? '').toString().toUpperCase();
