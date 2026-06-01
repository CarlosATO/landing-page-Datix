-- Verificación temporal del catálogo transversal Datix.
-- Reemplazar el company_id placeholder antes de ejecutar.

select * from public.catalog_categories where company_id = '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b'::uuid and code in ('TEST_CAT_MATERIAL', 'TEST_CAT_SERVICE');

select
  ci.sku,
  ci.name,
  ci.item_kind,
  ci.unit,
  ci.is_stockable,
  ci.is_purchasable,
  ci.is_service,
  ci.is_expense,
  ci.tracks_lot,
  ci.tracks_serial,
  ci.tracks_expiration,
  cc.code as category_code
from public.catalog_items ci
left join public.catalog_categories cc on cc.id = ci.category_id
where ci.company_id = '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b'::uuid
  and ci.sku in ('TEST_ITEM_CEMENTO', 'TEST_ITEM_FLETE', 'TEST_ITEM_TALADRO')
order by ci.sku;

select
  i.sku,
  i.item_type,
  i.unit,
  i.tracks_serial,
  i.tracks_lot,
  i.catalog_item_id,
  ci.item_kind
from logistica.items i
left join public.catalog_items ci on ci.id = i.catalog_item_id
where i.company_id = '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b'::uuid
  and i.sku in ('TEST_ITEM_CEMENTO', 'TEST_ITEM_FLETE', 'TEST_ITEM_TALADRO')
order by i.sku;
