-- Prueba temporal de logistica.create_stock_issue.
-- Reemplazar el company_id placeholder antes de ejecutar.

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
  v_consumable_item_id uuid;
  v_tool_item_id uuid;
  v_lot_id uuid;
  v_serial_id uuid;
  v_manual_result jsonb;
  v_issue_result jsonb;
  v_consumption_result jsonb;
  v_assignment_result jsonb;
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

  select candidate.user_id
    into v_user_id
  from (
    select cu.user_id, 0 as priority, cu.created_at
    from public.company_users cu
    where cu.company_id = v_company_id and upper(coalesce(cu.role, '')) = 'OWNER'
    union all
    select cu.user_id, 1 as priority, cu.created_at
    from public.company_users cu
    where cu.company_id = v_company_id and upper(coalesce(cu.role, '')) like 'ADMIN%'
    union all
    select cu.user_id, 2 as priority, cu.created_at
    from public.company_users cu
    where cu.company_id = v_company_id
    union all
    select ur.user_id, 3 as priority, ur.created_at
    from public.user_roles ur
    where ur.company_id = v_company_id and upper(coalesce(ur.role_key, '')) = 'OWNER'
    union all
    select ur.user_id, 4 as priority, ur.created_at
    from public.user_roles ur
    where ur.company_id = v_company_id and upper(coalesce(ur.role_key, '')) like 'ADMIN%'
    union all
    select ur.user_id, 5 as priority, ur.created_at
    from public.user_roles ur
    where ur.company_id = v_company_id
    union all
    select c.created_by, 6 as priority, c.created_at
    from public.companies c
    where c.id = v_company_id and c.created_by is not null
  ) candidate
  order by candidate.priority, candidate.created_at asc nulls last
  limit 1;

  if v_user_id is null then
    raise exception 'No se encontró un usuario válido para la empresa de prueba';
  end if;

  insert into public.projects (
    company_id, code, name, description, status, start_date, expected_end_date, budget_amount, address, city, region, responsible_user_id, metadata, is_active, created_by, updated_by
  ) values (
    v_company_id, 'TEST_SHARED_PROJECT_001', 'TEST_SHARED_PROJECT_001', 'Proyecto temporal para prueba de salida de stock', 'active', current_date, current_date + 30, 50000.00, 'TEST SHARED PROJECT ADDRESS', 'TEST CITY', 'TEST REGION', v_user_id, jsonb_build_object('test', true), true, v_user_id, v_user_id
  ) returning id into v_project_id;

  insert into public.contractors (
    company_id, tax_id, business_name, trade_name, contact_name, phone, email, address, city, region, status, metadata, is_active, created_by, updated_by
  ) values (
    v_company_id, 'TEST_SHARED_CONTRACTOR_001', 'TEST_SHARED_CONTRACTOR_001', 'TEST_SHARED_CONTRACTOR_TRADE_001', 'TEST CONTACTOR', '+56900000011', 'test_contractor@example.com', 'TEST CONTRACTOR ADDRESS', 'TEST CITY', 'TEST REGION', 'active', jsonb_build_object('test', true), true, v_user_id, v_user_id
  ) returning id into v_contractor_id;

  insert into public.workers (
    company_id, contractor_id, tax_id, first_name, last_name, job_title, phone, email, status, metadata, is_active, created_by, updated_by
  ) values (
    v_company_id, v_contractor_id, 'TEST_SHARED_WORKER_001', 'TEST', 'WORKER', 'Supervisor', '+56900000012', 'test_worker@example.com', 'active', jsonb_build_object('test', true), true, v_user_id, v_user_id
  ) returning id into v_worker_id;

  insert into logistica.warehouses (
    company_id, code, name, description, warehouse_type, is_active
  ) values (
    v_company_id, 'TEST_LOG_BOD_001', 'TEST_LOG_BOD_001', 'Bodega temporal para prueba de salida de stock', 'main', true
  ) on conflict (company_id, code)
  do update set name = excluded.name, description = excluded.description, warehouse_type = excluded.warehouse_type, is_active = excluded.is_active;

  select id into v_warehouse_id
  from logistica.warehouses
  where company_id = v_company_id and code = 'TEST_LOG_BOD_001'
  limit 1;

  insert into logistica.locations (
    company_id, warehouse_id, code, name, description, location_type, is_active
  ) values (
    v_company_id, v_warehouse_id, 'TEST_LOG_LOC_001', 'TEST_LOG_LOC_001', 'Ubicación temporal para prueba de salida de stock', 'rack', true
  ) on conflict (company_id, warehouse_id, code)
  do update set name = excluded.name, description = excluded.description, location_type = excluded.location_type, is_active = excluded.is_active;

  select id into v_location_id
  from logistica.locations
  where company_id = v_company_id and warehouse_id = v_warehouse_id and code = 'TEST_LOG_LOC_001'
  limit 1;

  insert into logistica.item_categories (company_id, name, description, is_active)
  values (v_company_id, 'TEST_LOG_CAT_001', 'Categoria temporal para prueba de salida de stock', true)
  on conflict (company_id, name)
  do update set description = excluded.description, is_active = excluded.is_active
  returning id into v_category_id;

  if v_category_id is null then
    select id into v_category_id
    from logistica.item_categories
    where company_id = v_company_id and name = 'TEST_LOG_CAT_001'
    limit 1;
  end if;

  insert into logistica.items (
    company_id, sku, name, description, item_type, category_id, unit, tracks_serial, tracks_lot, tracks_expiration, is_returnable, min_stock, is_active
  ) values (
    v_company_id, 'TEST_LOG_ITEM_CONS_001', 'TEST_LOG_ITEM_CONS_001', 'Consumible temporal para prueba de salida de stock', 'consumable', v_category_id, 'UN', false, true, false, false, 0, true
  ) on conflict (company_id, sku)
  do update set name = excluded.name, description = excluded.description, item_type = excluded.item_type, category_id = excluded.category_id, unit = excluded.unit, tracks_serial = excluded.tracks_serial, tracks_lot = excluded.tracks_lot, tracks_expiration = excluded.tracks_expiration, is_returnable = excluded.is_returnable, min_stock = excluded.min_stock, is_active = excluded.is_active;

  insert into logistica.items (
    company_id, sku, name, description, item_type, category_id, unit, tracks_serial, tracks_lot, tracks_expiration, is_returnable, min_stock, is_active
  ) values (
    v_company_id, 'TEST_LOG_ITEM_TOOL_001', 'TEST_LOG_ITEM_TOOL_001', 'Herramienta serializada temporal para prueba de salida de stock', 'tool', v_category_id, 'UN', true, false, false, true, 0, true
  ) on conflict (company_id, sku)
  do update set name = excluded.name, description = excluded.description, item_type = excluded.item_type, category_id = excluded.category_id, unit = excluded.unit, tracks_serial = excluded.tracks_serial, tracks_lot = excluded.tracks_lot, tracks_expiration = excluded.tracks_expiration, is_returnable = excluded.is_returnable, min_stock = excluded.min_stock, is_active = excluded.is_active;

  select id into v_consumable_item_id
  from logistica.items
  where company_id = v_company_id and sku = 'TEST_LOG_ITEM_CONS_001'
  limit 1;

  select id into v_tool_item_id
  from logistica.items
  where company_id = v_company_id and sku = 'TEST_LOG_ITEM_TOOL_001'
  limit 1;

  perform set_config('request.jwt.claim.sub', v_user_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  select logistica.create_manual_receipt(
    jsonb_build_object(
      'company_id', v_company_id,
      'warehouse_id', v_warehouse_id,
      'location_id', v_location_id,
      'reference_number', 'TEST_LOG_RECEIPT_ISSUE_001',
      'notes', 'Recepción temporal para prueba de stock issue',
      'items', jsonb_build_array(
        jsonb_build_object(
          'item_id', v_consumable_item_id,
          'quantity', 10,
          'unit_cost', 100.00,
          'lot_code', 'TEST_LOG_LOT_001',
          'expiration_date', current_date + 365,
          'serial_number', null,
          'notes', 'Ingreso del consumible de prueba'
        ),
        jsonb_build_object(
          'item_id', v_tool_item_id,
          'quantity', 1,
          'unit_cost', 250.00,
          'lot_code', null,
          'expiration_date', null,
          'serial_number', 'TEST_LOG_SERIAL_001',
          'notes', 'Ingreso de la herramienta de prueba'
        )
      )
    )
  ) into v_manual_result;

  select id into v_lot_id
  from logistica.item_lots
  where company_id = v_company_id
    and item_id = v_consumable_item_id
    and lot_code = 'TEST_LOG_LOT_001'
  limit 1;

  select id into v_serial_id
  from logistica.item_serials
  where company_id = v_company_id
    and item_id = v_tool_item_id
    and serial_number = 'TEST_LOG_SERIAL_001'
  limit 1;

  select logistica.create_stock_issue(
    jsonb_build_object(
      'company_id', v_company_id,
      'warehouse_id', v_warehouse_id,
      'location_id', v_location_id,
      'issue_type', 'ISSUE',
      'target_module', 'public',
      'target_entity_type', 'other',
      'target_entity_id', null,
      'reference_number', 'TEST_LOG_ISSUE_GEN_001',
      'notes', 'Salida general temporal',
      'items', jsonb_build_array(
        jsonb_build_object(
          'item_id', v_consumable_item_id,
          'quantity', 1,
          'lot_id', v_lot_id,
          'serial_id', null,
          'notes', 'Salida general de prueba'
        )
      )
    )
  ) into v_issue_result;

  select logistica.create_stock_issue(
    jsonb_build_object(
      'company_id', v_company_id,
      'warehouse_id', v_warehouse_id,
      'location_id', v_location_id,
      'issue_type', 'CONSUMPTION',
      'target_module', 'public',
      'target_entity_type', 'project',
      'target_entity_id', v_project_id,
      'reference_number', 'TEST_LOG_ISSUE_CONS_001',
      'notes', 'Consumo temporal hacia proyecto',
      'items', jsonb_build_array(
        jsonb_build_object(
          'item_id', v_consumable_item_id,
          'quantity', 3,
          'lot_id', v_lot_id,
          'serial_id', null,
          'notes', 'Consumo de prueba hacia proyecto'
        )
      )
    )
  ) into v_consumption_result;

  select logistica.create_stock_issue(
    jsonb_build_object(
      'company_id', v_company_id,
      'warehouse_id', v_warehouse_id,
      'location_id', v_location_id,
      'issue_type', 'ASSIGNMENT',
      'target_module', 'public',
      'target_entity_type', 'worker',
      'target_entity_id', v_worker_id,
      'reference_number', 'TEST_LOG_ISSUE_ASSIGN_001',
      'notes', 'Asignación temporal de herramienta',
      'items', jsonb_build_array(
        jsonb_build_object(
          'item_id', v_tool_item_id,
          'quantity', 1,
          'lot_id', null,
          'serial_id', v_serial_id,
          'notes', 'Asignación de prueba al trabajador'
        )
      )
    )
  ) into v_assignment_result;

  raise notice 'manual receipt result: %', v_manual_result;
  raise notice 'issue result: %', v_issue_result;
  raise notice 'consumption result: %', v_consumption_result;
  raise notice 'assignment result: %', v_assignment_result;
end;
$$;
