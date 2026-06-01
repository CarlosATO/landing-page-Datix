-- Limpieza temporal de la prueba de salida/asignación de stock Logística.

do $$
declare
  v_company_id uuid := '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b';
begin
  delete from public.audit_log
  where company_id = v_company_id
    and coalesce(new_data::text, old_data::text, '') like '%TEST_%';

  delete from logistica.audit_log
  where company_id = v_company_id
    and coalesce(new_data::text, old_data::text, '') like '%TEST_%';

  delete from logistica.stock_movements
  where company_id = v_company_id
    and reference_number in ('TEST_LOG_ISSUE_GEN_001', 'TEST_LOG_ISSUE_CONS_001', 'TEST_LOG_ISSUE_ASSIGN_001', 'TEST_LOG_RECEIPT_ISSUE_001');

  delete from logistica.stock_balances b
  using logistica.items i
  where b.company_id = v_company_id
    and i.company_id = v_company_id
    and b.item_id = i.id
    and i.sku in ('TEST_LOG_ITEM_CONS_001', 'TEST_LOG_ITEM_TOOL_001');

  delete from logistica.item_serials
  where company_id = v_company_id
    and serial_number = 'TEST_LOG_SERIAL_001';

  delete from logistica.item_lots
  where company_id = v_company_id
    and lot_code = 'TEST_LOG_LOT_001';

  delete from logistica.items
  where company_id = v_company_id
    and sku in ('TEST_LOG_ITEM_CONS_001', 'TEST_LOG_ITEM_TOOL_001');

  delete from logistica.item_categories
  where company_id = v_company_id
    and name = 'TEST_LOG_CAT_001';

  delete from logistica.locations
  where company_id = v_company_id
    and code = 'TEST_LOG_LOC_001';

  delete from logistica.warehouses
  where company_id = v_company_id
    and code = 'TEST_LOG_BOD_001';

  delete from public.workers where company_id = v_company_id and tax_id = 'TEST_SHARED_WORKER_001';
  delete from public.contractors where company_id = v_company_id and tax_id = 'TEST_SHARED_CONTRACTOR_001';
  delete from public.projects where company_id = v_company_id and code = 'TEST_SHARED_PROJECT_001';
end;
$$;
