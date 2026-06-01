-- Limpieza temporal del enlace Logística-Catálogo.

do $$
declare
  v_company_id uuid := '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b';
begin
  delete from logistica.items
  where company_id = v_company_id
    and sku in ('TEST_CATALOG_CEMENTO', 'TEST_CATALOG_FLETE', 'TEST_CATALOG_TALADRO');

  delete from public.catalog_items
  where company_id = v_company_id
    and sku in ('TEST_CATALOG_CEMENTO', 'TEST_CATALOG_FLETE', 'TEST_CATALOG_TALADRO');

  delete from public.catalog_categories
  where company_id = v_company_id
    and code in ('TEST_CAT_MATERIAL_LINK', 'TEST_CAT_SERVICE_LINK');
end;
$$;
