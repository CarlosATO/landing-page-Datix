-- DEV seed persistente para probar la UI de Logistica.
-- Idempotente. No borra datos. No incluye cleanup.
-- Company objetivo: 48e5e15d-8e6a-4e64-9610-70f2fb0bc53b.

do $$
declare
  v_company_id uuid := '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b';
  v_user_id uuid;
  v_project_demo_id uuid;
  v_stock_cc_id uuid;
  v_office_cc_id uuid;
  v_project_cc_id uuid;
  v_warehouse_id uuid;
  v_materials_category_id uuid;
  v_tools_category_id uuid;
  v_has_default_cost_center boolean := false;
  v_stock_general_is_default boolean := false;
  v_cement_catalog_id uuid;
  v_drill_catalog_id uuid;
  v_gloves_catalog_id uuid;
begin
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
    raise exception 'No se encontró un usuario válido para la empresa objetivo';
  end if;

  perform set_config('request.jwt.claim.sub', v_user_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  select exists (
    select 1
    from public.cost_centers cc
    where cc.company_id = v_company_id
      and coalesce(cc.is_default, false) = true
  ) into v_has_default_cost_center;

  v_stock_general_is_default := not v_has_default_cost_center;

  insert into public.projects (
    company_id,
    code,
    name,
    description,
    status,
    start_date,
    expected_end_date,
    budget_amount,
    address,
    city,
    region,
    responsible_user_id,
    metadata,
    is_active,
    created_by,
    updated_by
  ) values (
    v_company_id,
    'DEV_PROYECTO_DEMO_001',
    'PROYECTO DEMO',
    'Proyecto semilla para el centro de costo demo.',
    'active',
    current_date,
    current_date + 90,
    0,
    'N/A',
    'N/A',
    'N/A',
    v_user_id,
    jsonb_build_object('seed', 'dev_logistica_operational_minimum'),
    true,
    v_user_id,
    v_user_id
  ) on conflict (company_id, code)
  do update set
    name = excluded.name,
    description = excluded.description,
    status = excluded.status,
    start_date = excluded.start_date,
    expected_end_date = excluded.expected_end_date,
    budget_amount = excluded.budget_amount,
    address = excluded.address,
    city = excluded.city,
    region = excluded.region,
    responsible_user_id = excluded.responsible_user_id,
    metadata = excluded.metadata,
    is_active = excluded.is_active,
    updated_by = excluded.updated_by,
    updated_at = now()
  returning id into v_project_demo_id;

  insert into public.cost_centers (
    company_id,
    code,
    name,
    description,
    cost_center_type,
    project_id,
    is_default,
    is_active,
    created_by,
    updated_by
  ) values
    (v_company_id, 'STOCK GENERAL', 'STOCK GENERAL', 'Centro de costo para bodega central y stock común.', 'warehouse', null, v_stock_general_is_default, true, v_user_id, v_user_id),
    (v_company_id, 'OFICINA CENTRAL', 'OFICINA CENTRAL', 'Centro de costo para gastos administrativos.', 'office', null, false, true, v_user_id, v_user_id),
    (v_company_id, 'PROYECTO DEMO', 'PROYECTO DEMO', 'Centro de costo asociado al proyecto demo.', 'project', v_project_demo_id, false, true, v_user_id, v_user_id)
  on conflict (company_id, code)
  do update set
    name = excluded.name,
    description = excluded.description,
    cost_center_type = excluded.cost_center_type,
    project_id = excluded.project_id,
    is_default = excluded.is_default,
    is_active = excluded.is_active,
    updated_by = excluded.updated_by,
    updated_at = now();

  select id into v_stock_cc_id
  from public.cost_centers
  where company_id = v_company_id and code = 'STOCK GENERAL'
  limit 1;

  select id into v_office_cc_id
  from public.cost_centers
  where company_id = v_company_id and code = 'OFICINA CENTRAL'
  limit 1;

  select id into v_project_cc_id
  from public.cost_centers
  where company_id = v_company_id and code = 'PROYECTO DEMO'
  limit 1;

  insert into logistica.warehouses (
    company_id,
    code,
    name,
    description,
    warehouse_type,
    is_active
  ) values (
    v_company_id,
    'BODE-01',
    'Bodega Central',
    'Bodega principal para operación logística y recepción manual.',
    'main',
    true
  ) on conflict (company_id, code)
  do update set
    name = excluded.name,
    description = excluded.description,
    warehouse_type = excluded.warehouse_type,
    is_active = excluded.is_active;

  select id into v_warehouse_id
  from logistica.warehouses
  where company_id = v_company_id and code = 'BODE-01'
  limit 1;

  insert into logistica.locations (
    company_id,
    warehouse_id,
    code,
    name,
    description,
    location_type,
    aisle_code,
    column_number,
    level_number,
    division_code,
    is_active
  ) values
    (v_company_id, v_warehouse_id, 'A-C01-N01-D01', 'A-C01-N01-D01', 'Ubicación estructurada demo 1', 'rack', 'A', 1, 1, 'D01', true),
    (v_company_id, v_warehouse_id, 'A-C01-N01-D02', 'A-C01-N01-D02', 'Ubicación estructurada demo 2', 'rack', 'A', 1, 1, 'D02', true),
    (v_company_id, v_warehouse_id, 'A-C01-N02-D01', 'A-C01-N02-D01', 'Ubicación estructurada demo 3', 'rack', 'A', 1, 2, 'D01', true),
    (v_company_id, v_warehouse_id, 'PATIO-A', 'PATIO-A', 'Patio o zona exterior demo', 'zone', 'PATIO', null, null, null, true)
  on conflict (company_id, warehouse_id, code)
  do update set
    name = excluded.name,
    description = excluded.description,
    location_type = excluded.location_type,
    aisle_code = excluded.aisle_code,
    column_number = excluded.column_number,
    level_number = excluded.level_number,
    division_code = excluded.division_code,
    is_active = excluded.is_active;

  insert into public.catalog_categories (
    company_id,
    code,
    name,
    description,
    category_type,
    is_active,
    metadata,
    created_by,
    updated_by
  ) values
    (v_company_id, 'MATERIALES', 'MATERIALES', 'Categoría de materiales físicos de consumo.', 'material', true, jsonb_build_object('seed', 'dev_logistica_operational_minimum'), v_user_id, v_user_id),
    (v_company_id, 'HERRAMIENTAS', 'HERRAMIENTAS', 'Categoría de herramientas devolutivas.', 'tool', true, jsonb_build_object('seed', 'dev_logistica_operational_minimum'), v_user_id, v_user_id)
  on conflict (company_id, code)
  do update set
    name = excluded.name,
    description = excluded.description,
    category_type = excluded.category_type,
    is_active = excluded.is_active,
    metadata = excluded.metadata,
    updated_by = excluded.updated_by,
    updated_at = now();

  select id into v_materials_category_id
  from public.catalog_categories
  where company_id = v_company_id and code = 'MATERIALES'
  limit 1;

  select id into v_tools_category_id
  from public.catalog_categories
  where company_id = v_company_id and code = 'HERRAMIENTAS'
  limit 1;

  insert into public.catalog_items (
    company_id,
    category_id,
    sku,
    name,
    description,
    item_kind,
    unit,
    is_stockable,
    is_purchasable,
    is_service,
    is_expense,
    is_returnable,
    tracks_lot,
    tracks_serial,
    tracks_expiration,
    default_tax_rate,
    default_cost,
    metadata,
    is_active,
    created_by,
    updated_by
  ) values
    (v_company_id, v_materials_category_id, 'MAT-CEMENTO-25KG', 'Cemento 25 kg', 'Cemento 25 kg', 'physical', 'SACO', true, true, false, false, false, true, false, false, 0.1900, 6500.0000, jsonb_build_object('seed', 'dev_logistica_operational_minimum'), true, v_user_id, v_user_id),
    (v_company_id, v_tools_category_id, 'HER-TALADRO-BOSCH', 'Taladro Bosch', 'Taladro Bosch', 'tool', 'UN', true, true, false, false, true, false, true, false, 0.1900, 89000.0000, jsonb_build_object('seed', 'dev_logistica_operational_minimum'), true, v_user_id, v_user_id),
    (v_company_id, v_materials_category_id, 'MAT-GUANTES', 'Guantes de seguridad', 'Guantes de seguridad', 'physical', 'PAR', true, true, false, false, false, false, false, false, 0.1900, 1200.0000, jsonb_build_object('seed', 'dev_logistica_operational_minimum'), true, v_user_id, v_user_id)
  on conflict (company_id, sku)
  do update set
    category_id = excluded.category_id,
    name = excluded.name,
    description = excluded.description,
    item_kind = excluded.item_kind,
    unit = excluded.unit,
    is_stockable = excluded.is_stockable,
    is_purchasable = excluded.is_purchasable,
    is_service = excluded.is_service,
    is_expense = excluded.is_expense,
    is_returnable = excluded.is_returnable,
    tracks_lot = excluded.tracks_lot,
    tracks_serial = excluded.tracks_serial,
    tracks_expiration = excluded.tracks_expiration,
    default_tax_rate = excluded.default_tax_rate,
    default_cost = excluded.default_cost,
    metadata = excluded.metadata,
    is_active = excluded.is_active,
    updated_by = excluded.updated_by,
    updated_at = now();

  -- Reobtener cada catálogo por seguridad/idempotencia.
  select id into v_cement_catalog_id from public.catalog_items where company_id = v_company_id and sku = 'MAT-CEMENTO-25KG' limit 1;
  select id into v_drill_catalog_id from public.catalog_items where company_id = v_company_id and sku = 'HER-TALADRO-BOSCH' limit 1;
  select id into v_gloves_catalog_id from public.catalog_items where company_id = v_company_id and sku = 'MAT-GUANTES' limit 1;

  insert into logistica.items (
    company_id,
    sku,
    name,
    description,
    item_type,
    category_id,
    unit,
    tracks_serial,
    tracks_lot,
    tracks_expiration,
    is_returnable,
    min_stock,
    is_active,
    catalog_item_id,
    created_by,
    updated_by
  ) values
    (v_company_id, 'MAT-CEMENTO-25KG', 'Cemento 25 kg', 'Cemento 25 kg', 'consumable', null, 'SACO', false, true, false, false, 0, true, v_cement_catalog_id, v_user_id, v_user_id),
    (v_company_id, 'HER-TALADRO-BOSCH', 'Taladro Bosch', 'Taladro Bosch', 'tool', null, 'UN', true, false, false, true, 0, true, v_drill_catalog_id, v_user_id, v_user_id),
    (v_company_id, 'MAT-GUANTES', 'Guantes de seguridad', 'Guantes de seguridad', 'consumable', null, 'PAR', false, false, false, false, 0, true, v_gloves_catalog_id, v_user_id, v_user_id)
  on conflict (company_id, sku)
  do update set
    name = excluded.name,
    description = excluded.description,
    item_type = excluded.item_type,
    category_id = excluded.category_id,
    unit = excluded.unit,
    tracks_serial = excluded.tracks_serial,
    tracks_lot = excluded.tracks_lot,
    tracks_expiration = excluded.tracks_expiration,
    is_returnable = excluded.is_returnable,
    min_stock = excluded.min_stock,
    is_active = excluded.is_active,
    catalog_item_id = excluded.catalog_item_id,
    updated_by = excluded.updated_by,
    updated_at = now();

  raise notice 'DEV seed listo para company_id=%', v_company_id;
end;
$$;
