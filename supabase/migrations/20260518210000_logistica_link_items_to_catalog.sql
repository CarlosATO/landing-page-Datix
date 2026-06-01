create or replace function public.set_updated_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

alter table logistica.items add column if not exists catalog_item_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'items_catalog_item_id_fkey'
  ) then
    alter table logistica.items
      add constraint items_catalog_item_id_fkey
      foreign key (catalog_item_id) references public.catalog_items(id) on delete set null;
  end if;
end $$;

create index if not exists logistica_items_company_catalog_item_idx
  on logistica.items (company_id, catalog_item_id);

do $$
declare
  v_duplicate_groups integer;
begin
  select count(*) into v_duplicate_groups
  from (
    select 1
    from logistica.items
    where catalog_item_id is not null
    group by company_id, catalog_item_id
    having count(*) > 1
  ) dupes;

  if v_duplicate_groups = 0 then
    create unique index if not exists logistica_items_company_catalog_item_key_idx
      on logistica.items (company_id, catalog_item_id)
      where catalog_item_id is not null;
  else
    raise notice 'Skipping logistica.items catalog unique index due to % duplicate groups', v_duplicate_groups;
  end if;
end $$;

create or replace view logistica.v_logistica_items_catalog as
select
  li.id as logistica_item_id,
  li.catalog_item_id,
  li.company_id,
  li.sku,
  li.name,
  li.description,
  li.item_type,
  ci.item_kind as catalog_item_kind,
  ci.is_stockable,
  ci.is_purchasable,
  ci.is_service,
  ci.is_expense,
  ci.is_returnable,
  li.tracks_lot,
  li.tracks_serial,
  li.tracks_expiration,
  cc.name as category_name,
  li.is_active
from logistica.items li
left join public.catalog_items ci on ci.id = li.catalog_item_id
left join public.catalog_categories cc on cc.id = ci.category_id;

create or replace function logistica.create_logistica_item_from_catalog(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_catalog_item_id uuid;
  v_min_stock numeric(14,3);
  v_logistics_unit text;
  v_overrides jsonb;
  v_item logistica.items%rowtype;
  v_catalog_item public.catalog_items%rowtype;
  v_existing_count integer;
  v_item_type text;
  v_item_name text;
  v_item_description text;
  v_item_unit text;
  v_item_min_stock numeric(14,3);
  v_item_is_returnable boolean;
  v_item_tracks_lot boolean;
  v_item_tracks_serial boolean;
  v_item_tracks_expiration boolean;
  v_item_is_active boolean;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_catalog_item_id := nullif(btrim(coalesce(p_payload->>'catalog_item_id', '')), '')::uuid;
  v_min_stock := coalesce((p_payload->>'min_stock')::numeric, 0);
  v_logistics_unit := nullif(btrim(coalesce(p_payload->>'logistics_unit', '')), '');
  v_overrides := coalesce(p_payload->'overrides', '{}'::jsonb);

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if v_catalog_item_id is null then
    raise exception 'catalog_item_id es obligatorio';
  end if;

  if not public.has_company_access(v_company_id) then
    raise exception 'forbidden';
  end if;

  if not public.has_module_access(v_company_id, 'logistica') then
    raise exception 'module access required';
  end if;

  if not (
    public.is_owner(v_company_id)
    or public.has_role(v_company_id, 'ADMIN_LOGISTICA', 'logistica')
  ) then
    raise exception 'insufficient role';
  end if;

  select *
    into v_catalog_item
  from public.catalog_items ci
  where ci.id = v_catalog_item_id
    and ci.company_id = v_company_id
    and coalesce(ci.is_active, true) = true;

  if not found then
    raise exception 'catalog_item invalid';
  end if;

  if coalesce(v_catalog_item.is_stockable, false) is not true then
    raise exception 'catalog_item must be stockable';
  end if;

  if v_catalog_item.item_kind not in ('physical', 'tool', 'equipment') then
    raise exception 'catalog_item kind not compatible with logistica';
  end if;

  select count(*)
    into v_existing_count
  from logistica.items li
  where li.company_id = v_company_id
    and li.catalog_item_id = v_catalog_item_id;

  if v_existing_count > 0 then
    raise exception 'catalog_item already linked to a logistica item';
  end if;

  v_item_type := case v_catalog_item.item_kind
    when 'physical' then 'consumable'
    when 'tool' then 'tool'
    when 'equipment' then 'equipment'
    else 'consumable'
  end;

  v_item_name := coalesce(nullif(btrim(coalesce(v_overrides->>'name', '')), ''), v_catalog_item.name);
  v_item_description := coalesce(nullif(btrim(coalesce(v_overrides->>'description', '')), ''), v_catalog_item.description);
  v_item_unit := coalesce(nullif(btrim(coalesce(v_overrides->>'unit', '')), ''), v_logistics_unit, v_catalog_item.unit, 'UN');
  v_item_min_stock := coalesce(nullif(btrim(coalesce(v_overrides->>'min_stock', '')), '')::numeric, v_min_stock, 0);
  v_item_is_returnable := coalesce(nullif(btrim(coalesce(v_overrides->>'is_returnable', '')), '')::boolean, v_catalog_item.is_returnable, false);
  v_item_tracks_lot := coalesce(nullif(btrim(coalesce(v_overrides->>'tracks_lot', '')), '')::boolean, v_catalog_item.tracks_lot, false);
  v_item_tracks_serial := coalesce(nullif(btrim(coalesce(v_overrides->>'tracks_serial', '')), '')::boolean, v_catalog_item.tracks_serial, false);
  v_item_tracks_expiration := coalesce(nullif(btrim(coalesce(v_overrides->>'tracks_expiration', '')), '')::boolean, v_catalog_item.tracks_expiration, false);
  v_item_is_active := coalesce(nullif(btrim(coalesce(v_overrides->>'is_active', '')), '')::boolean, true);

  insert into logistica.items (
    company_id,
    sku,
    name,
    description,
    item_type,
    category_id,
    unit,
    tracks_serial,
    tracks_lot,
    tracks_expiration,
    is_returnable,
    min_stock,
    is_active,
    catalog_item_id,
    created_by,
    updated_by
  ) values (
    v_company_id,
    v_catalog_item.sku,
    v_item_name,
    v_item_description,
    v_item_type,
    null,
    v_item_unit,
    v_item_tracks_serial,
    v_item_tracks_lot,
    v_item_tracks_expiration,
    v_item_is_returnable,
    v_item_min_stock,
    v_item_is_active,
    v_catalog_item.id,
    v_user_id,
    v_user_id
  ) returning * into v_item;

  return jsonb_build_object(
    'success', true,
    'logistica_item_id', v_item.id
  );
end;
$$;

grant execute on function logistica.create_logistica_item_from_catalog(jsonb) to authenticated;
