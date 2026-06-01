# Logistica

Scope:
- logistica schema
- inventory core
- manual receipt RPC
- stock transfer RPC
- stock issue RPC
- catalog link to shared items
- backend-owned warehouse RPCs
- backend-owned location RPCs
- transversal cost centers for stock accounting
- warehouse RPC architecture
- location RPC architecture

| Timestamp | File | Purpose | Status |
| --- | --- | --- | --- |
| 20260518153000 | `20260518153000_fix_internal_receipt_generation.sql` | Receipt generation fix | applied in remote |
| 20260518172000 | `20260518172000_harden_locations_rpc.sql` | Locations RPC hardening | applied in remote |
| 20260518175000 | `20260518175000_hardening_base.sql` | Base hardening / shared helpers | applied in remote |
| 20260518180000 | `20260518180000_create_logistica_schema_base.sql` | Logistica schema base | applied in remote |
| 20260518190000 | `20260518190000_create_logistica_inventory_core.sql` | Inventory core | applied in remote |
| 20260518193000 | `20260518193000_create_logistica_manual_receipt_rpc.sql` | Manual receipt RPC | applied in remote |
| 20260518194000 | `20260518194000_create_logistica_stock_transfer_rpc.sql` | Stock transfer RPC | applied in remote |
| 20260518203000 | `20260518203000_logistica_create_stock_issue_rpc.sql` | Stock issue / assignment / consumption RPC | pending local |
| 20260518210000 | `20260518210000_logistica_link_items_to_catalog.sql` | Link Logistica items to shared catalog and expose catalog view | pending local |
| 20260520153000 | `20260520153000_logistica_warehouse_rpcs.sql` | Backend-owned warehouse create/update/activate/deactivate RPCs | pending local |
| 20260522120000 | `20260522120000_create_public_cost_centers.sql` | Cost centers backbone and stock movement/balance linkage | pending local |
| 20260522124500 | `20260522124500_logistica_warehouse_rpcs.sql` | Hardened warehouse RPC flow with backend-owned auditing | pending local |
| 20260522131000 | `20260522131000_public_logistica_warehouse_rpc_wrappers.sql` | Public wrappers for warehouse RPC access | pending local |
| 20260522133000 | `20260522133000_logistica_fix_list_warehouses_rpc.sql` | Fix for backend-owned warehouse listing RPC | pending local |
| 20260522140000 | `20260522140000_logistica_location_rpcs.sql` | Backend-owned location RPC flow and public wrappers | pending local |
| 20260522153000 | `20260522153000_logistica_bulk_create_locations_rpc.sql` | Backend-owned bulk location creation RPC | pending local |
| 20260522170000 | `20260522170000_logistica_structured_locations.sql` | Structured location model and bulk generation | pending local |
| 20260522193000 | `20260522193000_logistica_manual_receipt_cost_center.sql` | Manual receipt RPC with mandatory cost center plus public wrappers for receipt and cost centers | pending local |
| 20260522215000 | `20260522215000_catalog_items_images_barcode_brand_model_import.sql` | Catalog metadata + image support and Logistica import helpers | pending local |
| 20260522223000 | `20260522223000_fix_logistica_materials_view_id.sql` | Fix for material listing against the operational view PK | pending local |
| 20260522224000 | `20260522224000_fix_logistica_materials_runtime_columns.sql` | Fix for material listing against runtime columns | pending local |
| 20260522231000 | `20260522231000_catalog_item_kind_material_mapping.sql` | Canonical `item_kind` mapping for Logistica materials | pending local |
| 20260522233000 | `20260522233000_fix_material_fields_persistence.sql` | Persistence fix for catalog metadata, image data and duplicate preflight | pending local |

## 20260518203000_logistica_create_stock_issue_rpc.sql

- Qué crea: `logistica.create_stock_issue(jsonb)`.
- Qué modifica: `logistica.stock_movements`, `logistica.stock_balances`, `logistica.item_serials`.
- Dependencias: `logistica.stock_balances`, `logistica.stock_movements`, `logistica.item_serials`, `logistica.items`, `public.projects`, `public.contractors`, `public.workers`, `public.has_company_access`, `public.has_module_access`, `public.is_owner`.
- Impacto: habilita salidas, consumos y asignaciones transaccionales desde Logística hacia maestros compartidos.
- Riesgos: una mala referencia de destino o serial puede bloquear la salida; un stock insuficiente aborta toda la transacción.
- Rollback lógico: `drop function logistica.create_stock_issue(jsonb);` y revocar `execute` si fuera necesario.

## 20260518210000_logistica_link_items_to_catalog.sql

- Qué crea: `logistica.v_logistica_items_catalog` y `logistica.create_logistica_item_from_catalog(jsonb)`.
- Qué modifica: `logistica.items.catalog_item_id` y su índice/constraint defensivo.
- Dependencias: `public.catalog_items`, `public.catalog_categories`, `public.audit_log`, `public.set_updated_at`, `public.audit_shared_master_change`, `public.has_company_access`, `public.has_module_access` y roles admin de Logistica.
- Impacto: Logistica pasa a consumir el catálogo transversal como fuente común de ítems.
- Nota: la RPC crea un snapshot inicial del catálogo y permite overrides controlados de nombre, descripción, unidad y flags operativos.
- Riesgos: si un catálogo no es stockable o no es compatible, la creación se bloquea por diseño; no rompe las rutas existentes.
- Rollback lógico: retirar la función/vista y dejar `catalog_item_id` sin uso si fuera necesario.

## 20260520153000_logistica_warehouse_rpcs.sql

- Qué crea: `logistica.list_warehouses(jsonb)`, `logistica.create_warehouse(jsonb)`, `logistica.update_warehouse(jsonb)`, `logistica.deactivate_warehouse(jsonb)` y wrappers públicos en `public` para consumo del frontend.
- Qué modifica: `logistica.warehouses` vía RPC backend-owned.
- Dependencias: `public.has_company_access`, `public.has_module_access`, `public.is_owner`, `public.has_role`, `public.company_users`, `public.company_modules`.
- Impacto: el frontend deja de consultar `logistica` directo y consume `public.list_warehouses`, `public.create_warehouse`, `public.update_warehouse`, `public.deactivate_warehouse`. La reactivación se resuelve con `update_warehouse(... is_active=true)`.
- Nota: esta capa reemplaza escrituras críticas directas desde UI; las bodegas siguen siendo maestras logísticas, pero el write path es del backend.
- Riesgos: si el rol o el estado del módulo no coincide, la RPC falla con error explícito; no debe usarse `service role` desde frontend.
- Rollback lógico: `drop function` de las RPCs y retirar el grant de execute si fuera necesario.

## 20260522131000_public_logistica_warehouse_rpc_wrappers.sql

- Qué crea: wrappers públicos `public.list_warehouses(jsonb)`, `public.create_warehouse(jsonb)`, `public.update_warehouse(jsonb)` y `public.deactivate_warehouse(uuid)`.
- Qué modifica: no toca tablas; solo expone el backend-owned flow a través de `public`.
- Dependencias: `logistica.list_warehouses`, `logistica.create_warehouse`, `logistica.update_warehouse`, `logistica.deactivate_warehouse`.
- Impacto: el cliente Supabase resuelve las RPCs en `public` sin abrir el schema `logistica` al frontend.
- Nota: los wrappers usan `SECURITY DEFINER` y `search_path` restringido.
- Rollback lógico: `drop function public.*_warehouse(...)` y retirar los grants si fuera necesario.

## 20260522133000_logistica_fix_list_warehouses_rpc.sql

- Qué crea: `logistica.list_warehouses(jsonb)` corregida/redefinida.
- Qué modifica: no toca tablas; asegura que la RPC real exista para que el wrapper público pueda delegar.
- Dependencias: `public.company_users`, `public.company_modules`, `public.has_role`, `logistica.warehouses`.
- Impacto: resuelve el error `function logistica.list_warehouses(jsonb) does not exist` sin cambiar frontend ni wrappers.
- Nota: mantiene `SECURITY DEFINER`, `search_path = logistica, public`, validación de `auth.uid()`, `company_id`, membresía y módulo activo/trial.
- Rollback lógico: `drop function logistica.list_warehouses(jsonb)` si fuera necesario.

## 20260522140000_logistica_location_rpcs.sql

- Qué crea: `logistica.list_locations(jsonb)`, `logistica.create_location(jsonb)`, `logistica.update_location(jsonb)`, `logistica.deactivate_location(uuid)` y wrappers públicos `public.*` para consumo del frontend.
- Qué modifica: `logistica.locations.location_type` para aceptar `shelf`, `rack`, `floor`, `bin`, `zone`, `external`, `other`.
- Dependencias: `public.company_users`, `public.company_modules`, `public.has_role`, `logistica.warehouses`, `logistica.locations`, `logistica.stock_balances`, `public.audit_log`.
- Impacto: Ubicaciones deja de depender de DML directo y pasa a un flujo backend-owned con listing por bodega, búsqueda, filtro activo/inactivo y auditoría con eventos `LOCATION_*`.
- Nota: el frontend consume `public.list_locations`, `public.create_location`, `public.update_location`, `public.deactivate_location`.
- Riesgos: la desactivación falla si hay stock disponible asociado a la ubicación.
- Rollback lógico: retirar las funciones y el cambio de constraint si fuera necesario.

## 20260522153000_logistica_bulk_create_locations_rpc.sql

- Qué crea: `logistica.create_locations_bulk(jsonb)` y el wrapper público `public.create_locations_bulk(jsonb)`.
- Qué modifica: no toca tablas nuevas; agrega creación masiva backend-owned para `logistica.locations`.
- Dependencias: `public.company_users`, `public.company_modules`, `public.has_role`, `logistica.warehouses`, `logistica.locations`, `public.audit_log`.
- Rol requerido: `OWNER` o `ADMIN_LOGISTICA`.
- Impacto: Ubicaciones puede generar lotes por patrón `prefix + número` con preview en frontend, modo estricto por defecto y opción de omitir existentes.
- Nota: el patrón reutiliza la idea de creación matricial de `farmacia_saas`, pero adaptado a bodega general y sin lógica de sububicaciones.
- Riesgos: si el prefijo/rango genera un duplicado en modo estricto, la operación falla completa.
- Rollback lógico: retirar la función y su wrapper si fuera necesario.

## 20260522170000_logistica_structured_locations.sql

- Qué crea: campos físicos opcionales en `logistica.locations`, helper `logistica.compose_location_code(...)` y redefinición de RPCs para soportar ubicación simple y estructurada.
- Qué modifica: `logistica.locations` agrega `aisle_code`, `column_number`, `level_number`, `division_code` y `structured_code`.
- Dependencias: `public.company_users`, `public.company_modules`, `public.has_role`, `logistica.locations`, `logistica.warehouses`, `public.audit_log`.
- Impacto: la UI puede guardar ubicaciones manuales simples o estructuradas y crear lotes por pasillo/columna/nivel/división.
- Nota: `code` sigue siendo el identificador visual principal; los componentes separados permiten reportes y mapas físicos sin parsear texto libre.
- Rollback lógico: quitar columnas y retirar/reemplazar las funciones si fuera necesario.

## 20260522193000_logistica_manual_receipt_cost_center.sql

- Qué crea: redefine `logistica.create_manual_receipt(jsonb)`, ajusta el índice único de `logistica.stock_balances`, crea `public.list_cost_centers(jsonb)` y `public.create_manual_receipt(jsonb)`.
- Qué modifica: `logistica.stock_movements.cost_center_id` y `logistica.stock_balances.cost_center_id` pasan a ser obligatorios para recepción manual.
- Dependencias: `public.cost_centers`, `public.v_cost_centers_summary`, `public.has_company_access`, `public.has_module_access`, `public.is_owner`, `public.has_role`, `logistica.warehouses`, `logistica.locations`, `logistica.items`, `logistica.item_lots`, `logistica.item_serials`, `logistica.stock_movements`, `logistica.stock_balances`.
- Impacto: el frontend de recepción puede operar sin Adquisiciones, pero siempre imputando stock a un centro de costo válido de la empresa.
- Nota: la recepción manual sigue siendo por RPC; no hay DML directo desde UI.
- Riesgos: el flujo asume que `stock_balances` se segmenta por centro de costo; otros RPCs de stock aún pueden requerir ajuste posterior si se usan con balances no nulos.
- Rollback lógico: restaurar la función previa, retirar wrappers y volver al índice anterior si fuese estrictamente necesario.

## 20260522215000_catalog_items_images_barcode_brand_model_import.sql

- Qué crea: `public.search_similar_catalog_items(jsonb)`, `public.list_catalog_material_candidates(jsonb)`, `public.list_logistica_materials(jsonb)`, `public.create_logistica_material(jsonb)`, `public.update_logistica_material(jsonb)`, `public.update_catalog_item_image(jsonb)` y policies privadas para `catalog-items`.
- Qué modifica: `public.catalog_items` para persistir `barcode`, `brand`, `model`, `observation` e imagen privada.
- Impacto: Logistica puede buscar, crear y habilitar materiales con metadata comercial sin tocar otros módulos.
- Nota: la imagen se almacena en `catalog-items` por empresa con path privado y se actualiza vía RPC, no por DML directo desde UI.

## 20260522231000_catalog_item_kind_material_mapping.sql

- Qué crea: helper `public.normalize_catalog_item_kind(text)` y redefiniciones de `create_logistica_material` / `update_logistica_material`.
- Qué modifica: el flujo de materiales pasa a tratar `material` como canónico y deja `physical` solo como alias legacy.
- Impacto: la UI muestra `Material` pero el backend sigue validando contra el check real del catálogo sin romper compatibilidad.

## 20260522233000_fix_material_fields_persistence.sql

- Qué crea: redefine los RPCs de búsqueda, listado, creación, edición y actualización de imagen para que el catálogo no pierda metadata.
- Qué modifica: `list_logistica_materials` y `search_similar_catalog_items` vuelven a exponer barcode/marca/modelo/observación/imagen para que el frontend refresque correctamente.
- Impacto: el flujo de creación/edición ya devuelve `catalog_item_id` y `logistica_item_id`, permitiendo subir imagen y persistir metadata sin perder el vínculo.

## 20260522120000_create_public_cost_centers.sql

- Qué crea: `public.cost_centers` y `public.v_cost_centers_summary`.
- Qué modifica: `public.projects.cost_center_id`, `logistica.stock_movements.cost_center_id` y `logistica.stock_balances.cost_center_id`.
- Dependencias: `public.projects`, `public.has_company_access`, `public.can_manage_company_roles`, `public.audit_shared_master_change`, `public.set_updated_at`.
- Impacto: Logística queda lista para exigir `cost_center_id` en el futuro sin romper históricos existentes.
- Nota: `cost_center_id` puede quedar nulo solo por compatibilidad histórica; el flujo operativo nuevo debe imputar siempre.
- Rollback lógico: quitar columnas, vista, triggers y policies nuevas si fuera necesario.

## Warehouse RPC Architecture

- La UI de Bodegas no debe escribir ni consultar directamente sobre `logistica.warehouses`.
- El flujo oficial de acceso es: `public.list_warehouses`, `public.create_warehouse`, `public.update_warehouse`, `public.deactivate_warehouse`.
- Las funciones backend internas viven en `logistica` y los wrappers públicos las exponen sin abrir el schema `logistica` al frontend.
- Las RPCs son `SECURITY DEFINER`, validan `auth.uid()`, empresa, módulo y roles, y emiten auditoría backend-only.
- La desactivación es soft delete y se bloquea si existen `stock_balances` o `locations` activas asociadas.
- El frontend solo consume listado, abre formularios, dispara RPCs y refresca estado.
