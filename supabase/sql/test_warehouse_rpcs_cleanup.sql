-- Limpieza temporal de pruebas de bodegas Logística.

do $$
declare
  v_company_id uuid := '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b';
begin
  delete from public.audit_log
  where company_id = v_company_id
    and coalesce(new_data::text, old_data::text, '') like '%TEST_WH_%';

  delete from logistica.stock_balances b
  using logistica.warehouses w
  where b.company_id = v_company_id
    and w.company_id = v_company_id
    and b.warehouse_id = w.id
    and w.code in ('TEST_WH_STOCK_001', 'TEST_WH_LOC_001', 'TEST_WH_OK_001');

  delete from logistica.locations
  where company_id = v_company_id
    and code in ('TEST_WH_LOC_001');

  delete from logistica.warehouses
  where company_id = v_company_id
    and code in ('TEST_WH_STOCK_001', 'TEST_WH_LOC_001', 'TEST_WH_OK_001');

  delete from logistica.items
  where company_id = v_company_id
    and sku = 'TEST_WH_ITEM_001';

  delete from logistica.item_categories
  where company_id = v_company_id
    and name = 'TEST_WH_CAT_001';
end;
$$;
