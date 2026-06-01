# Public

Scope:
- Platform central / shared backend
- companies, company_modules, user_roles, audit helpers, shared masters, shared catalog, cost centers, portal glue

| Timestamp | File | Purpose | Status |
| --- | --- | --- | --- |
| 20260518195000 | `20260518195000_create_public_shared_operational_masters.sql` | Shared operational masters in `public` | pending |
| 20260518205000 | `20260518205000_public_create_catalog_items.sql` | Shared catalog items and categories; links Logistica items to catalog | pending local |
| 20260522120000 | `20260522120000_create_public_cost_centers.sql` | Transversal cost centers, project linkage and stock accounting hooks | pending local |
| 20260522193000 | `20260522193000_logistica_manual_receipt_cost_center.sql` | Public wrappers for cost center listing and manual receipt | pending local |
| 20260522215000 | `20260522215000_catalog_items_images_barcode_brand_model_import.sql` | Catalog barcode/brand/model/observation/image metadata, storage policies and Logistica import helpers | pending local |
| 20260522231000 | `20260522231000_catalog_item_kind_material_mapping.sql` | Canonical `item_kind` mapping plus Logistica material RPCs | pending local |
| 20260522233000 | `20260522233000_fix_material_fields_persistence.sql` | Material persistence fix for catalog metadata, image data and duplicate preflight | pending local |

Notes:
- `20260518133000_hardening_base.sql` was archived to `docs/sql_archive/` and is not part of the active migration set.

## 20260518205000_public_create_catalog_items.sql

- Qué crea: `public.catalog_categories` y `public.catalog_items`.
- Qué modifica: agrega `logistica.items.catalog_item_id` como enlace al catálogo común.
- Dependencias: `public.companies`, `auth.users`, `public.audit_log`, `public.set_updated_at`, `public.audit_shared_master_change`, `public.has_company_access`, roles admin por módulo.
- Impacto: centraliza la definición de materiales, servicios, gastos, herramientas y equipos para todos los módulos.
- Riesgos: el catálogo común se vuelve la referencia principal; un mal enlazado afectaría integración entre módulos, pero no borra datos existentes.
- Rollback lógico: eliminar la función/fks nuevos y dejar `catalog_item_id` nulo en Logística si fuera necesario.

## 20260522120000_create_public_cost_centers.sql

- Qué crea: `public.cost_centers`, `public.v_cost_centers_summary` y el puente entre `public.projects` y `logistica.stock_movements` / `logistica.stock_balances`.
- Qué modifica: agrega `public.projects.cost_center_id` y `logistica.stock_movements.cost_center_id` / `logistica.stock_balances.cost_center_id`.
- Dependencias: `public.companies`, `public.projects`, `public.has_company_access`, `public.can_manage_company_roles`, `public.audit_shared_master_change`, `public.set_updated_at`.
- Impacto: habilita la imputación financiera transversal y evita movimientos huérfanos a futuro.
- Nota: `project_id` en `public.cost_centers` es opcional, pero solo se permite cuando `cost_center_type = 'project'`.
- Riesgos: la compatibilidad histórica sigue permitiendo `null` en `cost_center_id`, pero los flujos nuevos deberán exigirlo.
- Rollback lógico: retirar la vista, los triggers y las columnas nuevas si fuese necesario.

## 20260522193000_logistica_manual_receipt_cost_center.sql

- Qué crea: `public.list_cost_centers(jsonb)` y `public.create_manual_receipt(jsonb)`.
- Qué modifica: no abre DML directo; solo expone wrappers públicos para el flujo de recepción manual y el catálogo de centros de costo.
- Dependencias: `public.v_cost_centers_summary`, `public.has_company_access`, `logistica.create_manual_receipt`.
- Impacto: el frontend puede elegir centros de costo y registrar recepciones sin tocar `logistica` directo.
- Rollback lógico: eliminar los wrappers y sus grants si fuese necesario.

## 20260522215000_catalog_items_images_barcode_brand_model_import.sql

- Qué crea: helpers de path para storage privado, RPCs de catálogo/materiales, policies de `storage.objects` para `catalog-items` y soporte de import Excel para Logistica.
- Qué modifica: `public.catalog_items` agrega `barcode`, `brand`, `model`, `observation`, `image_path`, `image_mime_type`, `image_size_bytes`, `image_updated_at`.
- Dependencias: `public.catalog_items`, `public.catalog_categories`, `logistica.items`, `public.has_company_access`, `public.has_role`, `auth.uid()`, `storage.objects`.
- Impacto: el catálogo transversal ya puede persistir metadatos comerciales e imagen privada por empresa.
- Rollback lógico: retirar funciones/policies nuevas y dejar el catálogo sin la capa de imagen si fuera estrictamente necesario.

## 20260522231000_catalog_item_kind_material_mapping.sql

- Qué crea: helper `public.normalize_catalog_item_kind(text)` y redefiniciones de RPCs de Logistica para canonicalizar `material`, `tool` y `equipment`.
- Qué modifica: `public.catalog_items.kind_check` se reexpande para aceptar el mapping canónico y las RPCs validan `item_kind` antes de persistir.
- Dependencias: `public.catalog_items`, `public.catalog_categories`, `logistica.items`, `public.normalize_catalog_text`, `public.has_company_access`, `public.has_module_access`.
- Impacto: la UI puede usar `Material` como label y el backend lo traduce a la forma canónica sin romper históricos.
- Rollback lógico: volver al mapping previo si se necesitara compatibilidad legacy estricta.

## 20260522233000_fix_material_fields_persistence.sql

- Qué crea: redefine `search_similar_catalog_items`, `list_logistica_materials`, `create_logistica_material`, `update_logistica_material` y `update_catalog_item_image`.
- Qué modifica: asegura persistencia de `barcode`, `brand`, `model`, `observation`, `image_path` y metadatos de imagen en `public.catalog_items`, además del estado operativo en `logistica.items`.
- Dependencias: `public.catalog_items`, `logistica.items`, `public.catalog_categories`, `public.normalize_catalog_item_kind`, `public.normalize_catalog_text`, `public.has_company_access`, `public.has_module_access`.
- Impacto: el flujo UI -> Catálogo -> Logistica deja de perder metadata al crear, editar o subir imagen.
- Rollback lógico: volver a la definición anterior de las RPCs si fuera necesario.
