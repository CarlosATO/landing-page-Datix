-- Limpieza temporal de pruebas de ubicaciones Logística.

do $$
declare
  v_company_id uuid := '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b';
begin
  delete from public.audit_log
  where company_id = v_company_id
    and coalesce(new_data::text, old_data::text, '') like '%TEST_LOC_%';

  delete from logistica.stock_balances b
  using logistica.locations l
  where b.company_id = v_company_id
    and l.company_id = v_company_id
    and b.location_id = l.id
    and (
      l.code in ('STOCK-A', 'PATIO-A')
      or l.code like 'A-C%'
      or l.code like 'B-C%'
    );

  delete from logistica.locations
  where company_id = v_company_id
    and (
      code in ('STOCK-A', 'PATIO-A')
      or code like 'A-C%'
      or code like 'B-C%'
    );

  delete from logistica.warehouses
  where company_id = v_company_id
    and code = 'TEST_LOC_WH_001';

  delete from logistica.items
  where company_id = v_company_id
    and sku = 'TEST_LOC_ITEM_001';

  delete from logistica.item_categories
  where company_id = v_company_id
    and name = 'TEST_LOC_CAT_001';
end;
$$;
