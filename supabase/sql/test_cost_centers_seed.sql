-- Seed temporal de centros de costo para una empresa.
-- Reemplazar el company_id placeholder antes de ejecutar.

do $$
declare
  v_company_id uuid := '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b';
  v_user_id uuid;
  v_existing_project_id uuid;
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
    select cu.user_id, 2 as priority, cu.created_at
    from public.company_users cu
    where cu.company_id = v_company_id and upper(coalesce(cu.role, '')) = 'OWNER'
    union all
    select cu.user_id, 3 as priority, cu.created_at
    from public.company_users cu
    where cu.company_id = v_company_id and upper(coalesce(cu.role, '')) like 'ADMIN%'
    union all
    select c.created_by, 4 as priority, c.created_at
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

  select p.id
    into v_existing_project_id
  from public.projects p
  where p.company_id = v_company_id
  order by p.created_at asc
  limit 1;

  update public.cost_centers
     set is_default = false
   where company_id = v_company_id;

  insert into public.cost_centers (
    company_id, code, name, description, cost_center_type, project_id, is_default, is_active, created_by, updated_by
  ) values
    (v_company_id, 'TEST_CC_OFFICE_001', 'OFICINA CENTRAL', 'Centro de costo para gastos administrativos y oficina', 'office', null, true, true, v_user_id, v_user_id),
    (v_company_id, 'TEST_CC_GENERAL_001', 'OPERACION GENERAL', 'Centro de costo para operación transversal', 'general_operation', null, false, true, v_user_id, v_user_id),
    (v_company_id, 'TEST_CC_STOCK_001', 'STOCK GENERAL', 'Centro de costo para bodega central y stock común', 'warehouse', null, false, true, v_user_id, v_user_id),
    (v_company_id, 'TEST_CC_PROJECT_001', 'PROYECTO DEMO', 'Centro de costo de ejemplo asociado a proyecto', 'project', v_existing_project_id, false, true, v_user_id, v_user_id)
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
end;
$$;
