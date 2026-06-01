-- 20260529194000_public_cost_centers_acquisition_ownership.sql
-- Corrige ownership modular de public.cost_centers para respetar Adquisiciones > Logística.

create or replace function public.can_manage_cost_centers(p_company_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select case
    when p_company_id is null or auth.uid() is null then false
    when public.is_owner(p_company_id) then true
    when exists (
      select 1
      from public.company_modules cm
      where cm.company_id = p_company_id
        and lower(cm.module_key) = 'adquisiciones'
        and lower(cm.status) in ('active', 'trial')
    ) then public.has_role(p_company_id, 'ADMIN_ADQUISICIONES', 'adquisiciones')
    else (
      public.has_role(p_company_id, 'ADMIN_LOGISTICA', 'logistica')
      or public.has_role(p_company_id, 'ADMIN_CONSTRUCCION', 'construccion')
    )
  end;
$$;

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
  v_adquisiciones_contracted boolean;
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

  select exists (
    select 1
    from public.company_modules cm
    where cm.company_id = v_company_id
      and lower(cm.module_key) = 'adquisiciones'
      and lower(cm.status) in ('active', 'trial')
  ) into v_adquisiciones_contracted;

  if v_adquisiciones_contracted then
    if not (public.is_owner(v_company_id) or public.has_role(v_company_id, 'ADMIN_ADQUISICIONES', 'adquisiciones')) then
      raise exception 'Los centros de costo son administrados desde Adquisiciones.';
    end if;
  else
    if not (
      public.is_owner(v_company_id)
      or public.has_role(v_company_id, 'ADMIN_LOGISTICA', 'logistica')
      or public.has_role(v_company_id, 'ADMIN_CONSTRUCCION', 'construccion')
    ) then
      raise exception 'insufficient role';
    end if;
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
  v_adquisiciones_contracted boolean;
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

  select exists (
    select 1
    from public.company_modules cm
    where cm.company_id = v_company_id
      and lower(cm.module_key) = 'adquisiciones'
      and lower(cm.status) in ('active', 'trial')
  ) into v_adquisiciones_contracted;

  if v_adquisiciones_contracted then
    if not (public.is_owner(v_company_id) or public.has_role(v_company_id, 'ADMIN_ADQUISICIONES', 'adquisiciones')) then
      raise exception 'Los centros de costo son administrados desde Adquisiciones.';
    end if;
  else
    if not (
      public.is_owner(v_company_id)
      or public.has_role(v_company_id, 'ADMIN_LOGISTICA', 'logistica')
      or public.has_role(v_company_id, 'ADMIN_CONSTRUCCION', 'construccion')
    ) then
      raise exception 'insufficient role';
    end if;
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
  v_adquisiciones_contracted boolean;
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

  select exists (
    select 1
    from public.company_modules cm
    where cm.company_id = v_company_id
      and lower(cm.module_key) = 'adquisiciones'
      and lower(cm.status) in ('active', 'trial')
  ) into v_adquisiciones_contracted;

  if v_adquisiciones_contracted then
    if not (public.is_owner(v_company_id) or public.has_role(v_company_id, 'ADMIN_ADQUISICIONES', 'adquisiciones')) then
      raise exception 'Los centros de costo son administrados desde Adquisiciones.';
    end if;
  else
    if not (
      public.is_owner(v_company_id)
      or public.has_role(v_company_id, 'ADMIN_LOGISTICA', 'logistica')
      or public.has_role(v_company_id, 'ADMIN_CONSTRUCCION', 'construccion')
    ) then
      raise exception 'insufficient role';
    end if;
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

do $$
begin
  if exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'cost_centers' and policyname = 'cost_centers_insert_company'
  ) then
    drop policy cost_centers_insert_company on public.cost_centers;
  end if;

  if exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'cost_centers' and policyname = 'cost_centers_update_company'
  ) then
    drop policy cost_centers_update_company on public.cost_centers;
  end if;
end $$;

drop policy if exists cost_centers_insert_company on public.cost_centers;
create policy cost_centers_insert_company
on public.cost_centers
for insert
with check (public.can_manage_cost_centers(company_id));

drop policy if exists cost_centers_update_company on public.cost_centers;
create policy cost_centers_update_company
on public.cost_centers
for update
using (public.can_manage_cost_centers(company_id))
with check (public.can_manage_cost_centers(company_id));
