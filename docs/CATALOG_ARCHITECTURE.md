# Catalog Architecture

The Datix catalog is a shared source of truth for items, materials, services and expenses.

It does not belong to Logistica or Adquisiciones.

How it is used:
- Logistica uses stockable and controllable items.
- Adquisiciones uses physical items, services and expenses for purchasing.
- Construccion can attach catalog items and costs to works and projects.
- Future modules should group reporting by `item_kind`, category, cost, purchase type and project.

Operational guidance:
- When Adquisiciones is contracted, formal receipts should ideally originate from purchase orders or receipt orders.
- When only Logistica exists, the system can still create physical items and manual receipts.

Design notes:
- `public.catalog_categories` groups the catalog by domain meaning.
- `public.catalog_items` holds the shared item definition.
- `public.catalog_items.item_kind` is canonicalized to `material`, `tool` and `equipment` for Logistica flows; legacy `physical` is treated as material.
- `public.catalog_items` also stores commercial metadata such as `barcode`, `brand`, `model`, `observation` and private image metadata (`image_path`, `image_mime_type`, `image_size_bytes`, `image_updated_at`).
- `logistica.items.catalog_item_id` links the operational Logistica configuration to the shared catalog.
- `logistica.v_logistica_items_catalog` exposes the operational/catalog join for UI and reports.
- `logistica.create_logistica_item_from_catalog` creates the Logistica configuration from the shared catalog snapshot.
