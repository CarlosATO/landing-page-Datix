-- Verificación temporal del enlace Logística-Catálogo.

select *
from logistica.v_logistica_items_catalog
where company_id = '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b'::uuid
  and sku in ('TEST_CATALOG_CEMENTO', 'TEST_CATALOG_TALADRO');

select
  sku,
  name,
  item_kind,
  unit,
  is_stockable,
  is_purchasable,
  is_service,
  is_expense,
  is_returnable,
  category_name,
  is_active
from logistica.v_logistica_items_catalog
where company_id = '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b'::uuid
  and sku = 'TEST_CATALOG_CEMENTO';

select
  i.sku,
  i.catalog_item_id,
  ci.item_kind,
  ci.is_stockable
from logistica.items i
join public.catalog_items ci on ci.id = i.catalog_item_id
where i.company_id = '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b'::uuid
  and i.sku = 'TEST_CATALOG_CEMENTO';
