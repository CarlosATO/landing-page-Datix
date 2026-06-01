-- Prueba temporal del enlace Logística-Catálogo.
-- Reemplazar el company_id placeholder antes de ejecutar.

do $$
declare
  v_company_id uuid := '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b';
  v_user_id uuid;
  v_material_category_id uuid;
  v_service_category_id uuid;
  v_physical_catalog_id uuid;
  v_service_catalog_id uuid;
  v_tool_catalog_id uuid;
  v_result jsonb;
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

  perform set_config('request.jwt.claim.sub', v_user_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  insert into public.catalog_categories (
    company_id, code, name, description, category_type, is_active, metadata, created_by, updated_by
  ) values (
    v_company_id, 'TEST_CAT_MATERIAL_LINK', 'TEST_CAT_MATERIAL_LINK', 'Categoria material para enlace', 'material', true, jsonb_build_object('test', true), v_user_id, v_user_id
  ) returning id into v_material_category_id;

  insert into public.catalog_categories (
    company_id, code, name, description, category_type, is_active, metadata, created_by, updated_by
  ) values (
    v_company_id, 'TEST_CAT_SERVICE_LINK', 'TEST_CAT_SERVICE_LINK', 'Categoria servicio para enlace', 'service', true, jsonb_build_object('test', true), v_user_id, v_user_id
  ) returning id into v_service_category_id;

  insert into public.catalog_items (
    company_id, category_id, sku, name, description, item_kind, unit, is_stockable, is_purchasable, is_service, is_expense, is_returnable, tracks_lot, tracks_serial, tracks_expiration, default_tax_rate, default_cost, metadata, is_active, created_by, updated_by
  ) values (
    v_company_id, v_material_category_id, 'TEST_CATALOG_CEMENTO', 'TEST_CATALOG_CEMENTO', 'Catálogo fisico para enlace', 'physical', 'SACO', true, true, false, false, false, true, false, false, 0.1900, 5000.0000, jsonb_build_object('test', true), true, v_user_id, v_user_id
  ) returning id into v_physical_catalog_id;

  insert into public.catalog_items (
    company_id, category_id, sku, name, description, item_kind, unit, is_stockable, is_purchasable, is_service, is_expense, is_returnable, tracks_lot, tracks_serial, tracks_expiration, default_tax_rate, default_cost, metadata, is_active, created_by, updated_by
  ) values (
    v_company_id, v_service_category_id, 'TEST_CATALOG_FLETE', 'TEST_CATALOG_FLETE', 'Servicio para probar rechazo', 'service', 'SERV', false, true, true, false, false, false, false, false, 0.0000, 15000.0000, jsonb_build_object('test', true), true, v_user_id, v_user_id
  ) returning id into v_service_catalog_id;

  insert into public.catalog_items (
    company_id, category_id, sku, name, description, item_kind, unit, is_stockable, is_purchasable, is_service, is_expense, is_returnable, tracks_lot, tracks_serial, tracks_expiration, default_tax_rate, default_cost, metadata, is_active, created_by, updated_by
  ) values (
    v_company_id, v_material_category_id, 'TEST_CATALOG_TALADRO', 'TEST_CATALOG_TALADRO', 'Herramienta para enlace', 'tool', 'UN', true, true, false, false, true, false, true, false, 0.1900, 35000.0000, jsonb_build_object('test', true), true, v_user_id, v_user_id
  ) returning id into v_tool_catalog_id;

  select logistica.create_logistica_item_from_catalog(
    jsonb_build_object(
      'company_id', v_company_id,
      'catalog_item_id', v_physical_catalog_id,
      'min_stock', 10,
      'logistics_unit', 'SACO',
      'location_defaults', jsonb_build_object('warehouse_code', 'TEST_LOG_BOD_LINK', 'location_code', 'TEST_LOG_LOC_LINK'),
      'overrides', jsonb_build_object('note', 'snapshot')
    )
  ) into v_result;

  raise notice 'link result: %', v_result;

  begin
    perform logistica.create_logistica_item_from_catalog(
      jsonb_build_object(
        'company_id', v_company_id,
        'catalog_item_id', v_service_catalog_id,
        'min_stock', 0
      )
    );
    raise exception 'service catalog item should have failed';
  exception when others then
    raise notice 'expected failure for service item: %', sqlerrm;
  end;
end;
$$;
