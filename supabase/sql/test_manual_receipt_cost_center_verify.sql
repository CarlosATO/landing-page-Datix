-- Verificación temporal de public.create_manual_receipt con cost_center_id.

do $$
declare
  v_company_id uuid := '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b';
  v_movements integer;
  v_balances integer;
  v_serial_status text;
begin
  select count(*)::int into v_movements
  from logistica.stock_movements
  where company_id = v_company_id
    and reference_number = 'TEST_LOG_RECEIPT_CC_001'
    and cost_center_id = (select id from public.cost_centers where company_id = v_company_id and code = 'TEST_CC_STOCK_001' limit 1);

  if coalesce(v_movements, 0) <> 2 then
    raise exception 'Se esperaban 2 movimientos y llegaron %', coalesce(v_movements, 0);
  end if;

  select count(*)::int into v_balances
  from logistica.stock_balances b
  join logistica.items i on i.id = b.item_id
  where b.company_id = v_company_id
    and b.cost_center_id = (select id from public.cost_centers where company_id = v_company_id and code = 'TEST_CC_STOCK_001' limit 1)
    and i.sku in ('TEST_LOG_ITEM_CONS_CC_001', 'TEST_LOG_ITEM_TOOL_CC_001');

  if coalesce(v_balances, 0) <> 2 then
    raise exception 'Se esperaban 2 saldos y llegaron %', coalesce(v_balances, 0);
  end if;

  select status into v_serial_status
  from logistica.item_serials
  where company_id = v_company_id
    and serial_number = 'TEST_LOG_SERIAL_CC_001';

  if coalesce(v_serial_status, '') <> 'available' then
    raise exception 'El serial no quedó disponible';
  end if;

  raise notice 'manual receipt with cost center verified successfully';
end;
$$;
