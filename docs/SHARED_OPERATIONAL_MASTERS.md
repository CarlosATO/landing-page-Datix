# Shared Operational Masters

`projects`, `contractors`, `workers` and `suppliers` live in `public` because they are shared masters for the whole Datix ecosystem.

Why they are centralized:
- They are not owned by a single functional module.
- Logistica, Construccion, Adquisiciones and future modules need the same source of truth.
- Duplicating them per module would create drift, inconsistent IDs and broken cross-module flows.

How modules use them:
- Logistica can create and consume them when a customer only has Logistica enabled.
- Construccion reuses `projects`, `contractors` and `workers` for works, crews and assignments.
- Adquisiciones reuses `suppliers` and `projects` for purchasing and sourcing flows.
- Future modules should reference these shared tables instead of creating module-local copies.

Operational rule:
- Module schemas should reference these masters from `public`, not duplicate them.
- `company_id` keeps tenant isolation while `public` keeps the ecosystem-wide model stable.

Security model:
- Visibility is controlled by `public.has_company_access(company_id)`.
- Management is restricted to `OWNER` and module admins allowed by the shared-master policy.
