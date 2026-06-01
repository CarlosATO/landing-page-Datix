create or replace function logistica.list_logistica_materials(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, logistica
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_search text;
  v_item_kind text;
  v_is_active boolean := true;
  v_tracks_serial boolean;
  v_tracks_lot boolean;
  v_tracks_expiration boolean;
  v_materials jsonb := '[]'::jsonb;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_search := nullif(btrim(coalesce(p_payload->>'search', '')), '');
  v_item_kind := nullif(lower(btrim(coalesce(p_payload->>'item_kind', ''))), '');
  v_is_active := coalesce((p_payload->>'is_active')::boolean, true);
  v_tracks_serial := nullif(p_payload->>'tracks_serial', '')::boolean;
  v_tracks_lot := nullif(p_payload->>'tracks_lot', '')::boolean;
  v_tracks_expiration := nullif(p_payload->>'tracks_expiration', '')::boolean;

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if not exists (
    select 1 from public.company_users cu
    where cu.company_id = v_company_id and cu.user_id = v_user_id
  ) then
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
    public.is_owner(v_company_id)
    or public.has_role(v_company_id, 'ADMIN_LOGISTICA', 'logistica')
    or public.has_role(v_company_id, 'OPERARIO_LOGISTICA', 'logistica')
  ) then
    raise exception 'insufficient role';
  end if;

  select coalesce(jsonb_agg(to_jsonb(i) order by i.name asc), '[]'::jsonb)
    into v_materials
  from (
    select
      li.id as logistica_item_id,
      li.catalog_item_id,
      li.company_id,
      li.sku,
      li.name,
      li.description,
      li.item_type,
      ci.item_kind as catalog_item_kind,
      ci.is_active as catalog_is_active,
      ci.default_cost,
      ci.default_tax_rate,
      ci.metadata as catalog_metadata,
      ci.unit as catalog_unit,
      ci.is_stockable,
      ci.is_purchasable,
      ci.is_service,
      ci.is_expense,
      ci.is_returnable,
      li.tracks_lot,
      li.tracks_serial,
      li.tracks_expiration,
      li.unit as logistics_unit,
      li.min_stock,
      li.is_active,
      cc.name as category_name,
      (li.catalog_item_id is not null) as catalog_linked
    from logistica.items li
    left join public.catalog_items ci
      on ci.id = li.catalog_item_id
     and ci.company_id = li.company_id
    left join public.catalog_categories cc on cc.id = ci.category_id
    where li.company_id = v_company_id
      and li.item_type in ('consumable', 'tool', 'equipment')
      and (
        v_search is null
        or upper(li.sku) like '%' || upper(v_search) || '%'
        or upper(li.name) like '%' || upper(v_search) || '%'
        or upper(coalesce(cc.name, '')) like '%' || upper(v_search) || '%'
      )
      and (v_item_kind is null or lower(coalesce(ci.item_kind, li.item_type)) = v_item_kind)
      and (v_tracks_serial is null or coalesce(li.tracks_serial, false) = v_tracks_serial)
      and (v_tracks_lot is null or coalesce(li.tracks_lot, false) = v_tracks_lot)
      and (v_tracks_expiration is null or coalesce(li.tracks_expiration, false) = v_tracks_expiration)
      and (not v_is_active or coalesce(li.is_active, true) = true)
    order by li.name asc
  ) i;

  return jsonb_build_object('success', true, 'materials', v_materials);
end;
$$;

create or replace function public.list_logistica_materials(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, logistica
as $$
begin
  return logistica.list_logistica_materials(p_payload);
end;
$$;

grant execute on function logistica.list_logistica_materials(jsonb) to authenticated;
grant execute on function public.list_logistica_materials(jsonb) to authenticated;
