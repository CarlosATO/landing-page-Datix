-- Seed temporal para probar RPCs de bodegas Logística.
-- Reemplazar el company_id placeholder antes de ejecutar.

do $$
declare
  v_company_id uuid := '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b';
  v_user_id uuid;
  v_category_id uuid;
  v_item_id uuid;
  v_wh_stock_id uuid;
  v_wh_location_id uuid;
  v_wh_ok_id uuid;
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
  values (v_company_id, 'TEST_WH_CAT_001', 'Categoría temporal bodegas', true)
  returning id into v_category_id;

  insert into logistica.items (
    company_id, sku, name, description, item_type, category_id, unit, tracks_serial, tracks_lot, tracks_expiration, is_returnable, min_stock, is_active, created_by, updated_by
  ) values (
    v_company_id, 'TEST_WH_ITEM_001', 'TEST_WH_ITEM_001', 'Ítem temporal para stock balance', 'consumable', v_category_id, 'UN', false, false, false, false, 0, true, v_user_id, v_user_id
  ) returning id into v_item_id;

  select (logistica.create_warehouse(jsonb_build_object(
    'company_id', v_company_id,
    'code', 'TEST_WH_STOCK_001',
    'name', 'TEST WH STOCK',
    'description', 'Bodega temporal con stock',
    'warehouse_type', 'main',
    'is_active', true
  ))->>'warehouse_id')::uuid into v_wh_stock_id;

  select (logistica.create_warehouse(jsonb_build_object(
    'company_id', v_company_id,
    'code', 'TEST_WH_LOC_001',
    'name', 'TEST WH LOC',
    'description', 'Bodega temporal con ubicación activa',
    'warehouse_type', 'project',
    'is_active', true
  ))->>'warehouse_id')::uuid into v_wh_location_id;

  select (logistica.create_warehouse(jsonb_build_object(
    'company_id', v_company_id,
    'code', 'TEST_WH_OK_001',
    'name', 'TEST WH OK',
    'description', 'Bodega temporal sin bloqueos',
    'warehouse_type', 'temporary',
    'is_active', true
  ))->>'warehouse_id')::uuid into v_wh_ok_id;

  insert into logistica.locations (
    company_id, warehouse_id, code, name, description, location_type, is_active, created_by, updated_by
  ) values (
    v_company_id, v_wh_location_id, 'TEST_WH_LOC_001', 'TEST_WH_LOC_001', 'Ubicación temporal activa', 'rack', true, v_user_id, v_user_id
  );

  insert into logistica.stock_balances (
    company_id, item_id, warehouse_id, location_id, quantity_on_hand, quantity_reserved, average_unit_cost, total_cost
  ) values (
    v_company_id, v_item_id, v_wh_stock_id, null, 5, 0, 100, 500
  );

  raise notice 'seed_warehouse_stock=%', v_wh_stock_id;
  raise notice 'seed_warehouse_location=%', v_wh_location_id;
  raise notice 'seed_warehouse_ok=%', v_wh_ok_id;
end;
$$;
