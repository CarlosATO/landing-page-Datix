-- Prueba temporal de logistica.create/update/deactivate/activate_warehouse.
-- Reemplazar el company_id placeholder antes de ejecutar.

do $$
declare
  v_company_id uuid := '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b';
  v_user_id uuid;
  v_created jsonb;
  v_updated jsonb;
  v_deactivated jsonb;
  v_activated jsonb;
  v_warehouse_id uuid;
begin
  delete from logistica.warehouses
  where company_id = v_company_id
    and code like 'TEST_LOG_WH_%';

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

  select logistica.create_warehouse(jsonb_build_object(
    'company_id', v_company_id,
    'code', 'TEST_LOG_WH_001',
    'name', 'TEST_LOG_WH_001',
    'description', 'Bodega temporal para prueba de RPCs',
    'warehouse_type', 'main',
    'is_active', true
  )) into v_created;

  v_warehouse_id := (v_created->>'warehouse_id')::uuid;

  select logistica.update_warehouse(jsonb_build_object(
    'warehouse_id', v_warehouse_id,
    'company_id', v_company_id,
    'code', 'TEST_LOG_WH_001',
    'name', 'TEST_LOG_WH_001 EDITADA',
    'description', 'Bodega temporal editada',
    'warehouse_type', 'project',
    'is_active', true
  )) into v_updated;

  select logistica.deactivate_warehouse(jsonb_build_object(
    'warehouse_id', v_warehouse_id,
    'company_id', v_company_id
  )) into v_deactivated;

  select logistica.activate_warehouse(jsonb_build_object(
    'warehouse_id', v_warehouse_id,
    'company_id', v_company_id
  )) into v_activated;

  raise notice 'create=%', v_created;
  raise notice 'update=%', v_updated;
  raise notice 'deactivate=%', v_deactivated;
  raise notice 'activate=%', v_activated;
end;
$$;
