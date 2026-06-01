-- Limpieza temporal de la prueba de recepción manual con centro de costo.

do $$
declare
  v_company_id uuid := '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b';
begin
  delete from public.audit_log
  where company_id = v_company_id
    and coalesce(new_data::text, old_data::text, '') like '%TEST_LOG_RECEIPT_CC_001%';

  delete from logistica.audit_log
  where company_id = v_company_id
    and coalesce(new_data::text, old_data::text, '') like '%TEST_LOG_RECEIPT_CC_001%';

  delete from logistica.stock_movements
  where company_id = v_company_id
    and reference_number = 'TEST_LOG_RECEIPT_CC_001';

  delete from logistica.stock_balances b
  using logistica.items i
  where b.company_id = v_company_id
    and i.company_id = v_company_id
    and b.item_id = i.id
    and i.sku in ('TEST_LOG_ITEM_CONS_CC_001', 'TEST_LOG_ITEM_TOOL_CC_001')
    and b.cost_center_id = (select id from public.cost_centers where company_id = v_company_id and code = 'TEST_CC_STOCK_001' limit 1);

  delete from logistica.item_serials
  where company_id = v_company_id
    and serial_number = 'TEST_LOG_SERIAL_CC_001';

  delete from logistica.item_lots
  where company_id = v_company_id
    and lot_code = 'TEST_LOG_LOT_CC_001';

  delete from logistica.items
  where company_id = v_company_id
    and sku in ('TEST_LOG_ITEM_CONS_CC_001', 'TEST_LOG_ITEM_TOOL_CC_001');

  delete from logistica.item_categories
  where company_id = v_company_id
    and name = 'TEST_LOG_CAT_CC_001';

  delete from logistica.locations
  where company_id = v_company_id
    and code = 'TEST_LOG_LOC_CC_001';

  delete from logistica.warehouses
  where company_id = v_company_id
    and code = 'TEST_LOG_BOD_CC_001';

  delete from public.cost_centers
  where company_id = v_company_id
    and code = 'TEST_CC_STOCK_001';

  delete from public.workers
  where company_id = v_company_id
    and tax_id = 'TEST_SHARED_WORKER_CC_001';

  delete from public.contractors
  where company_id = v_company_id
    and tax_id = 'TEST_SHARED_CONTRACTOR_CC_001';

  delete from public.projects
  where company_id = v_company_id
    and code in ('TEST_SHARED_PROJECT_CC_001');
end;
$$;
