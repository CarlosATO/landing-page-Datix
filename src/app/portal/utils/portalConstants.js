export const BRAND_PRIMARY = '#4C3073';

export const AVAILABLE_APPS = [
  { id: 'POS', name: 'Caja POS', reversed: false, roles: [{ v: 'CASHIER', l: 'Cajero' }, { v: 'MANAGER', l: 'Jefe de Local' }] },
  { id: 'LOGISTICA', name: 'Logística', roles: [{ v: 'STOCKER', l: 'Bodeguero' }, { v: 'MANAGER', l: 'Jefe de Operaciones' }] },
  { id: 'RRHH', name: 'Recursos Humanos', roles: [{ v: 'ASSISTANT', l: 'Asistente' }, { v: 'ADMIN', l: 'Administrador' }] },
  { id: 'ADQUISICIONES', name: 'Adquisiciones', roles: [{ v: 'BUYER', l: 'Comprador' }, { v: 'MANAGER', l: 'Jefe de Compras' }] },
  { id: 'FARMACIAS', name: 'Farmacias', roles: [{ v: 'PHARMACIST', l: 'Químico Farmacéutico' }, { v: 'ASSISTANT', l: 'Asistente de Farmacia' }] }
];

export const APP_OPENERS = {
  POS: { label: 'Caja POS', port: 5173, path: '/pos' },
  ADQUISICIONES: { label: 'Adquisiciones', port: 5174, path: '/dashboard-compras' },
  FARMACIAS: { label: 'Farmacias', port: 5175, path: '' }
};

export const MODULE_METADATA_TO_ROLE = {
  pos: { POS: 'MANAGER' },
  adquisiciones: { ADQUISICIONES: 'MANAGER' },
  farmacias: { FARMACIAS: 'PHARMACIST' },
  logistica: { LOGISTICA: 'MANAGER' },
  rrhh: { RRHH: 'ADMIN' }
};

export const toUpperValue = (value) => (value ?? '').toString().toUpperCase();
