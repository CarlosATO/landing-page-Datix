-- Prueba temporal de public.create_manual_receipt con cost_center_id obligatorio.

do $$
declare
  v_company_id uuid := '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b';
  v_user_id uuid;
  v_project_id uuid;
  v_contractor_id uuid;
  v_worker_id uuid;
  v_category_id uuid;
  v_warehouse_id uuid;
  v_location_id uuid;
  v_cost_center_id uuid;
  v_consumable_item_id uuid;
  v_tool_item_id uuid;
  v_result jsonb;
begin
  delete from public.audit_log
  where company_id = v_company_id
    and coalesce(new_data::text, old_data::text, '') like '%TEST_LOG_RECEIPT_CC_%';

  delete from logistica.audit_log
  where company_id = v_company_id
    and coalesce(new_data::text, old_data::text, '') like '%TEST_LOG_RECEIPT_CC_%';

  delete from logistica.stock_movements
  where company_id = v_company_id
    and reference_number = 'TEST_LOG_RECEIPT_CC_001';

  delete from logistica.stock_balances b
  using logistica.items i
  where b.company_id = v_company_id
    and i.company_id = v_company_id
    and b.item_id = i.id
    and i.sku in ('TEST_LOG_ITEM_CONS_CC_001', 'TEST_LOG_ITEM_TOOL_CC_001');

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

  select cu.user_id
    into v_user_id
  from public.company_users cu
  where cu.company_id = v_company_id
  order by case when upper(coalesce(cu.role, '')) = 'OWNER' then 0 else 1 end, cu.created_at asc
  limit 1;

  if v_user_id is null then
    raise exception 'No se encontró un usuario para la empresa de prueba';
  end if;

  select p.id
    into v_project_id
  from public.projects p
  where p.company_id = v_company_id
  order by p.created_at asc
  limit 1;

  if v_project_id is null then
    insert into public.projects (
      company_id, code, name, description, status, start_date, expected_end_date, budget_amount, address, city, region, responsible_user_id, metadata, is_active, created_by, updated_by
    ) values (
      v_company_id, 'TEST_SHARED_PROJECT_CC_001', 'TEST_SHARED_PROJECT_CC_001', 'Proyecto temporal para prueba de recepción', 'active', current_date, current_date + 30, 50000.00, 'TEST ADDRESS', 'TEST CITY', 'TEST REGION', v_user_id, jsonb_build_object('test', true), true, v_user_id, v_user_id
    ) returning id into v_project_id;
  end if;

  insert into public.contractors (
    company_id, tax_id, business_name, trade_name, contact_name, phone, email, address, city, region, status, metadata, is_active, created_by, updated_by
  ) values (
    v_company_id, 'TEST_SHARED_CONTRACTOR_CC_001', 'TEST_SHARED_CONTRACTOR_CC_001', 'TEST_SHARED_CONTRACTOR_CC_001', 'TEST CONTACTOR', '+56900000011', 'test_contractor@example.com', 'TEST CONTRACTOR ADDRESS', 'TEST CITY', 'TEST REGION', 'active', jsonb_build_object('test', true), true, v_user_id, v_user_id
  ) on conflict (company_id, tax_id)
  do update set business_name = excluded.business_name, trade_name = excluded.trade_name, contact_name = excluded.contact_name, phone = excluded.phone, email = excluded.email, address = excluded.address, city = excluded.city, region = excluded.region, status = excluded.status, is_active = excluded.is_active, updated_by = excluded.updated_by
  returning id into v_contractor_id;

  insert into public.workers (
    company_id, contractor_id, tax_id, first_name, last_name, job_title, phone, email, status, metadata, is_active, created_by, updated_by
  ) values (
    v_company_id, v_contractor_id, 'TEST_SHARED_WORKER_CC_001', 'TEST', 'WORKER', 'Supervisor', '+56900000012', 'test_worker@example.com', 'active', jsonb_build_object('test', true), true, v_user_id, v_user_id
  ) on conflict (company_id, tax_id)
  do update set contractor_id = excluded.contractor_id, first_name = excluded.first_name, last_name = excluded.last_name, job_title = excluded.job_title, phone = excluded.phone, email = excluded.email, status = excluded.status, is_active = excluded.is_active, updated_by = excluded.updated_by
  returning id into v_worker_id;

  insert into public.cost_centers (
    company_id, code, name, description, cost_center_type, project_id, is_default, is_active, created_by, updated_by
  ) values (
    v_company_id, 'TEST_CC_STOCK_001', 'STOCK GENERAL', 'Centro de costo para prueba de recepción', 'warehouse', null, false, true, v_user_id, v_user_id
  ) on conflict (company_id, code)
  do update set name = excluded.name, description = excluded.description, cost_center_type = excluded.cost_center_type, project_id = excluded.project_id, is_default = excluded.is_default, is_active = excluded.is_active, updated_by = excluded.updated_by, updated_at = now()
  returning id into v_cost_center_id;

  select id into v_warehouse_id
  from logistica.warehouses
  where company_id = v_company_id and code = 'TEST_LOG_BOD_CC_001'
  limit 1;

  insert into logistica.warehouses (
    company_id, code, name, description, warehouse_type, is_active
  ) values (
    v_company_id, 'TEST_LOG_BOD_CC_001', 'TEST_LOG_BOD_CC_001', 'Bodega temporal para prueba de recepción', 'main', true
  ) on conflict (company_id, code)
  do update set name = excluded.name, description = excluded.description, warehouse_type = excluded.warehouse_type, is_active = excluded.is_active;

  select id into v_warehouse_id
  from logistica.warehouses
  where company_id = v_company_id and code = 'TEST_LOG_BOD_CC_001'
  limit 1;

  insert into logistica.locations (
    company_id, warehouse_id, code, name, description, location_type, is_active
  ) values (
    v_company_id, v_warehouse_id, 'TEST_LOG_LOC_CC_001', 'TEST_LOG_LOC_CC_001', 'Ubicación temporal para prueba de recepción', 'rack', true
  ) on conflict (company_id, warehouse_id, code)
  do update set name = excluded.name, description = excluded.description, location_type = excluded.location_type, is_active = excluded.is_active;

  select id into v_location_id
  from logistica.locations
  where company_id = v_company_id and warehouse_id = v_warehouse_id and code = 'TEST_LOG_LOC_CC_001'
  limit 1;

  insert into logistica.item_categories (company_id, name, description, is_active)
  values (v_company_id, 'TEST_LOG_CAT_CC_001', 'Categoria temporal para prueba de recepción', true)
  on conflict (company_id, name)
  do update set description = excluded.description, is_active = excluded.is_active
  returning id into v_category_id;

  if v_category_id is null then
    select id into v_category_id
    from logistica.item_categories
    where company_id = v_company_id and name = 'TEST_LOG_CAT_CC_001'
    limit 1;
  end if;

  insert into logistica.items (
    company_id, sku, name, description, item_type, category_id, unit, tracks_serial, tracks_lot, tracks_expiration, is_returnable, min_stock, is_active
  ) values (
    v_company_id, 'TEST_LOG_ITEM_CONS_CC_001', 'TEST_LOG_ITEM_CONS_CC_001', 'Consumible temporal para prueba de recepción', 'consumable', v_category_id, 'UN', false, true, false, false, 0, true
  ) on conflict (company_id, sku)
  do update set name = excluded.name, description = excluded.description, item_type = excluded.item_type, category_id = excluded.category_id, unit = excluded.unit, tracks_serial = excluded.tracks_serial, tracks_lot = excluded.tracks_lot, tracks_expiration = excluded.tracks_expiration, is_returnable = excluded.is_returnable, min_stock = excluded.min_stock, is_active = excluded.is_active;

  insert into logistica.items (
    company_id, sku, name, description, item_type, category_id, unit, tracks_serial, tracks_lot, tracks_expiration, is_returnable, min_stock, is_active
  ) values (
    v_company_id, 'TEST_LOG_ITEM_TOOL_CC_001', 'TEST_LOG_ITEM_TOOL_CC_001', 'Herramienta serializada temporal para prueba de recepción', 'tool', v_category_id, 'UN', true, false, false, true, 0, true
  ) on conflict (company_id, sku)
  do update set name = excluded.name, description = excluded.description, item_type = excluded.item_type, category_id = excluded.category_id, unit = excluded.unit, tracks_serial = excluded.tracks_serial, tracks_lot = excluded.tracks_lot, tracks_expiration = excluded.tracks_expiration, is_returnable = excluded.is_returnable, min_stock = excluded.min_stock, is_active = excluded.is_active;

  select id into v_consumable_item_id
  from logistica.items
  where company_id = v_company_id and sku = 'TEST_LOG_ITEM_CONS_CC_001'
  limit 1;

  select id into v_tool_item_id
  from logistica.items
  where company_id = v_company_id and sku = 'TEST_LOG_ITEM_TOOL_CC_001'
  limit 1;

  if v_warehouse_id is null or v_location_id is null or v_cost_center_id is null or v_consumable_item_id is null or v_tool_item_id is null then
    raise exception 'No fue posible preparar los fixtures de la prueba';
  end if;

  perform set_config('request.jwt.claim.sub', v_user_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  select public.create_manual_receipt(
    jsonb_build_object(
      'company_id', v_company_id,
      'warehouse_id', v_warehouse_id,
      'location_id', v_location_id,
      'cost_center_id', v_cost_center_id,
      'reference_number', 'TEST_LOG_RECEIPT_CC_001',
      'notes', 'Recepción temporal de prueba con centro de costo',
      'items', jsonb_build_array(
        jsonb_build_object(
          'item_id', v_consumable_item_id,
          'quantity', 7,
          'unit_cost', 125.50,
          'lot_code', 'TEST_LOG_LOT_CC_001',
          'expiration_date', current_date + 365,
          'serial_number', null,
          'notes', 'Consumible de prueba'
        ),
        jsonb_build_object(
          'item_id', v_tool_item_id,
          'quantity', 1,
          'unit_cost', 300.00,
          'lot_code', null,
          'expiration_date', null,
          'serial_number', 'TEST_LOG_SERIAL_CC_001',
          'notes', 'Herramienta de prueba'
        )
      )
    )
  ) into v_result;

  raise notice 'RPC result: %', v_result;
end;
$$;
