-- Prueba temporal del catálogo transversal Datix.
-- Reemplazar el company_id placeholder antes de ejecutar.

do $$
declare
  v_company_id uuid := '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b';
  v_user_id uuid;
  v_material_category_id uuid;
  v_service_category_id uuid;
  v_cemento_catalog_id uuid;
  v_flete_catalog_id uuid;
  v_taladro_catalog_id uuid;
begin
  delete from logistica.items
  where company_id = v_company_id
    and sku in ('TEST_ITEM_CEMENTO', 'TEST_ITEM_FLETE', 'TEST_ITEM_TALADRO');

  delete from public.catalog_items
  where company_id = v_company_id
    and sku in ('TEST_ITEM_CEMENTO', 'TEST_ITEM_FLETE', 'TEST_ITEM_TALADRO');

  delete from public.catalog_categories
  where company_id = v_company_id
    and code in ('TEST_CAT_MATERIAL', 'TEST_CAT_SERVICE');

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
    v_company_id, 'TEST_CAT_MATERIAL', 'TEST_CAT_MATERIAL', 'Categoria temporal de materiales', 'material', true, jsonb_build_object('test', true), v_user_id, v_user_id
  ) returning id into v_material_category_id;

  insert into public.catalog_categories (
    company_id, code, name, description, category_type, is_active, metadata, created_by, updated_by
  ) values (
    v_company_id, 'TEST_CAT_SERVICE', 'TEST_CAT_SERVICE', 'Categoria temporal de servicios', 'service', true, jsonb_build_object('test', true), v_user_id, v_user_id
  ) returning id into v_service_category_id;

  insert into public.catalog_items (
    company_id, category_id, sku, name, description, item_kind, unit, is_stockable, is_purchasable, is_service, is_expense, is_returnable, tracks_lot, tracks_serial, tracks_expiration, default_tax_rate, default_cost, metadata, is_active, created_by, updated_by
  ) values (
    v_company_id, v_material_category_id, 'TEST_ITEM_CEMENTO', 'TEST_ITEM_CEMENTO', 'Item fisico temporal de prueba', 'physical', 'SACO', true, true, false, false, false, true, false, false, 0.1900, 5000.0000, jsonb_build_object('test', true), true, v_user_id, v_user_id
  ) returning id into v_cemento_catalog_id;

  insert into public.catalog_items (
    company_id, category_id, sku, name, description, item_kind, unit, is_stockable, is_purchasable, is_service, is_expense, is_returnable, tracks_lot, tracks_serial, tracks_expiration, default_tax_rate, default_cost, metadata, is_active, created_by, updated_by
  ) values (
    v_company_id, v_service_category_id, 'TEST_ITEM_FLETE', 'TEST_ITEM_FLETE', 'Servicio temporal de prueba', 'service', 'SERV', false, true, true, false, false, false, false, false, 0.0000, 15000.0000, jsonb_build_object('test', true), true, v_user_id, v_user_id
  ) returning id into v_flete_catalog_id;

  insert into public.catalog_items (
    company_id, category_id, sku, name, description, item_kind, unit, is_stockable, is_purchasable, is_service, is_expense, is_returnable, tracks_lot, tracks_serial, tracks_expiration, default_tax_rate, default_cost, metadata, is_active, created_by, updated_by
  ) values (
    v_company_id, v_material_category_id, 'TEST_ITEM_TALADRO', 'TEST_ITEM_TALADRO', 'Herramienta temporal de prueba', 'tool', 'UN', true, true, false, false, true, false, true, false, 0.1900, 35000.0000, jsonb_build_object('test', true), true, v_user_id, v_user_id
  ) returning id into v_taladro_catalog_id;

  insert into logistica.items (
    company_id, sku, name, description, item_type, category_id, unit, tracks_serial, tracks_lot, tracks_expiration, is_returnable, min_stock, is_active, catalog_item_id, created_by, updated_by
  ) values (
    v_company_id, 'TEST_ITEM_CEMENTO', 'TEST_ITEM_CEMENTO', 'Item fisico temporal de prueba', 'consumable', null, 'SACO', false, true, false, false, 0, true, v_cemento_catalog_id, v_user_id, v_user_id
  ) on conflict (company_id, sku)
  do update set catalog_item_id = excluded.catalog_item_id, updated_by = excluded.updated_by, updated_at = now();

  insert into logistica.items (
    company_id, sku, name, description, item_type, category_id, unit, tracks_serial, tracks_lot, tracks_expiration, is_returnable, min_stock, is_active, catalog_item_id, created_by, updated_by
  ) values (
    v_company_id, 'TEST_ITEM_FLETE', 'TEST_ITEM_FLETE', 'Servicio temporal de prueba', 'service', null, 'SERV', false, false, false, false, 0, true, v_flete_catalog_id, v_user_id, v_user_id
  ) on conflict (company_id, sku)
  do update set catalog_item_id = excluded.catalog_item_id, updated_by = excluded.updated_by, updated_at = now();

  insert into logistica.items (
    company_id, sku, name, description, item_type, category_id, unit, tracks_serial, tracks_lot, tracks_expiration, is_returnable, min_stock, is_active, catalog_item_id, created_by, updated_by
  ) values (
    v_company_id, 'TEST_ITEM_TALADRO', 'TEST_ITEM_TALADRO', 'Herramienta temporal de prueba', 'tool', null, 'UN', true, false, false, true, 0, true, v_taladro_catalog_id, v_user_id, v_user_id
  ) on conflict (company_id, sku)
  do update set catalog_item_id = excluded.catalog_item_id, updated_by = excluded.updated_by, updated_at = now();

  raise notice 'seeded catalog ids: %, %, %, %, %', v_material_category_id, v_service_category_id, v_cemento_catalog_id, v_flete_catalog_id, v_taladro_catalog_id;
end;
$$;
