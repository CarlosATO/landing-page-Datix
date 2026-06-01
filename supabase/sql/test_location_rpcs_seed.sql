-- Seed temporal para probar RPCs de ubicaciones Logística.
-- Reemplazar el company_id placeholder antes de ejecutar.

do $$
declare
  v_company_id uuid := '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b';
  v_user_id uuid;
  v_category_id uuid;
  v_item_id uuid;
  v_warehouse_id uuid;
  v_stock_location_id uuid;
  v_empty_location_id uuid;
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
    );

  delete from logistica.locations
  where company_id = v_company_id
    and (
      code in ('STOCK-A', 'PATIO-A')
      or code like 'A-C%'
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

  select candidate.user_id
    into v_user_id
  from (
    select ur.user_id, 0 as priority, ur.created_at
    from public.user_roles ur
    where ur.company_id = v_company_id and upper(coalesce(ur.role_key, '')) = 'OWNER'
    union all
    select ur.user_id, 1 as priority, ur.created_at
    from public.user_roles ur
    where ur.company_id = v_company_id and upper(coalesce(ur.role_key, '')) like 'ADMIN%'
    union all
    select c.created_by, 2 as priority, c.created_at
    from public.companies c
    where c.id = v_company_id and c.created_by is not null
  ) candidate
  order by candidate.priority, candidate.created_at asc nulls last
  limit 1;

  if v_user_id is null then
    raise exception 'No se encontró un usuario válido para la empresa de prueba';
  end if;

  perform set_config('request.jwt.claim.sub', v_user_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  insert into logistica.item_categories (company_id, name, description, is_active)
  values (v_company_id, 'TEST_LOC_CAT_001', 'Categoría temporal ubicaciones', true)
  returning id into v_category_id;

  insert into logistica.items (
    company_id, sku, name, description, item_type, category_id, unit, tracks_serial, tracks_lot, tracks_expiration, is_returnable, min_stock, is_active, created_by, updated_by
  ) values (
    v_company_id, 'TEST_LOC_ITEM_001', 'TEST_LOC_ITEM_001', 'Ítem temporal para stock balance', 'consumable', v_category_id, 'UN', false, false, false, false, 0, true, v_user_id, v_user_id
  ) returning id into v_item_id;

  select (public.create_warehouse(jsonb_build_object(
    'company_id', v_company_id,
    'code', 'TEST_LOC_WH_001',
    'name', 'TEST LOC WH',
    'description', 'Bodega temporal para ubicaciones',
    'warehouse_type', 'main',
    'is_active', true
  ))->>'warehouse_id')::uuid into v_warehouse_id;

  select (public.create_location(jsonb_build_object(
    'company_id', v_company_id,
    'warehouse_id', v_warehouse_id,
    'code', 'STOCK-A',
    'name', 'STOCK-A',
    'description', 'Ubicación temporal con stock',
    'location_type', 'rack',
    'aisle_code', 'A',
    'column_number', 1,
    'is_active', true
  ))->>'location_id')::uuid into v_stock_location_id;

  select (public.create_location(jsonb_build_object(
    'company_id', v_company_id,
    'warehouse_id', v_warehouse_id,
    'code', 'PATIO-A',
    'name', 'PATIO-A',
    'description', 'Ubicación temporal sin stock',
    'location_type', 'zone',
    'aisle_code', 'PATIO',
    'is_active', true
  ))->>'location_id')::uuid into v_empty_location_id;

  insert into logistica.stock_balances (
    company_id, item_id, warehouse_id, location_id, quantity_on_hand, quantity_reserved, average_unit_cost, total_cost
  ) values (
    v_company_id, v_item_id, v_warehouse_id, v_stock_location_id, 6, 0, 100, 600
  );

  raise notice 'seed_stock_location=%', v_stock_location_id;
  raise notice 'seed_empty_location=%', v_empty_location_id;
  raise notice 'seed_location_warehouse=%', v_warehouse_id;
end;
$$;
