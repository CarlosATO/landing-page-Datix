# Migrations Catalog

Supabase CLI only reads the physical files under `supabase/migrations/`.
This catalog is documentation only and groups migrations by domain.

Current pending migrations:
- `20260518195000_create_public_shared_operational_masters.sql`
- `20260518203000_logistica_create_stock_issue_rpc.sql`
- `20260518205000_public_create_catalog_items.sql`
- `20260518210000_logistica_link_items_to_catalog.sql`
- `20260520153000_logistica_warehouse_rpcs.sql`
- `20260522120000_create_public_cost_centers.sql`
- `20260522124500_logistica_warehouse_rpcs.sql`
- `20260522131000_public_logistica_warehouse_rpc_wrappers.sql`
- `20260522133000_logistica_fix_list_warehouses_rpc.sql`
- `20260522140000_logistica_location_rpcs.sql`
- `20260522153000_logistica_bulk_create_locations_rpc.sql`
- `20260522170000_logistica_structured_locations.sql`
- `20260522193000_logistica_manual_receipt_cost_center.sql`
- `20260522215000_catalog_items_images_barcode_brand_model_import.sql`
- `20260522223000_fix_logistica_materials_view_id.sql`
- `20260522224000_fix_logistica_materials_runtime_columns.sql`
- `20260522231000_catalog_item_kind_material_mapping.sql`
- `20260522233000_fix_material_fields_persistence.sql`

## A. Platform Central / Public
- `20260518195000_create_public_shared_operational_masters.sql` - shared operational masters in `public` - pending
- `20260518205000_public_create_catalog_items.sql` - shared catalog items/categories and Logistica catalog link - pending local
- `20260522120000_create_public_cost_centers.sql` - transversal cost centers and project linkages - pending local
- `20260518133000_hardening_base.sql` - archived legacy platform hardening - archived in `docs/sql_archive/`

## B. Pharmacy
- See `docs/migration-domains/pharmacy.md`

## C. Logistica
- `20260518203000_logistica_create_stock_issue_rpc.sql` - stock issue / assignment / consumption RPC - pending local
- `20260518210000_logistica_link_items_to_catalog.sql` - link Logistica items to shared catalog and add catalog view - pending local
- `20260520153000_logistica_warehouse_rpcs.sql` - backend-owned warehouse RPCs - pending local
- `20260522120000_create_public_cost_centers.sql` - cost centers backbone for stock accounting - pending local
- `20260522124500_logistica_warehouse_rpcs.sql` - hardened backend-owned warehouse RPC flow - pending local
- `20260522131000_public_logistica_warehouse_rpc_wrappers.sql` - public RPC wrappers for warehouse access - pending local
- `20260522133000_logistica_fix_list_warehouses_rpc.sql` - fix for backend-owned warehouse listing RPC - pending local
- `20260522140000_logistica_location_rpcs.sql` - backend-owned location RPCs and public wrappers - pending local
- `20260522153000_logistica_bulk_create_locations_rpc.sql` - backend-owned bulk location creation RPC - pending local
- `20260522170000_logistica_structured_locations.sql` - structured location model and bulk generation - pending local
- `20260522193000_logistica_manual_receipt_cost_center.sql` - manual receipt RPC with mandatory cost center and public wrappers - pending local
- `20260522215000_catalog_items_images_barcode_brand_model_import.sql` - catalog barcode/brand/model/observation/image metadata, storage policies and Logistica import helpers - pending local
- `20260522223000_fix_logistica_materials_view_id.sql` - material listing fix against the operational view PK - pending local
- `20260522224000_fix_logistica_materials_runtime_columns.sql` - material listing runtime column fix using base tables - pending local
- `20260522231000_catalog_item_kind_material_mapping.sql` - canonical item_kind mapping and Logistica material validation - pending local
- `20260522233000_fix_material_fields_persistence.sql` - persistence fix for barcode/brand/model/observation/image and duplicate preflight - pending local
- See `docs/migration-domains/logistica.md`

## D. Construccion
- See `docs/migration-domains/construccion.md`

## E. Adquisiciones
- See `docs/migration-domains/adquisiciones.md`

## Notes
- Do not move applied migration files out of `supabase/migrations/`.
- Classification is informational only.
- The goal is to keep CLI history aligned while making domain ownership readable.
