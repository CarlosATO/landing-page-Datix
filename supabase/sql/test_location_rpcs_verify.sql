-- Verificación temporal de public/logistica.list/update/deactivate_location.

do $$
declare
  v_company_id uuid := '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b';
  v_user_id uuid;
  v_warehouse_id uuid;
  v_stock_location_id uuid;
  v_empty_location_id uuid;
  v_list_result jsonb;
  v_update_result jsonb;
  v_deactivate_result jsonb;
  v_bulk_result jsonb;
  v_duplicate_ok boolean := false;
  v_stock_block_ok boolean := false;
  v_audit_created integer;
  v_audit_updated integer;
  v_audit_deactivated integer;
begin
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

  select id into v_warehouse_id
  from logistica.warehouses
  where company_id = v_company_id and code = 'TEST_LOC_WH_001';

  select id into v_stock_location_id
  from logistica.locations
  where company_id = v_company_id and code = 'STOCK-A';

  select id into v_empty_location_id
  from logistica.locations
  where company_id = v_company_id and code = 'PATIO-A';

  select public.list_locations(jsonb_build_object(
    'company_id', v_company_id,
    'warehouse_id', v_warehouse_id,
    'include_inactive', true,
    'search', null
  )) into v_list_result;

  if coalesce((v_list_result->>'success')::boolean, false) is distinct from true then
    raise exception 'list_locations no retornó success=true';
  end if;

  if jsonb_array_length(coalesce(v_list_result->'locations', '[]'::jsonb)) < 6 then
    raise exception 'list_locations no devolvió las ubicaciones esperadas';
  end if;

  if not exists (
    select 1
    from jsonb_array_elements(coalesce(v_list_result->'locations', '[]'::jsonb)) l
    where l->>'code' = 'A-C01-N01'
      and l->>'aisle_code' = 'A'
      and coalesce((l->>'column_number')::int, 0) = 1
      and coalesce((l->>'level_number')::int, 0) = 1
  ) then
    raise exception 'list_locations no devolvió metadata estructurada esperada';
  end if;

  select public.update_location(jsonb_build_object(
    'location_id', (select id from logistica.locations where company_id = v_company_id and code = 'A-C01-N02'),
    'company_id', v_company_id,
    'warehouse_id', v_warehouse_id,
    'code', 'A-C01-N02',
    'name', 'A-C01-N02 EDITADA',
    'description', 'Ubicación temporal editada',
    'location_type', 'zone',
    'aisle_code', 'A',
    'column_number', 1,
    'level_number', 2,
    'is_active', true
  )) into v_update_result;

  if coalesce(v_update_result->>'success', 'false') <> 'true' then
    raise exception 'update_location no retornó success=true';
  end if;

  begin
    perform public.create_location(jsonb_build_object(
      'company_id', v_company_id,
      'warehouse_id', v_warehouse_id,
      'code', 'PATIO-A',
      'name', 'DUPLICADA',
      'description', 'Duplicado esperado',
      'location_type', 'rack',
      'is_active', true
    ));
  exception when others then
    if position('Ya existe una ubicación con ese código en esa bodega' in sqlerrm) > 0 then
      v_duplicate_ok := true;
    else
      raise;
    end if;
  end;

  if not v_duplicate_ok then
    raise exception 'create_location no bloqueó el duplicado';
  end if;

  begin
    select public.deactivate_location(v_stock_location_id) into v_deactivate_result;
    raise exception 'deactivate_location debía bloquearse por stock';
  exception when others then
    if position('stock disponible' in sqlerrm) > 0 then
      v_stock_block_ok := true;
    else
      raise;
    end if;
  end;

  if not v_stock_block_ok then
    raise exception 'No se detectó bloqueo por stock disponible';
  end if;

  select public.deactivate_location(v_empty_location_id) into v_deactivate_result;

  if coalesce(v_deactivate_result->>'success', 'false') <> 'true' then
    raise exception 'deactivate_location no retornó success=true';
  end if;

  if coalesce((v_deactivate_result->'location'->>'is_active')::boolean, true) is distinct from false then
    raise exception 'deactivate_location no desactivó la ubicación';
  end if;

  select public.create_locations_bulk(jsonb_build_object(
    'company_id', v_company_id,
    'warehouse_id', v_warehouse_id,
    'aisle_code', 'B',
    'column_start', 1,
    'column_end', 2,
    'level_start', 1,
    'level_end', 2,
    'column_pad', 2,
    'level_pad', 2,
    'location_type', 'rack',
    'description', 'Ubicaciones bulk de prueba',
    'is_active', true,
    'strict_mode', true
  )) into v_bulk_result;

  if coalesce((v_bulk_result->>'success')::boolean, false) is distinct from true then
    raise exception 'create_locations_bulk no retornó success=true';
  end if;

  if coalesce((v_bulk_result->>'count')::int, 0) <> 4 then
    raise exception 'create_locations_bulk no devolvió el conteo esperado';
  end if;

  if not exists (
    select 1
    from jsonb_array_elements(coalesce(v_bulk_result->'locations', '[]'::jsonb)) l
    where l->>'code' = 'B-C01-N01'
      and l->>'aisle_code' = 'B'
      and coalesce((l->>'column_number')::int, 0) = 1
      and coalesce((l->>'level_number')::int, 0) = 1
  ) then
    raise exception 'create_locations_bulk no devolvió metadata estructurada esperada';
  end if;

  select count(*)::int into v_audit_created
  from public.audit_log
  where company_id = v_company_id
    and action = 'LOCATION_CREATED'
    and coalesce(new_data->>'code', old_data->>'code', '') in ('STOCK-A', 'PATIO-A', 'A-C01-N01', 'A-C01-N02', 'A-C02-N01', 'A-C02-N02');

  select count(*)::int into v_audit_updated
  from public.audit_log
  where company_id = v_company_id
    and action = 'LOCATION_UPDATED'
    and coalesce(new_data->>'code', old_data->>'code', '') = 'A-C01-N02';

  select count(*)::int into v_audit_deactivated
  from public.audit_log
  where company_id = v_company_id
    and action = 'LOCATION_DEACTIVATED'
    and coalesce(new_data->>'code', old_data->>'code', '') = 'PATIO-A';

  if not exists (
    select 1
    from public.audit_log
    where company_id = v_company_id
      and action = 'LOCATION_BULK_CREATED'
      and coalesce((new_data->>'count'), old_data->>'count') = '4'
  ) then
    raise exception 'No se registró LOCATION_BULK_CREATED';
  end if;

  if v_audit_created < 2 then
    raise exception 'No se registraron los eventos LOCATION_CREATED esperados';
  end if;

  if v_audit_updated < 1 then
    raise exception 'No se registró LOCATION_UPDATED';
  end if;

  if v_audit_deactivated < 1 then
    raise exception 'No se registró LOCATION_DEACTIVATED';
  end if;

  raise notice 'list=%', v_list_result;
  raise notice 'update=%', v_update_result;
  raise notice 'deactivate=%', v_deactivate_result;
  raise notice 'bulk=%', v_bulk_result;
end;
$$;
