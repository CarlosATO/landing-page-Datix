create or replace function logistica.create_locations_bulk(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_warehouse_id uuid;
  v_membership_role text;
  v_prefix text;
  v_start_number integer;
  v_end_number integer;
  v_pad_length integer := 2;
  v_location_type text;
  v_name_prefix text;
  v_description text;
  v_is_active boolean := true;
  v_mode text := 'strict';
  v_warehouse logistica.warehouses%rowtype;
  v_existing_code text;
  v_locations jsonb := '[]'::jsonb;
  v_inserted_count integer := 0;
  v_inserted_row logistica.locations%rowtype;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido para creación masiva de ubicaciones';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_warehouse_id := nullif(btrim(coalesce(p_payload->>'warehouse_id', '')), '')::uuid;
  v_prefix := upper(btrim(coalesce(p_payload->>'prefix', '')));
  v_start_number := nullif(btrim(coalesce(p_payload->>'start_number', '')), '')::integer;
  v_end_number := nullif(btrim(coalesce(p_payload->>'end_number', '')), '')::integer;
  v_pad_length := greatest(coalesce(nullif(btrim(coalesce(p_payload->>'pad_length', '')), '')::integer, 2), 1);
  v_location_type := lower(btrim(coalesce(p_payload->>'location_type', 'rack')));
  v_name_prefix := nullif(btrim(coalesce(p_payload->>'name_prefix', '')), '');
  v_description := nullif(btrim(coalesce(p_payload->>'description', '')), '');
  v_is_active := coalesce((p_payload->>'is_active')::boolean, true);
  v_mode := lower(coalesce(nullif(btrim(coalesce(p_payload->>'mode', '')), ''), 'strict'));

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if v_warehouse_id is null then
    raise exception 'warehouse_id es obligatorio';
  end if;

  if v_prefix = '' then
    raise exception 'prefix es obligatorio';
  end if;

  if v_start_number is null or v_end_number is null then
    raise exception 'start_number y end_number son obligatorios';
  end if;

  if v_start_number > v_end_number then
    raise exception 'start_number debe ser menor o igual a end_number';
  end if;

  if v_end_number - v_start_number + 1 > 500 then
    raise exception 'El lote máximo permitido es de 500 ubicaciones';
  end if;

  if v_location_type not in ('shelf', 'rack', 'floor', 'bin', 'zone', 'external', 'other') then
    raise exception 'location_type inválido';
  end if;

  select cu.role
    into v_membership_role
  from public.company_users cu
  where cu.company_id = v_company_id
    and cu.user_id = v_user_id
  limit 1;

  if v_membership_role is null then
    raise exception 'forbidden';
  end if;

  if not exists (
    select 1
    from public.company_modules cm
    where cm.company_id = v_company_id
      and lower(cm.module_key) = 'logistica'
      and lower(cm.status) in ('active', 'trial')
  ) then
    raise exception 'module access required';
  end if;

  if not (
    upper(v_membership_role) = 'OWNER'
    or public.has_role(v_company_id, 'ADMIN_LOGISTICA', 'logistica')
  ) then
    raise exception 'insufficient role';
  end if;

  select *
    into v_warehouse
  from logistica.warehouses w
  where w.id = v_warehouse_id
    and w.company_id = v_company_id;

  if not found then
    raise exception 'La bodega no pertenece a la empresa';
  end if;

  for v_existing_code in
    select format('%s-%s', v_prefix, lpad(gs::text, v_pad_length, '0'))
    from generate_series(v_start_number, v_end_number) gs
  loop
    if exists (
      select 1
      from logistica.locations l
      where l.company_id = v_company_id
        and l.warehouse_id = v_warehouse_id
        and upper(l.code) = upper(v_existing_code)
    ) then
      if v_mode = 'skip' then
        continue;
      end if;

      raise exception 'Ya existe una ubicación con el código % en esta bodega', v_existing_code;
    end if;
  end loop;

  perform set_config('datix.skip_logistica_audit', 'on', true);

  for v_existing_code in
    select format('%s-%s', v_prefix, lpad(gs::text, v_pad_length, '0'))
    from generate_series(v_start_number, v_end_number) gs
  loop
    if v_mode = 'skip' and exists (
      select 1
      from logistica.locations l
      where l.company_id = v_company_id
        and l.warehouse_id = v_warehouse_id
        and upper(l.code) = upper(v_existing_code)
    ) then
      continue;
    end if;

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
      v_existing_code,
      coalesce(v_name_prefix || '-' || lpad(regexp_replace(v_existing_code, '^.*-', ''), v_pad_length, '0'), v_existing_code),
      v_description,
      v_location_type,
      v_is_active,
      v_user_id,
      v_user_id
    )
    returning * into v_inserted_row;

    v_locations := v_locations || jsonb_build_array(to_jsonb(v_inserted_row));
    v_inserted_count := v_inserted_count + 1;
  end loop;

  if v_inserted_count = 0 then
    raise exception 'No se creó ninguna ubicación: todas ya existían';
  end if;

  perform logistica.log_location_audit(
    v_company_id,
    null,
    'LOCATION_BULK_CREATED',
    null,
    jsonb_build_object(
      'warehouse_id', v_warehouse_id,
      'prefix', v_prefix,
      'start_number', v_start_number,
      'end_number', v_end_number,
      'pad_length', v_pad_length,
      'location_type', v_location_type,
      'mode', v_mode,
      'count', v_inserted_count,
      'locations', v_locations
    )
  );

  return jsonb_build_object('success', true, 'count', v_inserted_count, 'locations', v_locations);
end;
$$;

grant execute on function logistica.create_locations_bulk(jsonb) to authenticated;

create or replace function public.create_locations_bulk(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, logistica
as $$
begin
  return logistica.create_locations_bulk(p_payload);
end;
$$;

grant execute on function public.create_locations_bulk(jsonb) to authenticated;
