create or replace function logistica.assert_warehouse_admin_access(p_company_id uuid)
returns void
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if not public.has_company_access(p_company_id) then
    raise exception 'forbidden';
  end if;

  if not exists (
    select 1
    from public.company_modules cm
    where cm.company_id = p_company_id
      and lower(cm.module_key) = 'logistica'
      and lower(cm.status) in ('active', 'trial')
  ) then
    raise exception 'module access required';
  end if;

  if not (
    public.is_owner(p_company_id)
    or public.has_role(p_company_id, 'ADMIN_LOGISTICA', 'logistica')
  ) then
    raise exception 'insufficient role';
  end if;
end;
$$;

create or replace function logistica.create_warehouse(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_code text;
  v_name text;
  v_description text;
  v_warehouse_type text;
  v_is_active boolean;
  v_warehouse logistica.warehouses%rowtype;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_code := nullif(btrim(coalesce(p_payload->>'code', '')), '');
  v_name := nullif(btrim(coalesce(p_payload->>'name', '')), '');
  v_description := nullif(btrim(coalesce(p_payload->>'description', '')), '');
  v_warehouse_type := lower(btrim(coalesce(p_payload->>'warehouse_type', 'main')));
  v_is_active := coalesce((p_payload->>'is_active')::boolean, true);

  if v_code is null then
    raise exception 'code es obligatorio';
  end if;

  if v_name is null then
    raise exception 'name es obligatorio';
  end if;

  if v_warehouse_type not in ('main', 'project', 'mobile', 'temporary', 'external') then
    raise exception 'warehouse_type inválido';
  end if;

  perform logistica.assert_warehouse_admin_access(v_company_id);

  if exists (
    select 1
    from logistica.warehouses w
    where w.company_id = v_company_id
      and w.code = v_code
  ) then
    raise exception 'Ya existe una bodega con ese código';
  end if;

  insert into logistica.warehouses (
    company_id,
    code,
    name,
    description,
    warehouse_type,
    is_active,
    created_by,
    updated_by
  ) values (
    v_company_id,
    v_code,
    v_name,
    v_description,
    v_warehouse_type,
    v_is_active,
    v_user_id,
    v_user_id
  )
  returning * into v_warehouse;

  return jsonb_build_object(
    'success', true,
    'warehouse_id', v_warehouse.id,
    'warehouse', to_jsonb(v_warehouse)
  );
end;
$$;

create or replace function logistica.update_warehouse(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_warehouse_id uuid;
  v_code text;
  v_name text;
  v_description text;
  v_warehouse_type text;
  v_is_active boolean;
  v_warehouse logistica.warehouses%rowtype;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_warehouse_id := nullif(btrim(coalesce(p_payload->>'warehouse_id', '')), '')::uuid;
  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_code := nullif(btrim(coalesce(p_payload->>'code', '')), '');
  v_name := nullif(btrim(coalesce(p_payload->>'name', '')), '');
  v_description := nullif(btrim(coalesce(p_payload->>'description', '')), '');
  v_warehouse_type := lower(btrim(coalesce(p_payload->>'warehouse_type', 'main')));
  v_is_active := coalesce((p_payload->>'is_active')::boolean, true);

  if v_warehouse_id is null then
    raise exception 'warehouse_id es obligatorio';
  end if;

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if v_code is null then
    raise exception 'code es obligatorio';
  end if;

  if v_name is null then
    raise exception 'name es obligatorio';
  end if;

  if v_warehouse_type not in ('main', 'project', 'mobile', 'temporary', 'external') then
    raise exception 'warehouse_type inválido';
  end if;

  perform logistica.assert_warehouse_admin_access(v_company_id);

  select w.*
    into v_warehouse
  from logistica.warehouses w
  where w.id = v_warehouse_id
    and w.company_id = v_company_id
  for update;

  if not found then
    raise exception 'La bodega no existe o no pertenece a la empresa';
  end if;

  if exists (
    select 1
    from logistica.warehouses w
    where w.company_id = v_company_id
      and w.id <> v_warehouse_id
      and w.code = v_code
  ) then
    raise exception 'Ya existe otra bodega con ese código';
  end if;

  update logistica.warehouses
     set code = v_code,
         name = v_name,
         description = v_description,
         warehouse_type = v_warehouse_type,
         is_active = v_is_active,
         updated_by = v_user_id
   where id = v_warehouse_id
     and company_id = v_company_id
   returning * into v_warehouse;

  return jsonb_build_object(
    'success', true,
    'warehouse_id', v_warehouse.id,
    'warehouse', to_jsonb(v_warehouse)
  );
end;
$$;

create or replace function logistica.deactivate_warehouse(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_warehouse_id uuid;
  v_warehouse logistica.warehouses%rowtype;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_warehouse_id := nullif(btrim(coalesce(p_payload->>'warehouse_id', '')), '')::uuid;
  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;

  if v_warehouse_id is null then
    raise exception 'warehouse_id es obligatorio';
  end if;

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  perform logistica.assert_warehouse_admin_access(v_company_id);

  select w.*
    into v_warehouse
  from logistica.warehouses w
  where w.id = v_warehouse_id
    and w.company_id = v_company_id
  for update;

  if not found then
    raise exception 'La bodega no existe o no pertenece a la empresa';
  end if;

  update logistica.warehouses
     set is_active = false,
         updated_by = v_user_id
   where id = v_warehouse_id
     and company_id = v_company_id
   returning * into v_warehouse;

  return jsonb_build_object(
    'success', true,
    'warehouse_id', v_warehouse.id,
    'warehouse', to_jsonb(v_warehouse)
  );
end;
$$;

create or replace function logistica.activate_warehouse(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_warehouse_id uuid;
  v_warehouse logistica.warehouses%rowtype;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_warehouse_id := nullif(btrim(coalesce(p_payload->>'warehouse_id', '')), '')::uuid;
  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;

  if v_warehouse_id is null then
    raise exception 'warehouse_id es obligatorio';
  end if;

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  perform logistica.assert_warehouse_admin_access(v_company_id);

  select w.*
    into v_warehouse
  from logistica.warehouses w
  where w.id = v_warehouse_id
    and w.company_id = v_company_id
  for update;

  if not found then
    raise exception 'La bodega no existe o no pertenece a la empresa';
  end if;

  update logistica.warehouses
     set is_active = true,
         updated_by = v_user_id
   where id = v_warehouse_id
     and company_id = v_company_id
   returning * into v_warehouse;

  return jsonb_build_object(
    'success', true,
    'warehouse_id', v_warehouse.id,
    'warehouse', to_jsonb(v_warehouse)
  );
end;
$$;

grant execute on function logistica.create_warehouse(jsonb) to authenticated;
grant execute on function logistica.update_warehouse(jsonb) to authenticated;
grant execute on function logistica.deactivate_warehouse(jsonb) to authenticated;
grant execute on function logistica.activate_warehouse(jsonb) to authenticated;
