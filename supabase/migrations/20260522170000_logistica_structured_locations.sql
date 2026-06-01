alter table logistica.locations
  add column if not exists aisle_code text,
  add column if not exists column_number integer,
  add column if not exists level_number integer,
  add column if not exists division_code text,
  add column if not exists structured_code jsonb not null default '{}'::jsonb;

create index if not exists locations_company_warehouse_aisle_idx
  on logistica.locations (company_id, warehouse_id, aisle_code, column_number, level_number);

create or replace function logistica.compose_location_code(
  p_aisle_code text,
  p_column_number integer,
  p_level_number integer default null,
  p_division_code text default null,
  p_column_pad integer default 2,
  p_level_pad integer default 2
)
returns text
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_code text;
begin
  if nullif(btrim(coalesce(p_aisle_code, '')), '') is null then
    raise exception 'aisle_code es obligatorio';
  end if;

  if p_column_number is null then
    raise exception 'column_number es obligatorio';
  end if;

  if p_column_number < 1 then
    raise exception 'column_number inválido';
  end if;

  v_code := upper(btrim(p_aisle_code)) || '-C' || lpad(p_column_number::text, greatest(coalesce(p_column_pad, 2), 1), '0');

  if p_level_number is not null then
    if p_level_number < 1 then
      raise exception 'level_number inválido';
    end if;

    v_code := v_code || '-N' || lpad(p_level_number::text, greatest(coalesce(p_level_pad, 2), 1), '0');
  end if;

  if nullif(btrim(coalesce(p_division_code, '')), '') is not null then
    if p_level_number is null then
      raise exception 'division_code requiere level_number';
    end if;

    v_code := v_code || '-' || upper(btrim(p_division_code));
  end if;

  return v_code;
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

  select coalesce(jsonb_agg(to_jsonb(l) order by l.aisle_code nulls last, l.column_number nulls last, l.level_number nulls last, l.division_code nulls last, l.code asc), '[]'::jsonb)
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
      l.aisle_code,
      l.column_number,
      l.level_number,
      l.division_code,
      l.structured_code,
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
    order by l.aisle_code nulls last, l.column_number nulls last, l.level_number nulls last, l.division_code nulls last, l.code asc
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
  v_aisle_code text;
  v_column_number integer;
  v_level_number integer;
  v_division_code text;
  v_structured_code jsonb := '{}'::jsonb;
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
  v_aisle_code := nullif(upper(btrim(coalesce(p_payload->>'aisle_code', ''))), '');
  v_column_number := nullif(btrim(coalesce(p_payload->>'column_number', '')), '')::integer;
  v_level_number := nullif(btrim(coalesce(p_payload->>'level_number', '')), '')::integer;
  v_division_code := nullif(upper(btrim(coalesce(p_payload->>'division_code', ''))), '');

  perform logistica.assert_location_write_access(v_company_id);

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if v_warehouse_id is null then
    raise exception 'warehouse_id es obligatorio';
  end if;

  if v_code = '' then
    if v_aisle_code is null or v_column_number is null then
      raise exception 'code es obligatorio';
    end if;

    v_code := logistica.compose_location_code(v_aisle_code, v_column_number, v_level_number, v_division_code);
  end if;

  if v_name = '' then
    v_name := v_code;
  end if;

  if v_location_type not in ('shelf', 'rack', 'floor', 'bin', 'zone', 'external', 'other') then
    raise exception 'location_type inválido';
  end if;

  if v_column_number is not null and v_column_number < 1 then
    raise exception 'column_number inválido';
  end if;

  if v_level_number is not null and v_level_number < 1 then
    raise exception 'level_number inválido';
  end if;

  if v_division_code is not null and v_division_code = '' then
    raise exception 'division_code inválido';
  end if;

  select *
    into v_warehouse
  from logistica.warehouses w
  where w.id = v_warehouse_id
    and w.company_id = v_company_id;

  if not found then
    raise exception 'La bodega no pertenece a la empresa';
  end if;

  v_structured_code := jsonb_strip_nulls(jsonb_build_object(
    'aisle_code', v_aisle_code,
    'column_number', v_column_number,
    'column_code', case when v_column_number is not null then format('C%s', lpad(v_column_number::text, 2, '0')) end,
    'level_number', v_level_number,
    'level_code', case when v_level_number is not null then format('N%s', lpad(v_level_number::text, 2, '0')) end,
    'division_code', v_division_code
  ));

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
    aisle_code,
    column_number,
    level_number,
    division_code,
    structured_code,
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
    v_aisle_code,
    v_column_number,
    v_level_number,
    v_division_code,
    v_structured_code,
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
  v_aisle_code text;
  v_column_number integer;
  v_level_number integer;
  v_division_code text;
  v_structured_code jsonb := '{}'::jsonb;
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
  v_aisle_code := nullif(upper(btrim(coalesce(p_payload->>'aisle_code', ''))), '');
  v_column_number := nullif(btrim(coalesce(p_payload->>'column_number', '')), '')::integer;
  v_level_number := nullif(btrim(coalesce(p_payload->>'level_number', '')), '')::integer;
  v_division_code := nullif(upper(btrim(coalesce(p_payload->>'division_code', ''))), '');

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
    if v_aisle_code is not null and v_column_number is not null then
      v_code := logistica.compose_location_code(v_aisle_code, v_column_number, v_level_number, v_division_code);
    else
      raise exception 'code es obligatorio';
    end if;
  end if;

  if v_name = '' then
    v_name := v_code;
  end if;

  if v_location_type not in ('shelf', 'rack', 'floor', 'bin', 'zone', 'external', 'other') then
    raise exception 'location_type inválido';
  end if;

  if v_column_number is not null and v_column_number < 1 then
    raise exception 'column_number inválido';
  end if;

  if v_level_number is not null and v_level_number < 1 then
    raise exception 'level_number inválido';
  end if;

  if v_division_code is not null and v_division_code = '' then
    raise exception 'division_code inválido';
  end if;

  select *
    into v_warehouse
  from logistica.warehouses w
  where w.id = v_warehouse_id
    and w.company_id = v_company_id;

  if not found then
    raise exception 'La bodega no pertenece a la empresa';
  end if;

  v_structured_code := jsonb_strip_nulls(jsonb_build_object(
    'aisle_code', coalesce(v_aisle_code, v_existing.aisle_code),
    'column_number', coalesce(v_column_number, v_existing.column_number),
    'column_code', case when coalesce(v_column_number, v_existing.column_number) is not null then format('C%s', lpad(coalesce(v_column_number, v_existing.column_number)::text, 2, '0')) end,
    'level_number', coalesce(v_level_number, v_existing.level_number),
    'level_code', case when coalesce(v_level_number, v_existing.level_number) is not null then format('N%s', lpad(coalesce(v_level_number, v_existing.level_number)::text, 2, '0')) end,
    'division_code', coalesce(v_division_code, v_existing.division_code)
  ));

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
         aisle_code = coalesce(v_aisle_code, v_existing.aisle_code),
         column_number = coalesce(v_column_number, v_existing.column_number),
         level_number = coalesce(v_level_number, v_existing.level_number),
         division_code = coalesce(v_division_code, v_existing.division_code),
         structured_code = v_structured_code,
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
  v_mode text := 'strict';
  v_strict_mode boolean := true;
  v_location_type text;
  v_description text;
  v_is_active boolean := true;
  v_name_prefix text;
  v_warehouse logistica.warehouses%rowtype;
  v_locations jsonb := '[]'::jsonb;
  v_inserted_count integer := 0;
  v_inserted_row logistica.locations%rowtype;
  v_code text;
  v_column_count integer;
  v_level_count integer;
  v_division_count integer;
  v_total_count integer;
  v_column_number integer;
  v_level_number integer;
  v_division_number integer;
  v_aisle_code text;
  v_column_start integer;
  v_column_end integer;
  v_level_start integer;
  v_level_end integer;
  v_division_start integer;
  v_division_end integer;
  v_column_pad integer := 2;
  v_level_pad integer := 2;
  v_division_pad integer := 2;
  v_prefix text;
  v_start_number integer;
  v_end_number integer;
  v_pad_length integer := 2;
  v_existing_code text;
  v_structured_payload boolean := false;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido para creación masiva de ubicaciones';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_warehouse_id := nullif(btrim(coalesce(p_payload->>'warehouse_id', '')), '')::uuid;
  v_location_type := lower(btrim(coalesce(p_payload->>'location_type', 'rack')));
  v_description := nullif(btrim(coalesce(p_payload->>'description', '')), '');
  v_is_active := coalesce((p_payload->>'is_active')::boolean, true);
  v_name_prefix := nullif(btrim(coalesce(p_payload->>'name_prefix', '')), '');
  v_mode := lower(coalesce(nullif(btrim(coalesce(p_payload->>'mode', '')), ''), 'strict'));
  v_strict_mode := coalesce((p_payload->>'strict_mode')::boolean, v_mode <> 'skip');

  v_aisle_code := nullif(upper(btrim(coalesce(p_payload->>'aisle_code', ''))), '');
  v_column_start := nullif(btrim(coalesce(p_payload->>'column_start', '')), '')::integer;
  v_column_end := nullif(btrim(coalesce(p_payload->>'column_end', '')), '')::integer;
  v_level_start := nullif(btrim(coalesce(p_payload->>'level_start', '')), '')::integer;
  v_level_end := nullif(btrim(coalesce(p_payload->>'level_end', '')), '')::integer;
  v_division_start := nullif(btrim(coalesce(p_payload->>'division_start', '')), '')::integer;
  v_division_end := nullif(btrim(coalesce(p_payload->>'division_end', '')), '')::integer;
  v_column_pad := greatest(coalesce(nullif(btrim(coalesce(p_payload->>'column_pad', '')), '')::integer, 2), 1);
  v_level_pad := greatest(coalesce(nullif(btrim(coalesce(p_payload->>'level_pad', '')), '')::integer, 2), 1);
  v_division_pad := greatest(coalesce(nullif(btrim(coalesce(p_payload->>'division_pad', '')), '')::integer, 2), 1);

  v_prefix := upper(btrim(coalesce(p_payload->>'prefix', '')));
  v_start_number := nullif(btrim(coalesce(p_payload->>'start_number', '')), '')::integer;
  v_end_number := nullif(btrim(coalesce(p_payload->>'end_number', '')), '')::integer;
  v_pad_length := greatest(coalesce(nullif(btrim(coalesce(p_payload->>'pad_length', '')), '')::integer, 2), 1);

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if v_warehouse_id is null then
    raise exception 'warehouse_id es obligatorio';
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

  if v_aisle_code is not null or v_column_start is not null or v_column_end is not null or v_level_start is not null or v_level_end is not null or v_division_start is not null or v_division_end is not null then
    v_structured_payload := true;
  end if;

  if v_structured_payload then
    if v_aisle_code is null then
      raise exception 'aisle_code es obligatorio';
    end if;

    if v_column_start is null or v_column_end is null then
      raise exception 'column_start y column_end son obligatorios';
    end if;

    if v_column_start < 1 or v_column_end < 1 then
      raise exception 'column_start y column_end deben ser mayores a 0';
    end if;

    if v_column_start > v_column_end then
      raise exception 'column_start debe ser menor o igual a column_end';
    end if;

    if v_level_start is null and v_level_end is not null or v_level_start is not null and v_level_end is null then
      raise exception 'level_start y level_end deben venir juntos';
    end if;

    if v_division_start is null and v_division_end is not null or v_division_start is not null and v_division_end is null then
      raise exception 'division_start y division_end deben venir juntos';
    end if;

    if v_division_start is not null and v_level_start is null then
      raise exception 'division_start y division_end requieren niveles';
    end if;

    if v_level_start is not null and v_level_start > v_level_end then
      raise exception 'level_start debe ser menor o igual a level_end';
    end if;

    if v_level_start is not null and (v_level_start < 1 or v_level_end < 1) then
      raise exception 'level_start y level_end deben ser mayores a 0';
    end if;

    if v_division_start is not null and v_division_start > v_division_end then
      raise exception 'division_start debe ser menor o igual a division_end';
    end if;

    if v_division_start is not null and (v_division_start < 1 or v_division_end < 1) then
      raise exception 'division_start y division_end deben ser mayores a 0';
    end if;

    v_column_count := v_column_end - v_column_start + 1;
    v_level_count := case when v_level_start is null then 1 else v_level_end - v_level_start + 1 end;
    v_division_count := case when v_division_start is null then 1 else v_division_end - v_division_start + 1 end;
    v_total_count := v_column_count * v_level_count * v_division_count;

    if v_total_count > 500 then
      raise exception 'El lote máximo permitido es de 500 ubicaciones';
    end if;

    for v_column_number in v_column_start..v_column_end loop
      if v_level_start is null then
        v_code := logistica.compose_location_code(v_aisle_code, v_column_number, null, null, v_column_pad, v_level_pad);

        if v_strict_mode and exists (
          select 1
          from logistica.locations l
          where l.company_id = v_company_id
            and l.warehouse_id = v_warehouse_id
            and upper(l.code) = upper(v_code)
        ) then
          raise exception 'Ya existe una ubicación con el código % en esta bodega', v_code;
        end if;
      else
        for v_level_number in v_level_start..v_level_end loop
          if v_division_start is null then
            v_code := logistica.compose_location_code(v_aisle_code, v_column_number, v_level_number, null, v_column_pad, v_level_pad);

            if v_strict_mode and exists (
              select 1
              from logistica.locations l
              where l.company_id = v_company_id
                and l.warehouse_id = v_warehouse_id
                and upper(l.code) = upper(v_code)
            ) then
              raise exception 'Ya existe una ubicación con el código % en esta bodega', v_code;
            end if;
          else
            for v_division_number in v_division_start..v_division_end loop
              v_code := logistica.compose_location_code(
                v_aisle_code,
                v_column_number,
                v_level_number,
                format('D%s', lpad(v_division_number::text, v_division_pad, '0')),
                v_column_pad,
                v_level_pad
              );

              if v_strict_mode and exists (
                select 1
                from logistica.locations l
                where l.company_id = v_company_id
                  and l.warehouse_id = v_warehouse_id
                  and upper(l.code) = upper(v_code)
              ) then
                raise exception 'Ya existe una ubicación con el código % en esta bodega', v_code;
              end if;
            end loop;
          end if;
        end loop;
      end if;
    end loop;

    perform set_config('datix.skip_logistica_audit', 'on', true);

    for v_column_number in v_column_start..v_column_end loop
      if v_level_start is null then
        v_code := logistica.compose_location_code(v_aisle_code, v_column_number, null, null, v_column_pad, v_level_pad);

        if not v_strict_mode and exists (
          select 1
          from logistica.locations l
          where l.company_id = v_company_id
            and l.warehouse_id = v_warehouse_id
            and upper(l.code) = upper(v_code)
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
          aisle_code,
          column_number,
          level_number,
          division_code,
          structured_code,
          is_active,
          created_by,
          updated_by
        ) values (
          v_company_id,
          v_warehouse_id,
          v_code,
          coalesce(v_name_prefix || ' ' || v_code, v_code),
          v_description,
          v_location_type,
          v_aisle_code,
          v_column_number,
          null,
          null,
          jsonb_strip_nulls(jsonb_build_object(
            'aisle_code', v_aisle_code,
            'column_number', v_column_number,
            'column_code', format('C%s', lpad(v_column_number::text, v_column_pad, '0'))
          )),
          v_is_active,
          v_user_id,
          v_user_id
        )
        returning * into v_inserted_row;

        v_locations := v_locations || jsonb_build_array(to_jsonb(v_inserted_row));
        v_inserted_count := v_inserted_count + 1;
      else
        for v_level_number in v_level_start..v_level_end loop
          if v_division_start is null then
            v_code := logistica.compose_location_code(v_aisle_code, v_column_number, v_level_number, null, v_column_pad, v_level_pad);

            if not v_strict_mode and exists (
              select 1
              from logistica.locations l
              where l.company_id = v_company_id
                and l.warehouse_id = v_warehouse_id
                and upper(l.code) = upper(v_code)
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
              aisle_code,
              column_number,
              level_number,
              division_code,
              structured_code,
              is_active,
              created_by,
              updated_by
            ) values (
              v_company_id,
              v_warehouse_id,
              v_code,
              coalesce(v_name_prefix || ' ' || v_code, v_code),
              v_description,
              v_location_type,
              v_aisle_code,
              v_column_number,
              v_level_number,
              null,
              jsonb_strip_nulls(jsonb_build_object(
                'aisle_code', v_aisle_code,
                'column_number', v_column_number,
                'column_code', format('C%s', lpad(v_column_number::text, v_column_pad, '0')),
                'level_number', v_level_number,
                'level_code', format('N%s', lpad(v_level_number::text, v_level_pad, '0'))
              )),
              v_is_active,
              v_user_id,
              v_user_id
            )
            returning * into v_inserted_row;

            v_locations := v_locations || jsonb_build_array(to_jsonb(v_inserted_row));
            v_inserted_count := v_inserted_count + 1;
          else
            for v_division_number in v_division_start..v_division_end loop
              v_code := logistica.compose_location_code(
                v_aisle_code,
                v_column_number,
                v_level_number,
                format('D%s', lpad(v_division_number::text, v_division_pad, '0')),
                v_column_pad,
                v_level_pad
              );

              if not v_strict_mode and exists (
                select 1
                from logistica.locations l
                where l.company_id = v_company_id
                  and l.warehouse_id = v_warehouse_id
                  and upper(l.code) = upper(v_code)
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
                aisle_code,
                column_number,
                level_number,
                division_code,
                structured_code,
                is_active,
                created_by,
                updated_by
              ) values (
                v_company_id,
                v_warehouse_id,
                v_code,
                coalesce(v_name_prefix || ' ' || v_code, v_code),
                v_description,
                v_location_type,
                v_aisle_code,
                v_column_number,
                v_level_number,
                format('D%s', lpad(v_division_number::text, v_division_pad, '0')),
                jsonb_strip_nulls(jsonb_build_object(
                  'aisle_code', v_aisle_code,
                  'column_number', v_column_number,
                  'column_code', format('C%s', lpad(v_column_number::text, v_column_pad, '0')),
                  'level_number', v_level_number,
                  'level_code', format('N%s', lpad(v_level_number::text, v_level_pad, '0')),
                  'division_code', format('D%s', lpad(v_division_number::text, v_division_pad, '0'))
                )),
                v_is_active,
                v_user_id,
                v_user_id
              )
              returning * into v_inserted_row;

              v_locations := v_locations || jsonb_build_array(to_jsonb(v_inserted_row));
              v_inserted_count := v_inserted_count + 1;
            end loop;
          end if;
        end loop;
      end if;
    end loop;
  else
    if v_prefix = '' then
      raise exception 'prefix es obligatorio';
    end if;

    if v_start_number is null or v_end_number is null then
      raise exception 'start_number y end_number son obligatorios';
    end if;

    if v_start_number < 1 or v_end_number < 1 then
      raise exception 'start_number y end_number deben ser mayores a 0';
    end if;

    if v_start_number > v_end_number then
      raise exception 'start_number debe ser menor o igual a end_number';
    end if;

    if v_end_number - v_start_number + 1 > 500 then
      raise exception 'El lote máximo permitido es de 500 ubicaciones';
    end if;

    for v_existing_code in
      select format('%s-%s', v_prefix, lpad(gs::text, v_pad_length, '0'))
      from generate_series(v_start_number, v_end_number) gs
    loop
      if v_strict_mode and exists (
        select 1
        from logistica.locations l
        where l.company_id = v_company_id
          and l.warehouse_id = v_warehouse_id
          and upper(l.code) = upper(v_existing_code)
      ) then
        raise exception 'Ya existe una ubicación con el código % en esta bodega', v_existing_code;
      end if;
    end loop;

    perform set_config('datix.skip_logistica_audit', 'on', true);

    for v_existing_code in
      select format('%s-%s', v_prefix, lpad(gs::text, v_pad_length, '0'))
      from generate_series(v_start_number, v_end_number) gs
    loop
      if not v_strict_mode and exists (
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
        aisle_code,
        column_number,
        level_number,
        division_code,
        structured_code,
        is_active,
        created_by,
        updated_by
      ) values (
        v_company_id,
        v_warehouse_id,
        v_existing_code,
        coalesce(v_name_prefix || ' ' || v_existing_code, v_existing_code),
        v_description,
        v_location_type,
        v_prefix,
        nullif(regexp_replace(v_existing_code, '^.*-', ''), '')::integer,
        null,
        null,
        jsonb_strip_nulls(jsonb_build_object(
          'legacy_prefix', v_prefix,
          'number', nullif(regexp_replace(v_existing_code, '^.*-', ''), '')::integer,
          'code', v_existing_code
        )),
        v_is_active,
        v_user_id,
        v_user_id
      )
      returning * into v_inserted_row;

      v_locations := v_locations || jsonb_build_array(to_jsonb(v_inserted_row));
      v_inserted_count := v_inserted_count + 1;
    end loop;
  end if;

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
      'count', v_inserted_count,
      'strict_mode', v_strict_mode,
      'structured_mode', v_structured_payload,
      'locations', v_locations
    )
  );

  return jsonb_build_object('success', true, 'count', v_inserted_count, 'locations', v_locations);
end;
$$;

grant execute on function logistica.compose_location_code(text, integer, integer, text, integer, integer) to authenticated;
grant execute on function logistica.list_locations(jsonb) to authenticated;
grant execute on function logistica.create_location(jsonb) to authenticated;
grant execute on function logistica.update_location(jsonb) to authenticated;
grant execute on function logistica.create_locations_bulk(jsonb) to authenticated;

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

grant execute on function public.list_locations(jsonb) to authenticated;
grant execute on function public.create_location(jsonb) to authenticated;
grant execute on function public.update_location(jsonb) to authenticated;
grant execute on function public.create_locations_bulk(jsonb) to authenticated;
