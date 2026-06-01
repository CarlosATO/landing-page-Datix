create or replace function public.create_cost_center(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_code text;
  v_name text;
  v_description text;
  v_cost_center_type text;
  v_project_id uuid;
  v_is_default boolean;
  v_is_active boolean := true;
  v_cost_center_id uuid;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_code := btrim(coalesce(p_payload->>'code', ''));
  v_name := btrim(coalesce(p_payload->>'name', ''));
  v_description := nullif(btrim(coalesce(p_payload->>'description', '')), '');
  v_cost_center_type := lower(btrim(coalesce(p_payload->>'cost_center_type', '')));
  v_project_id := nullif(btrim(coalesce(p_payload->>'project_id', '')), '')::uuid;
  v_is_default := coalesce((p_payload->>'is_default')::boolean, false);
  v_is_active := coalesce((p_payload->>'is_active')::boolean, true);

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if v_code = '' then
    raise exception 'code es obligatorio';
  end if;

  if v_name = '' then
    raise exception 'name es obligatorio';
  end if;

  if v_cost_center_type not in ('project', 'office', 'administration', 'warehouse', 'maintenance', 'general_operation', 'other') then
    raise exception 'cost_center_type inválido';
  end if;

  if not public.has_company_access(v_company_id) then
    raise exception 'forbidden';
  end if;

  if not exists (
    select 1
    from public.company_modules cm
    where cm.company_id = v_company_id
      and lower(cm.module_key) = 'adquisiciones'
      and lower(cm.status) in ('active', 'trial')
  ) then
    if not (
      public.is_owner(v_company_id)
      or public.has_role(v_company_id, 'ADMIN_LOGISTICA', 'logistica')
      or public.has_role(v_company_id, 'ADMIN_CONSTRUCCION', 'construccion')
    ) then
      raise exception 'insufficient role';
    end if;
  else
    raise exception 'cost centers preferred from adquisiciones';
  end if;

  if v_project_id is not null and v_cost_center_type <> 'project' then
    raise exception 'project_id solo puede usarse cuando cost_center_type = project';
  end if;

  if v_project_id is not null then
    perform 1
    from public.projects p
    where p.id = v_project_id
      and p.company_id = v_company_id;

    if not found then
      raise exception 'project_id no existe o no pertenece a la empresa';
    end if;
  end if;

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
  ) values (
    v_company_id,
    v_code,
    v_name,
    v_description,
    v_cost_center_type,
    v_project_id,
    v_is_default,
    v_is_active,
    v_user_id,
    v_user_id
  )
  on conflict (company_id, code)
  do update set
    name = excluded.name,
    description = excluded.description,
    cost_center_type = excluded.cost_center_type,
    project_id = excluded.project_id,
    is_default = excluded.is_default,
    is_active = excluded.is_active,
    updated_by = excluded.updated_by,
    updated_at = now()
  returning id into v_cost_center_id;

  return jsonb_build_object('success', true, 'cost_center_id', v_cost_center_id);
end;
$$;

create or replace function public.update_cost_center(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_cost_center_id uuid;
  v_code text;
  v_name text;
  v_description text;
  v_cost_center_type text;
  v_project_id uuid;
  v_is_default boolean;
  v_is_active boolean;
  v_existing public.cost_centers%rowtype;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_cost_center_id := nullif(btrim(coalesce(p_payload->>'cost_center_id', p_payload->>'id', '')), '')::uuid;
  v_code := btrim(coalesce(p_payload->>'code', ''));
  v_name := btrim(coalesce(p_payload->>'name', ''));
  v_description := nullif(btrim(coalesce(p_payload->>'description', '')), '');
  v_cost_center_type := lower(btrim(coalesce(p_payload->>'cost_center_type', '')));
  v_project_id := nullif(btrim(coalesce(p_payload->>'project_id', '')), '')::uuid;
  v_is_default := coalesce((p_payload->>'is_default')::boolean, false);
  v_is_active := coalesce((p_payload->>'is_active')::boolean, true);

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if v_cost_center_id is null then
    raise exception 'cost_center_id es obligatorio';
  end if;

  select * into v_existing
  from public.cost_centers cc
  where cc.id = v_cost_center_id
    and cc.company_id = v_company_id;

  if not found then
    raise exception 'cost_center not found';
  end if;

  if not public.has_company_access(v_company_id) then
    raise exception 'forbidden';
  end if;

  if not exists (
    select 1
    from public.company_modules cm
    where cm.company_id = v_company_id
      and lower(cm.module_key) = 'adquisiciones'
      and lower(cm.status) in ('active', 'trial')
  ) then
    if not (
      public.is_owner(v_company_id)
      or public.has_role(v_company_id, 'ADMIN_LOGISTICA', 'logistica')
      or public.has_role(v_company_id, 'ADMIN_CONSTRUCCION', 'construccion')
    ) then
      raise exception 'insufficient role';
    end if;
  else
    raise exception 'cost centers preferred from adquisiciones';
  end if;

  if v_code = '' then
    v_code := v_existing.code;
  end if;

  if v_name = '' then
    v_name := v_existing.name;
  end if;

  if v_cost_center_type = '' then
    v_cost_center_type := v_existing.cost_center_type;
  end if;

  if v_cost_center_type not in ('project', 'office', 'administration', 'warehouse', 'maintenance', 'general_operation', 'other') then
    raise exception 'cost_center_type inválido';
  end if;

  if v_project_id is not null and v_cost_center_type <> 'project' then
    raise exception 'project_id solo puede usarse cuando cost_center_type = project';
  end if;

  if v_project_id is not null then
    perform 1
    from public.projects p
    where p.id = v_project_id
      and p.company_id = v_company_id;

    if not found then
      raise exception 'project_id no existe o no pertenece a la empresa';
    end if;
  end if;

  update public.cost_centers
     set code = v_code,
         name = v_name,
         description = v_description,
         cost_center_type = v_cost_center_type,
         project_id = coalesce(v_project_id, project_id),
         is_default = v_is_default,
         is_active = v_is_active,
         updated_by = v_user_id
   where id = v_cost_center_id
     and company_id = v_company_id;

  return jsonb_build_object('success', true, 'cost_center_id', v_cost_center_id);
end;
$$;

create or replace function public.deactivate_cost_center(p_cost_center_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_cost_center_id is null then
    raise exception 'cost_center_id es obligatorio';
  end if;

  select cc.company_id into v_company_id
  from public.cost_centers cc
  where cc.id = p_cost_center_id;

  if v_company_id is null then
    raise exception 'cost_center not found';
  end if;

  if not public.has_company_access(v_company_id) then
    raise exception 'forbidden';
  end if;

  if not exists (
    select 1
    from public.company_modules cm
    where cm.company_id = v_company_id
      and lower(cm.module_key) = 'adquisiciones'
      and lower(cm.status) in ('active', 'trial')
  ) then
    if not (
      public.is_owner(v_company_id)
      or public.has_role(v_company_id, 'ADMIN_LOGISTICA', 'logistica')
      or public.has_role(v_company_id, 'ADMIN_CONSTRUCCION', 'construccion')
    ) then
      raise exception 'insufficient role';
    end if;
  else
    raise exception 'cost centers preferred from adquisiciones';
  end if;

  update public.cost_centers
     set is_active = false,
         updated_by = v_user_id,
         updated_at = now()
   where id = p_cost_center_id
     and company_id = v_company_id;

  return jsonb_build_object('success', true, 'cost_center_id', p_cost_center_id);
end;
$$;

create or replace function public.list_cost_centers(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_company_id uuid;
  v_search text;
  v_is_active boolean := true;
  v_cost_centers jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_search := nullif(btrim(coalesce(p_payload->>'search', '')), '');
  v_is_active := coalesce((p_payload->>'is_active')::boolean, true);

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if not public.has_company_access(v_company_id) then
    raise exception 'forbidden';
  end if;

  select coalesce(jsonb_agg(to_jsonb(cc) order by cc.name asc), '[]'::jsonb)
    into v_cost_centers
  from (
    select
      ccs.id,
      ccs.company_id,
      ccs.code,
      ccs.name,
      ccs.description,
      ccs.cost_center_type,
      ccs.project_id,
      ccs.is_default,
      ccs.is_active,
      ccs.created_at,
      ccs.updated_at
    from public.v_cost_centers_summary ccs
    where ccs.company_id = v_company_id
      and (
        v_search is null
        or upper(ccs.code) like '%' || upper(v_search) || '%'
        or upper(ccs.name) like '%' || upper(v_search) || '%'
      )
      and (
        not v_is_active
        or coalesce(ccs.is_active, true) = true
      )
    order by ccs.name asc
  ) cc;

  return jsonb_build_object('success', true, 'cost_centers', v_cost_centers);
end;
$$;

grant execute on function public.create_cost_center(jsonb) to authenticated;
grant execute on function public.update_cost_center(jsonb) to authenticated;
grant execute on function public.deactivate_cost_center(uuid) to authenticated;
grant execute on function public.list_cost_centers(jsonb) to authenticated;
