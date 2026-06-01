-- Verificación temporal de logistica.create/update/deactivate_warehouse.

do $$
declare
  v_company_id uuid := '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b';
  v_user_id uuid;
  v_wh_stock_id uuid;
  v_wh_location_id uuid;
  v_wh_ok_id uuid;
  v_update_result jsonb;
  v_deactivate_result jsonb;
  v_duplicate_ok boolean := false;
  v_stock_block_ok boolean := false;
  v_location_block_ok boolean := false;
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

  select id into v_wh_stock_id from logistica.warehouses where company_id = v_company_id and code = 'TEST_WH_STOCK_001';
  select id into v_wh_location_id from logistica.warehouses where company_id = v_company_id and code = 'TEST_WH_LOC_001';
  select id into v_wh_ok_id from logistica.warehouses where company_id = v_company_id and code = 'TEST_WH_OK_001';

  select logistica.update_warehouse(jsonb_build_object(
    'warehouse_id', v_wh_ok_id,
    'company_id', v_company_id,
    'code', 'TEST_WH_OK_001',
    'name', 'TEST WH OK EDITADA',
    'description', 'Bodega temporal editada',
    'warehouse_type', 'external',
    'is_active', true
  )) into v_update_result;

  if coalesce(v_update_result->>'success', 'false') <> 'true' then
    raise exception 'update_warehouse no retornó success=true';
  end if;

  begin
    perform logistica.create_warehouse(jsonb_build_object(
      'company_id', v_company_id,
      'code', 'TEST_WH_OK_001',
      'name', 'DUPLICADA',
      'description', 'Duplicado esperado',
      'warehouse_type', 'main',
      'is_active', true
    ));
  exception when others then
    if position('Ya existe una bodega con ese código' in sqlerrm) > 0 then
      v_duplicate_ok := true;
    else
      raise;
    end if;
  end;

  if not v_duplicate_ok then
    raise exception 'create_warehouse no bloqueó el duplicado';
  end if;

  begin
    select logistica.deactivate_warehouse(v_wh_stock_id) into v_deactivate_result;
    raise exception 'deactivate_warehouse debía bloquearse por stock_balance';
  exception when others then
    if position('stock_balances activos' in sqlerrm) > 0 then
      v_stock_block_ok := true;
    else
      raise;
    end if;
  end;

  if not v_stock_block_ok then
    raise exception 'No se detectó bloqueo por stock';
  end if;

  begin
    select logistica.deactivate_warehouse(v_wh_location_id) into v_deactivate_result;
    raise exception 'deactivate_warehouse debía bloquearse por locations activas';
  exception when others then
    if position('ubicaciones activas asociadas' in sqlerrm) > 0 then
      v_location_block_ok := true;
    else
      raise;
    end if;
  end;

  if not v_location_block_ok then
    raise exception 'No se detectó bloqueo por locations activas';
  end if;

  select logistica.deactivate_warehouse(v_wh_ok_id) into v_deactivate_result;

  if coalesce(v_deactivate_result->>'success', 'false') <> 'true' then
    raise exception 'deactivate_warehouse no retornó success=true';
  end if;

  select count(*)::int into v_audit_created
  from public.audit_log
  where company_id = v_company_id
    and action = 'WAREHOUSE_CREATED'
    and coalesce(new_data->>'code', old_data->>'code', '') in ('TEST_WH_STOCK_001', 'TEST_WH_LOC_001', 'TEST_WH_OK_001');

  select count(*)::int into v_audit_updated
  from public.audit_log
  where company_id = v_company_id
    and action = 'WAREHOUSE_UPDATED'
    and coalesce(new_data->>'code', old_data->>'code', '') = 'TEST_WH_OK_001';

  select count(*)::int into v_audit_deactivated
  from public.audit_log
  where company_id = v_company_id
    and action = 'WAREHOUSE_DEACTIVATED'
    and coalesce(new_data->>'code', old_data->>'code', '') = 'TEST_WH_OK_001';

  if v_audit_created < 3 then
    raise exception 'No se registraron los eventos WAREHOUSE_CREATED esperados';
  end if;

  if v_audit_updated < 1 then
    raise exception 'No se registró WAREHOUSE_UPDATED';
  end if;

  if v_audit_deactivated < 1 then
    raise exception 'No se registró WAREHOUSE_DEACTIVATED';
  end if;

  raise notice 'update=%', v_update_result;
  raise notice 'deactivate=%', v_deactivate_result;
end;
$$;
