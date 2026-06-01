alter table logistica.locations
  drop constraint if exists locations_type_check;

alter table logistica.locations
  add constraint locations_type_check
  check (location_type in ('shelf', 'rack', 'floor', 'bin', 'zone', 'external', 'other'));

create or replace function logistica.assert_location_read_access(p_company_id uuid)
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

create or replace function logistica.assert_location_write_access(p_company_id uuid)
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
  ) then
    raise exception 'insufficient role';
  end if;
end;
$$;

create or replace function logistica.log_location_audit(
  p_company_id uuid,
  p_location_id uuid,
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
    'locations',
    p_location_id,
    p_old_data,
    p_new_data,
    jsonb_build_object('backend_owned', true, 'source', 'location_rpc')
  );
end;
$$;

create or replace function logistica.list_locations(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_company_id uuid;
  v_warehouse_id uuid;
  v_include_inactive boolean := true;
  v_search text;
  v_locations jsonb := '[]'::jsonb;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_warehouse_id := nullif(btrim(coalesce(p_payload->>'warehouse_id', '')), '')::uuid;
  v_include_inactive := coalesce((p_payload->>'include_inactive')::boolean, true);
  v_search := nullif(btrim(coalesce(p_payload->>'search', '')), '');

  perform logistica.assert_location_read_access(v_company_id);

  if v_warehouse_id is null then
    raise exception 'warehouse_id es obligatorio';
  end if;

  if not exists (
    select 1
    from logistica.warehouses w
    where w.id = v_warehouse_id
      and w.company_id = v_company_id
  ) then
    raise exception 'La bodega no pertenece a la empresa';
  end if;

  select coalesce(jsonb_agg(to_jsonb(l) order by l.code asc), '[]'::jsonb)
    into v_locations
  from (
    select
      l.id,
      l.company_id,
      l.warehouse_id,
      l.code,
      l.name,
      l.description,
      l.location_type,
      l.is_active,
      l.created_at,
      l.updated_at,
      l.created_by,
      l.updated_by
    from logistica.locations l
    where l.company_id = v_company_id
      and l.warehouse_id = v_warehouse_id
      and (
        v_include_inactive
        or coalesce(l.is_active, true) = true
      )
      and (
        v_search is null
        or upper(l.code) like '%' || upper(v_search) || '%'
        or upper(l.name) like '%' || upper(v_search) || '%'
      )
    order by l.code asc
  ) l;

  return jsonb_build_object(
    'success', true,
    'locations', v_locations
  );
end;
$$;

create or replace function logistica.create_location(p_payload jsonb)
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
  v_location_type text;
  v_is_active boolean := true;
  v_warehouse logistica.warehouses%rowtype;
  v_location logistica.locations%rowtype;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_warehouse_id := nullif(btrim(coalesce(p_payload->>'warehouse_id', '')), '')::uuid;
  v_code := upper(btrim(coalesce(p_payload->>'code', '')));
  v_name := btrim(coalesce(p_payload->>'name', ''));
  v_description := nullif(btrim(coalesce(p_payload->>'description', '')), '');
  v_location_type := lower(btrim(coalesce(p_payload->>'location_type', 'rack')));
  v_is_active := coalesce((p_payload->>'is_active')::boolean, true);

  perform logistica.assert_location_write_access(v_company_id);

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if v_warehouse_id is null then
    raise exception 'warehouse_id es obligatorio';
  end if;

  if v_code = '' then
    raise exception 'code es obligatorio';
  end if;

  if v_name = '' then
    raise exception 'name es obligatorio';
  end if;

  if v_location_type not in ('shelf', 'rack', 'floor', 'bin', 'zone', 'external', 'other') then
    raise exception 'location_type inválido';
  end if;

  select *
    into v_warehouse
  from logistica.warehouses w
  where w.id = v_warehouse_id
    and w.company_id = v_company_id;

  if not found then
    raise exception 'La bodega no pertenece a la empresa';
  end if;

  if exists (
    select 1
    from logistica.locations l
    where l.company_id = v_company_id
      and l.warehouse_id = v_warehouse_id
      and upper(l.code) = v_code
  ) then
    raise exception 'Ya existe una ubicación con ese código en esa bodega';
  end if;

  perform set_config('datix.skip_logistica_audit', 'on', true);

  insert into logistica.locations (
    company_id,
    warehouse_id,
    code,
    name,
    description,
    location_type,
    is_active,
    created_by,
    updated_by
  ) values (
    v_company_id,
    v_warehouse_id,
    v_code,
    v_name,
    v_description,
    v_location_type,
    v_is_active,
    v_user_id,
    v_user_id
  )
  returning * into v_location;

  perform logistica.log_location_audit(
    v_company_id,
    v_location.id,
    'LOCATION_CREATED',
    null,
    to_jsonb(v_location)
  );

  return jsonb_build_object('success', true, 'location_id', v_location.id, 'location', to_jsonb(v_location));
end;
$$;

create or replace function logistica.update_location(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_location_id uuid;
  v_company_id uuid;
  v_warehouse_id uuid;
  v_code text;
  v_name text;
  v_description text;
  v_location_type text;
  v_is_active boolean := true;
  v_existing logistica.locations%rowtype;
  v_warehouse logistica.warehouses%rowtype;
  v_updated logistica.locations%rowtype;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_location_id := nullif(btrim(coalesce(p_payload->>'location_id', '')), '')::uuid;
  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_warehouse_id := nullif(btrim(coalesce(p_payload->>'warehouse_id', '')), '')::uuid;
  v_code := upper(btrim(coalesce(p_payload->>'code', '')));
  v_name := btrim(coalesce(p_payload->>'name', ''));
  v_description := nullif(btrim(coalesce(p_payload->>'description', '')), '');
  v_location_type := lower(btrim(coalesce(p_payload->>'location_type', 'rack')));
  v_is_active := coalesce((p_payload->>'is_active')::boolean, true);

  if v_location_id is null then
    raise exception 'location_id es obligatorio';
  end if;

  select *
    into v_existing
  from logistica.locations l
  where l.id = v_location_id;

  if not found then
    raise exception 'Ubicación no encontrada';
  end if;

  if v_company_id is null then
    v_company_id := v_existing.company_id;
  end if;

  if v_company_id <> v_existing.company_id then
    raise exception 'La ubicación no pertenece a la empresa';
  end if;

  perform logistica.assert_location_write_access(v_company_id);

  if v_warehouse_id is null then
    v_warehouse_id := v_existing.warehouse_id;
  end if;

  if v_code = '' then
    raise exception 'code es obligatorio';
  end if;

  if v_name = '' then
    raise exception 'name es obligatorio';
  end if;

  if v_location_type not in ('shelf', 'rack', 'floor', 'bin', 'zone', 'external', 'other') then
    raise exception 'location_type inválido';
  end if;

  select *
    into v_warehouse
  from logistica.warehouses w
  where w.id = v_warehouse_id
    and w.company_id = v_company_id;

  if not found then
    raise exception 'La bodega no pertenece a la empresa';
  end if;

  if exists (
    select 1
    from logistica.locations l
    where l.company_id = v_company_id
      and l.warehouse_id = v_warehouse_id
      and upper(l.code) = v_code
      and l.id <> v_location_id
  ) then
    raise exception 'Ya existe una ubicación con ese código en esa bodega';
  end if;

  perform set_config('datix.skip_logistica_audit', 'on', true);

  update logistica.locations
     set warehouse_id = v_warehouse_id,
         code = v_code,
         name = v_name,
         description = v_description,
         location_type = v_location_type,
         is_active = v_is_active,
         updated_by = v_user_id
   where id = v_location_id
     and company_id = v_company_id
   returning * into v_updated;

  perform logistica.log_location_audit(
    v_company_id,
    v_updated.id,
    'LOCATION_UPDATED',
    to_jsonb(v_existing),
    to_jsonb(v_updated)
  );

  return jsonb_build_object('success', true, 'location_id', v_updated.id, 'location', to_jsonb(v_updated));
end;
$$;

create or replace function logistica.deactivate_location(p_location_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_location logistica.locations%rowtype;
  v_blocking_stock_count integer := 0;
  v_updated logistica.locations%rowtype;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_location_id is null then
    raise exception 'location_id es obligatorio';
  end if;

  select *
    into v_location
  from logistica.locations l
  where l.id = p_location_id;

  if not found then
    raise exception 'Ubicación no encontrada';
  end if;

  perform logistica.assert_location_write_access(v_location.company_id);

  select count(*)::int
    into v_blocking_stock_count
  from logistica.stock_balances b
  where b.company_id = v_location.company_id
    and b.location_id = p_location_id
    and coalesce(b.quantity_on_hand, 0) > 0;

  if v_blocking_stock_count > 0 then
    raise exception 'No se puede desactivar la ubicación: existe stock disponible';
  end if;

  if coalesce(v_location.is_active, true) = false then
    raise exception 'La ubicación ya está desactivada';
  end if;

  perform set_config('datix.skip_logistica_audit', 'on', true);

  update logistica.locations
     set is_active = false,
         updated_by = v_user_id
   where id = p_location_id
     and company_id = v_location.company_id
   returning * into v_updated;

  perform logistica.log_location_audit(
    v_location.company_id,
    v_updated.id,
    'LOCATION_DEACTIVATED',
    to_jsonb(v_location),
    to_jsonb(v_updated)
  );

  return jsonb_build_object('success', true, 'location_id', v_updated.id, 'location', to_jsonb(v_updated));
end;
$$;

grant execute on function logistica.list_locations(jsonb) to authenticated;
grant execute on function logistica.create_location(jsonb) to authenticated;
grant execute on function logistica.update_location(jsonb) to authenticated;
grant execute on function logistica.deactivate_location(uuid) to authenticated;
revoke insert, update, delete on logistica.locations from authenticated;

create or replace function public.list_locations(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, logistica
as $$
begin
  return logistica.list_locations(p_payload);
end;
$$;

create or replace function public.create_location(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, logistica
as $$
begin
  return logistica.create_location(p_payload);
end;
$$;

create or replace function public.update_location(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, logistica
as $$
begin
  return logistica.update_location(p_payload);
end;
$$;

create or replace function public.deactivate_location(p_location_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, logistica
as $$
begin
  return logistica.deactivate_location(p_location_id);
end;
$$;

grant execute on function public.list_locations(jsonb) to authenticated;
grant execute on function public.create_location(jsonb) to authenticated;
grant execute on function public.update_location(jsonb) to authenticated;
grant execute on function public.deactivate_location(uuid) to authenticated;
