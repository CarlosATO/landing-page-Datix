create or replace function logistica.assert_warehouse_write_access(p_company_id uuid)
returns void
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_membership_role text;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  select cu.role
    into v_membership_role
  from public.company_users cu
  where cu.company_id = p_company_id
    and cu.user_id = v_user_id
  limit 1;

  if v_membership_role is null then
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

  if upper(v_membership_role) not in ('OWNER', 'MANAGER')
     and not public.has_role(p_company_id, 'ADMIN_LOGISTICA', 'logistica')
  then
    raise exception 'insufficient role';
  end if;
end;
$$;

create or replace function logistica.assert_warehouse_read_access(p_company_id uuid)
returns void
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_membership_role text;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  select cu.role
    into v_membership_role
  from public.company_users cu
  where cu.company_id = p_company_id
    and cu.user_id = v_user_id
  limit 1;

  if v_membership_role is null then
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
    upper(v_membership_role) in ('OWNER', 'MANAGER')
    or public.has_role(p_company_id, 'ADMIN_LOGISTICA', 'logistica')
    or public.has_role(p_company_id, 'OPERARIO_LOGISTICA', 'logistica')
  ) then
    raise exception 'insufficient role';
  end if;
end;
$$;

create or replace function logistica.log_warehouse_audit(
  p_company_id uuid,
  p_warehouse_id uuid,
  p_action text,
  p_old_data jsonb,
  p_new_data jsonb
)
returns void
language plpgsql
security definer
set search_path = logistica, public
as $$
begin
  insert into public.audit_log (
    company_id,
    user_id,
    action,
    entity_schema,
    entity_table,
    entity_id,
    old_data,
    new_data,
    metadata
  ) values (
    p_company_id,
    auth.uid(),
    p_action,
    'logistica',
    'warehouses',
    p_warehouse_id,
    p_old_data,
    p_new_data,
    jsonb_build_object('backend_owned', true, 'source', 'warehouse_rpc')
  );
end;
$$;

create or replace function logistica.list_warehouses(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_include_inactive boolean := true;
  v_search text;
  v_warehouses jsonb := '[]'::jsonb;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_include_inactive := coalesce((p_payload->>'include_inactive')::boolean, true);
  v_search := nullif(btrim(coalesce(p_payload->>'search', '')), '');

  perform logistica.assert_warehouse_read_access(v_company_id);

  select coalesce(jsonb_agg(to_jsonb(w) order by w.name asc), '[]'::jsonb)
    into v_warehouses
  from (
    select
      w.id,
      w.company_id,
      w.code,
      w.name,
      w.description,
      w.warehouse_type,
      w.is_active,
      w.created_at,
      w.updated_at
    from logistica.warehouses w
    where w.company_id = v_company_id
      and (
        v_include_inactive
        or coalesce(w.is_active, true) = true
      )
      and (
        v_search is null
        or upper(w.code) like '%' || upper(v_search) || '%'
        or upper(w.name) like '%' || upper(v_search) || '%'
      )
    order by w.name asc
  ) w;

  return jsonb_build_object(
    'success', true,
    'warehouses', v_warehouses
  );
end;
$$;

create or replace function logistica.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_company_id uuid;
  v_entity_id uuid;
  v_old jsonb;
  v_new jsonb;
begin
  if current_setting('datix.skip_logistica_audit', true) = 'on' then
    if tg_op = 'DELETE' then
      return old;
    end if;

    return new;
  end if;

  if tg_op = 'INSERT' then
    v_company_id := new.company_id;
    v_entity_id := new.id;
    v_new := to_jsonb(new);
  elsif tg_op = 'UPDATE' then
    v_company_id := coalesce(new.company_id, old.company_id);
    v_entity_id := coalesce(new.id, old.id);
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
  else
    v_company_id := old.company_id;
    v_entity_id := old.id;
    v_old := to_jsonb(old);
  end if;

  insert into logistica.audit_log (
    company_id,
    user_id,
    action,
    entity_table,
    entity_id,
    old_data,
    new_data,
    metadata
  ) values (
    v_company_id,
    auth.uid(),
    lower(tg_op),
    tg_table_name,
    v_entity_id,
    v_old,
    v_new,
    jsonb_build_object('trigger', true)
  );

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
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
  v_code := upper(btrim(coalesce(p_payload->>'code', '')));
  v_name := btrim(coalesce(p_payload->>'name', ''));
  v_description := nullif(btrim(coalesce(p_payload->>'description', '')), '');
  v_warehouse_type := lower(btrim(coalesce(p_payload->>'warehouse_type', 'main')));
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

  if v_warehouse_type not in ('main', 'project', 'mobile', 'temporary', 'external') then
    raise exception 'warehouse_type inválido';
  end if;

  perform logistica.assert_warehouse_write_access(v_company_id);
  perform set_config('datix.skip_logistica_audit', 'on', true);

  if exists (
    select 1
    from logistica.warehouses w
    where w.company_id = v_company_id
      and upper(btrim(w.code)) = v_code
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

  perform logistica.log_warehouse_audit(
    v_company_id,
    v_warehouse.id,
    'WAREHOUSE_CREATED',
    null,
    to_jsonb(v_warehouse)
  );

  return jsonb_build_object('success', true, 'warehouse_id', v_warehouse.id, 'warehouse', to_jsonb(v_warehouse));
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
  v_old_warehouse logistica.warehouses%rowtype;
  v_new_warehouse logistica.warehouses%rowtype;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_warehouse_id := nullif(btrim(coalesce(p_payload->>'warehouse_id', '')), '')::uuid;
  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_code := upper(btrim(coalesce(p_payload->>'code', '')));
  v_name := btrim(coalesce(p_payload->>'name', ''));
  v_description := nullif(btrim(coalesce(p_payload->>'description', '')), '');
  v_warehouse_type := lower(btrim(coalesce(p_payload->>'warehouse_type', 'main')));
  v_is_active := coalesce((p_payload->>'is_active')::boolean, true);

  if v_warehouse_id is null then
    raise exception 'warehouse_id es obligatorio';
  end if;

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if v_code = '' then
    raise exception 'code es obligatorio';
  end if;

  if v_name = '' then
    raise exception 'name es obligatorio';
  end if;

  if v_warehouse_type not in ('main', 'project', 'mobile', 'temporary', 'external') then
    raise exception 'warehouse_type inválido';
  end if;

  perform logistica.assert_warehouse_write_access(v_company_id);
  perform set_config('datix.skip_logistica_audit', 'on', true);

  select w.*
    into v_old_warehouse
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
      and upper(btrim(w.code)) = v_code
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
   returning * into v_new_warehouse;

  perform logistica.log_warehouse_audit(
    v_company_id,
    v_new_warehouse.id,
    'WAREHOUSE_UPDATED',
    to_jsonb(v_old_warehouse),
    to_jsonb(v_new_warehouse)
  );

  return jsonb_build_object('success', true, 'warehouse_id', v_new_warehouse.id, 'warehouse', to_jsonb(v_new_warehouse));
end;
$$;

create or replace function logistica.deactivate_warehouse(p_warehouse_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_warehouse logistica.warehouses%rowtype;
  v_blocking_balance_count integer;
  v_blocking_location_count integer;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_warehouse_id is null then
    raise exception 'warehouse_id es obligatorio';
  end if;

  select w.*
    into v_warehouse
  from logistica.warehouses w
  where w.id = p_warehouse_id
  for update;

  if not found then
    raise exception 'La bodega no existe';
  end if;

  v_company_id := v_warehouse.company_id;

  perform logistica.assert_warehouse_write_access(v_company_id);
  perform set_config('datix.skip_logistica_audit', 'on', true);

  select count(*)::int
    into v_blocking_balance_count
  from logistica.stock_balances b
  where b.company_id = v_company_id
    and b.warehouse_id = p_warehouse_id
    and coalesce(b.quantity_on_hand, 0) > 0;

  if v_blocking_balance_count > 0 then
    raise exception 'No se puede desactivar la bodega: existen stock_balances activos';
  end if;

  select count(*)::int
    into v_blocking_location_count
  from logistica.locations l
  where l.company_id = v_company_id
    and l.warehouse_id = p_warehouse_id
    and coalesce(l.is_active, true) = true;

  if v_blocking_location_count > 0 then
    raise exception 'No se puede desactivar la bodega: existen ubicaciones activas asociadas';
  end if;

  if coalesce(v_warehouse.is_active, true) = false then
    raise exception 'La bodega ya está desactivada';
  end if;

  update logistica.warehouses
     set is_active = false,
         updated_by = v_user_id
   where id = p_warehouse_id
     and company_id = v_company_id
   returning * into v_warehouse;

  perform logistica.log_warehouse_audit(
    v_company_id,
    v_warehouse.id,
    'WAREHOUSE_DEACTIVATED',
    jsonb_build_object('is_active', true),
    to_jsonb(v_warehouse)
  );

  return jsonb_build_object('success', true, 'warehouse_id', v_warehouse.id, 'warehouse', to_jsonb(v_warehouse));
end;
$$;

revoke insert, update, delete on logistica.warehouses from authenticated;
grant execute on function logistica.create_warehouse(jsonb) to authenticated;
grant execute on function logistica.update_warehouse(jsonb) to authenticated;
grant execute on function logistica.deactivate_warehouse(uuid) to authenticated;
grant execute on function logistica.list_warehouses(jsonb) to authenticated;

create or replace function public.list_warehouses(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, logistica
as $$
begin
  return logistica.list_warehouses(p_payload);
end;
$$;

create or replace function public.create_warehouse(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, logistica
as $$
begin
  return logistica.create_warehouse(p_payload);
end;
$$;

create or replace function public.update_warehouse(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, logistica
as $$
begin
  return logistica.update_warehouse(p_payload);
end;
$$;

create or replace function public.deactivate_warehouse(p_warehouse_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, logistica
as $$
begin
  return logistica.deactivate_warehouse(p_warehouse_id);
end;
$$;

grant execute on function public.list_warehouses(jsonb) to authenticated;
grant execute on function public.create_warehouse(jsonb) to authenticated;
grant execute on function public.update_warehouse(jsonb) to authenticated;
grant execute on function public.deactivate_warehouse(uuid) to authenticated;
