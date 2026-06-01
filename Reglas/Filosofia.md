# DATIX — REGLAS OFICIALES DE ARQUITECTURA BACKEND Y MIGRACIONES

## Objetivo

Este documento define las reglas obligatorias para crear nuevos módulos en Datix SaaS.

Aplica para:

* Logística
* Construcción
* Adquisiciones
* Farmacia
* Futuros módulos (Restaurant, RRHH, etc.)

Cada migración backend nueva debe:

Crearse en:

landing-page-Datix/supabase/migrations/

Tener naming:

timestamp + dominio + accion

Actualizar:

docs/migration-domains/<dominio>.md
Explicar:
qué crea
qué modifica
dependencias
impacto
riesgos
rollback lógico si aplica

Estas reglas NO son opcionales.

---

# 1. FILOSOFÍA GENERAL

Datix NO es una aplicación frontend.

Datix es:

* PostgreSQL + Supabase
* Arquitectura multi-tenant
* Backend transaccional
* RLS estricto
* Auditoría obligatoria
* Frontend desacoplado

El frontend:

* muestra información
* consume APIs
* guía UX

Pero:

* la base de datos protege
* el backend decide
* las transacciones garantizan consistencia

---

# 2. ARQUITECTURA OFICIAL DATIX

## Plataforma central (`public`)

El schema `public` es la base común del SaaS.

Contiene:

* companies
* company_modules
* user_roles
* audit_log
* helpers RLS
* permisos globales
* lógica multi-tenant
* funciones de acceso

Ejemplos:

* public.has_company_access()
* public.has_module_access()
* public.has_role()
* public.is_owner()

Todos los módulos dependen de esta base.

---

## Módulos funcionales

Cada módulo vive en SU PROPIO SCHEMA.

Ejemplos:

* pharmacy.*
* logistica.*
* construccion.*
* adquisiciones.*

IMPORTANTE:

❌ Nunca crear schemas por empresa.

Correcto:

* un schema funcional
* separación por `company_id`
* RLS estricto

---

# 3. REGLA CRÍTICA — MIGRACIONES

## TODA migración debe aplicarse inmediatamente a Supabase remoto

Flujo obligatorio:

1. Crear migración
2. Revisar SQL
3. Aplicar inmediatamente
4. Verificar schema/tablas/functions
5. Recién después continuar desarrollo frontend/backend

Nunca acumular migraciones sin aplicar.

---

# 4. ESTRUCTURA OBLIGATORIA POR MÓDULO

Cada módulo SaaS debe tener:

```text
modulo_saas/
├── src/
├── supabase/
│   ├── migrations/
│   ├── functions/
│   └── sql/
├── package.json
├── vite.config.js
└── README.md
```

Ejemplo real:

```text
logistica_saas/
construccion_saas/
farmacia_saas/
```

---

# 5. REGLA DE HISTORIAL DE MIGRACIONES

Todos los módulos deben mantener el historial compatible con el remoto.

Si el remoto ya tiene migraciones aplicadas:

* el módulo debe tener copia local de esas migraciones
* aunque pertenezcan a la plataforma base

Esto evita:

```text
Remote migration versions not found in local migrations directory
```

---

# 6. ORDEN CORRECTO DE MIGRACIONES

Siempre:

## Primero

Migraciones base/platform:

* helpers RLS
* company_modules
* user_roles
* funciones public.*
* auditoría global

## Después

Migraciones del módulo:

* schema modulo
* tablas
* triggers
* policies
* RPCs

Nunca al revés.

---

# 7. REGLA DE SEGURIDAD

## El frontend NO escribe datos críticos directamente

Nunca hacer:

```js
await supabase.from("items").insert(...)
```

para operaciones críticas.

Correcto:

Frontend
→ API / RPC
→ backend transaccional
→ PostgreSQL decide

---

# 8. OPERACIONES CRÍTICAS

Toda operación crítica debe ser:

* transaccional
* auditable
* reversible
* protegida por RLS

Ejemplos:

* recepciones
* stock
* transferencias
* pagos
* órdenes
* avances de obra

---

# 9. REGLA DE RLS

Toda tabla operacional debe tener:

```sql
company_id uuid not null
```

Y políticas usando:

```sql
public.has_company_access(company_id)
```

Más control modular:

```sql
public.has_module_access(company_id, 'logistica')
```

---

# 10. REGLA DE ROLES

Modelo híbrido oficial:

## Global

* OWNER

## Modulares

* ADMIN_LOGISTICA
* OPERARIO_LOGISTICA
* SUPERVISOR_OBRA
* etc.

Nunca mezclar permisos globales con operativos.

---

# 11. REGLA DE AUDITORÍA

Toda operación crítica debe registrar:

* usuario
* acción
* tabla
* datos anteriores
* datos nuevos
* timestamp

Nunca depender solo de logs frontend.

---

# 12. REGLA DE SQL

Toda migración debe ser:

* defensiva
* reintentable
* idempotente

Usar:

```sql
create schema if not exists
create table if not exists
drop policy if exists
create or replace function
create index if not exists
```

Esto evita corrupción si una migración falla parcialmente.

---

# 13. REGLA DE MÓDULOS

El portal central:

* autentica
* controla acceso
* abre módulos

Los módulos:

* respetan sesión Supabase
* respetan company_modules
* respetan roles

Nunca autenticación separada por módulo.

---

# 14. REGLA DE NAVEGACIÓN

Arquitectura oficial:

```text
portal.datix.cl
logistica.datix.cl
construccion.datix.cl
adquisiciones.datix.cl
```

Pero:

* misma sesión
* mismo auth
* mismo tenant
* misma fuente de verdad

---

# 15. REGLA FINAL

Datix NO se construye:

* rápido
* improvisado
* frontend-first

Datix se construye:

* backend-first
* transaction-first
* audit-first
* scalable-first
* enterprise-first
