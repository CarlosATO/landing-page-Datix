create or replace function public.normalize_catalog_item_kind(p_value text)
returns text
language sql
immutable
set search_path = pg_catalog, public
as $$
  select case lower(btrim(coalesce(p_value, '')))
    when 'material' then 'material'
    when 'physical' then 'material'
    when 'consumable' then 'material'
    when 'fisico' then 'material'
    when 'tool' then 'tool'
    when 'herramienta' then 'tool'
    when 'equipment' then 'equipment'
    when 'equipo' then 'equipment'
    when 'service' then 'service'
    when 'expense' then 'expense'
    when 'other' then 'other'
    else null
  end;
$$;

create or replace function public.search_similar_catalog_items(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, logistica
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_sku text;
  v_barcode text;
  v_name text;
  v_name_norm text;
  v_barcode_norm text;
  v_items jsonb := '[]'::jsonb;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_sku := nullif(upper(btrim(coalesce(p_payload->>'sku', ''))), '');
  v_barcode := nullif(btrim(coalesce(p_payload->>'barcode', '')), '');
  v_name := nullif(btrim(coalesce(p_payload->>'name', '')), '');
  v_name_norm := public.normalize_catalog_text(v_name);
  v_barcode_norm := public.normalize_catalog_text(v_barcode);

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if not exists (
    select 1 from public.company_users cu
    where cu.company_id = v_company_id and cu.user_id = v_user_id
  ) then
    raise exception 'forbidden';
  end if;

  select coalesce(jsonb_agg(to_jsonb(i) order by i.match_score desc, i.name asc), '[]'::jsonb)
    into v_items
  from (
    select
      ci.id as catalog_item_id,
      li.id as logistica_item_id,
      ci.company_id,
      ci.category_id,
      cc.name as category_name,
      ci.sku,
      ci.barcode,
      ci.name,
      ci.description,
      ci.observation,
      ci.brand,
      ci.model,
      public.normalize_catalog_item_kind(ci.item_kind) as item_kind,
      ci.unit,
      ci.is_stockable,
      ci.is_purchasable,
      ci.is_service,
      ci.is_expense,
      ci.is_returnable,
      ci.tracks_lot,
      ci.tracks_serial,
      ci.tracks_expiration,
      ci.default_cost,
      ci.image_path,
      ci.image_mime_type,
      ci.image_size_bytes,
      ci.image_updated_at,
      ci.is_active as catalog_is_active,
      (li.id is not null) as logistica_enabled,
      coalesce(li.is_active, false) as logistica_is_active,
      li.unit as logistics_unit,
      li.min_stock,
      case when li.item_type = 'consumable' then 'material' else li.item_type end as item_type,
      case
        when v_sku is not null and upper(ci.sku) = v_sku then 1.0
        when v_barcode_norm is not null and public.normalize_catalog_text(ci.barcode) = v_barcode_norm then 0.99
        when v_name_norm is not null and public.normalize_catalog_text(ci.name) = v_name_norm then 0.98
        when v_name_norm is not null and public.normalize_catalog_text(ci.name) like v_name_norm || '%' then 0.85
        when v_name_norm is not null and v_name_norm like public.normalize_catalog_text(ci.name) || '%' then 0.82
        when v_name_norm is not null and (
          public.normalize_catalog_text(ci.name) like '%' || v_name_norm || '%'
          or v_name_norm like '%' || public.normalize_catalog_text(ci.name) || '%'
        ) then 0.75
        else 0.0
      end as match_score,
      case
        when v_sku is not null and upper(ci.sku) = v_sku then 'exact_sku'
        when v_barcode_norm is not null and public.normalize_catalog_text(ci.barcode) = v_barcode_norm then 'exact_barcode'
        when v_name_norm is not null and public.normalize_catalog_text(ci.name) = v_name_norm then 'exact_name'
        else 'similar'
      end as match_type
    from public.catalog_items ci
    left join public.catalog_categories cc on cc.id = ci.category_id
    left join logistica.items li
      on li.catalog_item_id = ci.id
     and li.company_id = v_company_id
    where ci.company_id = v_company_id
      and (
        (v_sku is not null and upper(ci.sku) = v_sku)
        or (v_barcode_norm is not null and public.normalize_catalog_text(ci.barcode) = v_barcode_norm)
        or (
          v_name_norm is not null and (
            public.normalize_catalog_text(ci.name) = v_name_norm
            or public.normalize_catalog_text(ci.name) like v_name_norm || '%'
            or v_name_norm like public.normalize_catalog_text(ci.name) || '%'
            or public.normalize_catalog_text(ci.name) like '%' || v_name_norm || '%'
            or v_name_norm like '%' || public.normalize_catalog_text(ci.name) || '%'
          )
        )
      )
    order by match_score desc, ci.name asc
  ) i;

  return jsonb_build_object('success', true, 'items', v_items);
end;
$$;

create or replace function public.list_logistica_materials(p_payload jsonb)
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
  v_item_kind := public.normalize_catalog_item_kind(p_payload->>'item_kind');
  v_is_active := coalesce((p_payload->>'is_active')::boolean, true);
  v_tracks_serial := nullif(p_payload->>'tracks_serial', '')::boolean;
  v_tracks_lot := nullif(p_payload->>'tracks_lot', '')::boolean;
  v_tracks_expiration := nullif(p_payload->>'tracks_expiration', '')::boolean;

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if p_payload ? 'item_kind' and nullif(btrim(coalesce(p_payload->>'item_kind', '')), '') is not null and v_item_kind is null then
    raise exception 'item_kind no permitido';
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
      case when li.item_type = 'consumable' then 'material' else li.item_type end as item_type,
      public.normalize_catalog_item_kind(ci.item_kind) as catalog_item_kind,
      ci.barcode,
      ci.brand,
      ci.model,
      ci.observation,
      ci.image_path,
      ci.image_mime_type,
      ci.image_size_bytes,
      ci.image_updated_at,
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
    left join public.catalog_items ci on ci.id = li.catalog_item_id
    left join public.catalog_categories cc on cc.id = ci.category_id
    where li.company_id = v_company_id
      and li.item_type in ('consumable', 'tool', 'equipment')
      and (
        v_search is null
        or upper(li.sku) like '%' || upper(v_search) || '%'
        or upper(li.name) like '%' || upper(v_search) || '%'
        or upper(coalesce(ci.barcode, '')) like '%' || upper(v_search) || '%'
        or upper(coalesce(ci.brand, '')) like '%' || upper(v_search) || '%'
        or upper(coalesce(ci.model, '')) like '%' || upper(v_search) || '%'
        or upper(coalesce(cc.name, '')) like '%' || upper(v_search) || '%'
      )
      and (v_item_kind is null or public.normalize_catalog_item_kind(coalesce(ci.item_kind, li.item_type)) = v_item_kind)
      and (v_tracks_serial is null or coalesce(li.tracks_serial, false) = v_tracks_serial)
      and (v_tracks_lot is null or coalesce(li.tracks_lot, false) = v_tracks_lot)
      and (v_tracks_expiration is null or coalesce(li.tracks_expiration, false) = v_tracks_expiration)
      and (not v_is_active or coalesce(li.is_active, true) = true)
    order by li.name asc
  ) i;

  return jsonb_build_object('success', true, 'materials', v_materials);
end;
$$;

create or replace function public.create_logistica_material(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, logistica
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_catalog_item_id uuid;
  v_catalog_item public.catalog_items%rowtype;
  v_category_id uuid;
  v_sku text;
  v_barcode text;
  v_name text;
  v_description text;
  v_observation text;
  v_brand text;
  v_model text;
  v_item_kind text;
  v_unit text := 'UN';
  v_default_cost numeric(14,4);
  v_min_stock numeric(14,3) := 0;
  v_is_returnable boolean := false;
  v_tracks_lot boolean := false;
  v_tracks_serial boolean := false;
  v_tracks_expiration boolean := false;
  v_confirm_similar boolean := false;
  v_image_path text;
  v_image_mime_type text;
  v_image_size_bytes integer;
  v_catalog_id uuid;
  v_link_result jsonb;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_catalog_item_id := nullif(btrim(coalesce(p_payload->>'catalog_item_id', '')), '')::uuid;
  v_category_id := nullif(btrim(coalesce(p_payload->>'category_id', '')), '')::uuid;
  v_sku := upper(btrim(coalesce(p_payload->>'sku', '')));
  v_barcode := nullif(upper(btrim(coalesce(p_payload->>'barcode', ''))), '');
  v_name := btrim(coalesce(p_payload->>'name', ''));
  v_description := nullif(btrim(coalesce(p_payload->>'description', '')), '');
  v_observation := nullif(btrim(coalesce(p_payload->>'observation', '')), '');
  v_brand := nullif(btrim(coalesce(p_payload->>'brand', '')), '');
  v_model := nullif(btrim(coalesce(p_payload->>'model', '')), '');
  v_item_kind := public.normalize_catalog_item_kind(coalesce(p_payload->>'item_kind', 'material'));
  v_unit := coalesce(nullif(btrim(coalesce(p_payload->>'unit', '')), ''), 'UN');
  v_default_cost := nullif(btrim(coalesce(p_payload->>'default_cost', '')), '')::numeric;
  v_min_stock := coalesce(nullif(btrim(coalesce(p_payload->>'min_stock', '')), '')::numeric, 0);
  v_is_returnable := coalesce((p_payload->>'is_returnable')::boolean, false);
  v_tracks_lot := coalesce((p_payload->>'tracks_lot')::boolean, false);
  v_tracks_serial := coalesce((p_payload->>'tracks_serial')::boolean, false);
  v_tracks_expiration := coalesce((p_payload->>'tracks_expiration')::boolean, false);
  v_confirm_similar := coalesce((p_payload->>'confirm_similar')::boolean, false);
  v_image_path := nullif(btrim(coalesce(p_payload->>'image_path', '')), '');
  v_image_mime_type := nullif(lower(btrim(coalesce(p_payload->>'image_mime_type', ''))), '');
  v_image_size_bytes := nullif(btrim(coalesce(p_payload->>'image_size_bytes', '')), '')::integer;

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if v_item_kind is null then
    raise exception 'item_kind inválido';
  end if;

  if v_item_kind not in ('material', 'tool', 'equipment') then
    raise exception 'Logística solo permite material, tool y equipment';
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
  ) then
    raise exception 'insufficient role';
  end if;

  if v_catalog_item_id is not null then
    select * into v_catalog_item
    from public.catalog_items ci
    where ci.id = v_catalog_item_id
      and ci.company_id = v_company_id;

    if not found then
      raise exception 'catalog item not found';
    end if;

    if exists (
      select 1
      from public.catalog_items ci
      where ci.company_id = v_company_id
        and ci.id <> v_catalog_item_id
        and upper(ci.sku) = v_sku
    ) then
      raise exception 'Ya existe un ítem con ese SKU';
    end if;

    if v_barcode is not null and exists (
      select 1
      from public.catalog_items ci
      where ci.company_id = v_company_id
        and ci.id <> v_catalog_item_id
        and upper(coalesce(ci.barcode, '')) = v_barcode
    ) then
      raise exception 'Ya existe un ítem con ese código de barras';
    end if;

    update public.catalog_items
       set sku = coalesce(nullif(v_sku, ''), sku),
           barcode = coalesce(v_barcode, barcode),
           name = coalesce(nullif(v_name, ''), name),
           description = coalesce(v_description, description),
           observation = coalesce(v_observation, observation),
           brand = coalesce(v_brand, brand),
           model = coalesce(v_model, model),
           item_kind = v_item_kind,
           unit = coalesce(v_unit, unit),
           category_id = coalesce(v_category_id, category_id),
           is_stockable = true,
           is_purchasable = true,
           is_service = false,
           is_expense = false,
           is_returnable = coalesce(v_is_returnable, is_returnable),
           tracks_lot = coalesce(v_tracks_lot, tracks_lot),
           tracks_serial = coalesce(v_tracks_serial, tracks_serial),
           tracks_expiration = coalesce(v_tracks_expiration, tracks_expiration),
           default_cost = coalesce(v_default_cost, default_cost),
           image_path = coalesce(v_image_path, image_path),
           image_mime_type = coalesce(v_image_mime_type, image_mime_type),
           image_size_bytes = coalesce(v_image_size_bytes, image_size_bytes),
           image_updated_at = case when v_image_path is not null then now() else image_updated_at end,
           updated_by = v_user_id
     where id = v_catalog_item_id
       and company_id = v_company_id;

    v_link_result := logistica.create_logistica_item_from_catalog(jsonb_build_object(
      'company_id', v_company_id,
      'catalog_item_id', v_catalog_item_id,
      'min_stock', v_min_stock,
      'logistics_unit', nullif(v_unit, 'UN'),
      'overrides', jsonb_build_object(
        'unit', v_unit,
        'description', v_description,
        'observation', v_observation,
        'brand', v_brand,
        'model', v_model,
        'barcode', v_barcode,
        'is_returnable', v_is_returnable,
        'tracks_lot', v_tracks_lot,
        'tracks_serial', v_tracks_serial,
        'tracks_expiration', v_tracks_expiration,
        'min_stock', v_min_stock,
        'is_active', true
      )
    ));

    return jsonb_build_object(
      'success', true,
      'catalog_item_id', v_catalog_item_id,
      'logistica_item_id', (v_link_result->>'logistica_item_id')::uuid
    );
  end if;

  if v_sku = '' then
    raise exception 'sku es obligatorio';
  end if;

  if v_name = '' then
    raise exception 'name es obligatorio';
  end if;

  if not coalesce((p_payload->>'is_stockable')::boolean, true) then
    raise exception 'El material logístico debe ser stockable';
  end if;

  if not coalesce((p_payload->>'is_purchasable')::boolean, true) then
    raise exception 'El material logístico debe ser comprable';
  end if;

  if v_category_id is not null then
    if not exists (
      select 1
      from public.catalog_categories cc
      where cc.id = v_category_id
        and cc.company_id = v_company_id
    ) then
      raise exception 'categoría inválida';
    end if;
  end if;

  if exists (
    select 1
    from public.catalog_items ci
    where ci.company_id = v_company_id
      and upper(ci.sku) = v_sku
  ) then
    raise exception 'Ya existe un ítem con ese SKU';
  end if;

  if v_barcode is not null and exists (
    select 1
    from public.catalog_items ci
    where ci.company_id = v_company_id
      and upper(coalesce(ci.barcode, '')) = v_barcode
  ) then
    raise exception 'Ya existe un ítem con ese código de barras';
  end if;

  if not v_confirm_similar and exists (
    select 1
    from public.catalog_items ci
    where ci.company_id = v_company_id
      and (
        public.normalize_catalog_text(ci.name) = public.normalize_catalog_text(v_name)
        or public.normalize_catalog_text(ci.name) like '%' || public.normalize_catalog_text(v_name) || '%'
        or public.normalize_catalog_text(v_name) like '%' || public.normalize_catalog_text(ci.name) || '%'
      )
  ) then
    raise exception 'similar catalog item found';
  end if;

  insert into public.catalog_items (
    company_id,
    category_id,
    sku,
    barcode,
    name,
    description,
    observation,
    brand,
    model,
    item_kind,
    unit,
    is_stockable,
    is_purchasable,
    is_service,
    is_expense,
    is_returnable,
    tracks_lot,
    tracks_serial,
    tracks_expiration,
    default_cost,
    image_path,
    image_mime_type,
    image_size_bytes,
    image_updated_at,
    metadata,
    is_active,
    created_by,
    updated_by
  ) values (
    v_company_id,
    v_category_id,
    v_sku,
    v_barcode,
    v_name,
    v_description,
    v_observation,
    v_brand,
    v_model,
    v_item_kind,
    v_unit,
    true,
    true,
    false,
    false,
    v_is_returnable,
    v_tracks_lot,
    v_tracks_serial,
    v_tracks_expiration,
    v_default_cost,
    v_image_path,
    v_image_mime_type,
    v_image_size_bytes,
    case when v_image_path is not null then now() else null end,
    jsonb_build_object('source', 'logistica', 'created_via', 'logistica_create_material'),
    true,
    v_user_id,
    v_user_id
  ) returning id into v_catalog_id;

  v_link_result := logistica.create_logistica_item_from_catalog(jsonb_build_object(
    'company_id', v_company_id,
    'catalog_item_id', v_catalog_id,
    'min_stock', v_min_stock,
    'logistics_unit', nullif(v_unit, 'UN'),
    'overrides', jsonb_build_object(
      'unit', v_unit,
      'description', v_description,
      'observation', v_observation,
      'brand', v_brand,
      'model', v_model,
      'barcode', v_barcode,
      'is_returnable', v_is_returnable,
      'tracks_lot', v_tracks_lot,
      'tracks_serial', v_tracks_serial,
      'tracks_expiration', v_tracks_expiration,
      'min_stock', v_min_stock,
      'is_active', true
    )
  ));

  return jsonb_build_object(
    'success', true,
    'catalog_item_id', v_catalog_id,
    'logistica_item_id', (v_link_result->>'logistica_item_id')::uuid
  );
end;
$$;

create or replace function public.update_logistica_material(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, logistica
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_logistica_item_id uuid;
  v_catalog_item_id uuid;
  v_logistica_item logistica.items%rowtype;
  v_catalog_item public.catalog_items%rowtype;
  v_category_id uuid;
  v_sku text;
  v_barcode text;
  v_name text;
  v_description text;
  v_observation text;
  v_brand text;
  v_model text;
  v_item_kind text;
  v_unit text;
  v_default_cost numeric(14,4);
  v_min_stock numeric(14,3);
  v_is_returnable boolean;
  v_tracks_lot boolean;
  v_tracks_serial boolean;
  v_tracks_expiration boolean;
  v_image_path text;
  v_image_mime_type text;
  v_image_size_bytes integer;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_logistica_item_id := nullif(btrim(coalesce(p_payload->>'logistica_item_id', p_payload->>'item_id', '')), '')::uuid;
  v_catalog_item_id := nullif(btrim(coalesce(p_payload->>'catalog_item_id', '')), '')::uuid;
  v_category_id := nullif(btrim(coalesce(p_payload->>'category_id', '')), '')::uuid;
  v_sku := upper(btrim(coalesce(p_payload->>'sku', '')));
  v_barcode := nullif(upper(btrim(coalesce(p_payload->>'barcode', ''))), '');
  v_name := btrim(coalesce(p_payload->>'name', ''));
  v_description := nullif(btrim(coalesce(p_payload->>'description', '')), '');
  v_observation := nullif(btrim(coalesce(p_payload->>'observation', '')), '');
  v_brand := nullif(btrim(coalesce(p_payload->>'brand', '')), '');
  v_model := nullif(btrim(coalesce(p_payload->>'model', '')), '');
  v_item_kind := public.normalize_catalog_item_kind(coalesce(p_payload->>'item_kind', 'material'));
  v_unit := nullif(btrim(coalesce(p_payload->>'unit', '')), '');
  v_default_cost := nullif(btrim(coalesce(p_payload->>'default_cost', '')), '')::numeric;
  v_min_stock := nullif(btrim(coalesce(p_payload->>'min_stock', '')), '')::numeric;
  v_is_returnable := nullif(btrim(coalesce(p_payload->>'is_returnable', '')), '')::boolean;
  v_tracks_lot := nullif(btrim(coalesce(p_payload->>'tracks_lot', '')), '')::boolean;
  v_tracks_serial := nullif(btrim(coalesce(p_payload->>'tracks_serial', '')), '')::boolean;
  v_tracks_expiration := nullif(btrim(coalesce(p_payload->>'tracks_expiration', '')), '')::boolean;
  v_image_path := nullif(btrim(coalesce(p_payload->>'image_path', '')), '');
  v_image_mime_type := nullif(lower(btrim(coalesce(p_payload->>'image_mime_type', ''))), '');
  v_image_size_bytes := nullif(btrim(coalesce(p_payload->>'image_size_bytes', '')), '')::integer;

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if v_item_kind is null then
    raise exception 'item_kind inválido';
  end if;

  if v_item_kind not in ('material', 'tool', 'equipment') then
    raise exception 'Logística solo permite material, tool y equipment';
  end if;

  if v_logistica_item_id is null then
    raise exception 'logistica_item_id es obligatorio';
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
  ) then
    raise exception 'insufficient role';
  end if;

  select * into v_logistica_item
  from logistica.items li
  where li.id = v_logistica_item_id
    and li.company_id = v_company_id;

  if not found then
    raise exception 'logistica item not found';
  end if;

  if v_catalog_item_id is null then
    v_catalog_item_id := v_logistica_item.catalog_item_id;
  end if;

  if v_catalog_item_id is not null then
    select * into v_catalog_item
    from public.catalog_items ci
    where ci.id = v_catalog_item_id
      and ci.company_id = v_company_id;

    if not found then
      raise exception 'catalog item not found';
    end if;

    if exists (
      select 1
      from public.catalog_items ci
      where ci.company_id = v_company_id
        and ci.id <> v_catalog_item_id
        and upper(ci.sku) = v_sku
    ) then
      raise exception 'Ya existe un ítem con ese SKU';
    end if;

    if v_barcode is not null and exists (
      select 1
      from public.catalog_items ci
      where ci.company_id = v_company_id
        and ci.id <> v_catalog_item_id
        and upper(coalesce(ci.barcode, '')) = v_barcode
    ) then
      raise exception 'Ya existe un ítem con ese código de barras';
    end if;

    update public.catalog_items
       set sku = coalesce(nullif(v_sku, ''), sku),
           barcode = coalesce(v_barcode, barcode),
           name = coalesce(nullif(v_name, ''), name),
           description = coalesce(v_description, description),
           observation = coalesce(v_observation, observation),
           brand = coalesce(v_brand, brand),
           model = coalesce(v_model, model),
           item_kind = v_item_kind,
           unit = coalesce(v_unit, unit),
           category_id = coalesce(v_category_id, category_id),
           is_stockable = true,
           is_purchasable = true,
           is_service = false,
           is_expense = false,
           is_returnable = coalesce(v_is_returnable, is_returnable),
           tracks_lot = coalesce(v_tracks_lot, tracks_lot),
           tracks_serial = coalesce(v_tracks_serial, tracks_serial),
           tracks_expiration = coalesce(v_tracks_expiration, tracks_expiration),
           default_cost = coalesce(v_default_cost, default_cost),
           image_path = coalesce(v_image_path, image_path),
           image_mime_type = coalesce(v_image_mime_type, image_mime_type),
           image_size_bytes = coalesce(v_image_size_bytes, image_size_bytes),
           image_updated_at = case when v_image_path is not null then now() else image_updated_at end,
           updated_by = v_user_id
     where id = v_catalog_item_id
       and company_id = v_company_id;
  end if;

  update logistica.items
     set sku = coalesce(nullif(v_sku, ''), sku),
         name = coalesce(nullif(v_name, ''), name),
         description = coalesce(v_description, description),
         item_type = case
           when v_item_kind = 'tool' then 'tool'
           when v_item_kind = 'equipment' then 'equipment'
           else 'consumable'
         end,
         unit = coalesce(v_unit, unit),
         tracks_serial = coalesce(v_tracks_serial, tracks_serial),
         tracks_lot = coalesce(v_tracks_lot, tracks_lot),
         tracks_expiration = coalesce(v_tracks_expiration, tracks_expiration),
         is_returnable = coalesce(v_is_returnable, is_returnable),
         min_stock = coalesce(v_min_stock, min_stock),
         is_active = coalesce((p_payload->>'is_active')::boolean, is_active),
         updated_by = v_user_id
   where id = v_logistica_item_id
     and company_id = v_company_id;

  return jsonb_build_object(
    'success', true,
    'logistica_item_id', v_logistica_item_id,
    'catalog_item_id', v_catalog_item_id
  );
end;
$$;

create or replace function public.update_catalog_item_image(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_catalog_item_id uuid;
  v_image_path text;
  v_image_mime_type text;
  v_image_size_bytes integer;
  v_catalog_item public.catalog_items%rowtype;
  v_expected_prefix text;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_catalog_item_id := nullif(btrim(coalesce(p_payload->>'catalog_item_id', '')), '')::uuid;
  v_image_path := nullif(btrim(coalesce(p_payload->>'image_path', '')), '');
  v_image_mime_type := lower(btrim(coalesce(p_payload->>'image_mime_type', '')));
  v_image_size_bytes := nullif(btrim(coalesce(p_payload->>'image_size_bytes', '')), '')::integer;

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if v_catalog_item_id is null then
    raise exception 'catalog_item_id es obligatorio';
  end if;

  if not exists (
    select 1 from public.company_users cu
    where cu.company_id = v_company_id and cu.user_id = v_user_id
  ) then
    raise exception 'forbidden';
  end if;

  if not (
    public.is_owner(v_company_id)
    or public.has_role(v_company_id, 'ADMIN_LOGISTICA', 'logistica')
    or public.has_role(v_company_id, 'ADMIN_ADQUISICIONES', 'adquisiciones')
  ) then
    raise exception 'insufficient role';
  end if;

  select * into v_catalog_item
  from public.catalog_items ci
  where ci.id = v_catalog_item_id
    and ci.company_id = v_company_id;

  if not found then
    raise exception 'catalog item not found';
  end if;

  v_expected_prefix := v_company_id::text || '/catalog_items/' || v_catalog_item_id::text || '/';

  if v_image_path is null or left(v_image_path, length(v_expected_prefix)) <> v_expected_prefix then
    raise exception 'image_path inválido';
  end if;

  if v_image_mime_type not in ('image/jpeg', 'image/png', 'image/webp') then
    raise exception 'image_mime_type no permitido';
  end if;

  if v_image_size_bytes is null or v_image_size_bytes <= 0 or v_image_size_bytes > 5242880 then
    raise exception 'image_size_bytes inválido';
  end if;

  update public.catalog_items
     set image_path = v_image_path,
         image_mime_type = v_image_mime_type,
         image_size_bytes = v_image_size_bytes,
         image_updated_at = now(),
         updated_by = v_user_id
   where id = v_catalog_item_id
     and company_id = v_company_id;

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
    v_company_id,
    v_user_id,
    'catalog_item_image_updated',
    'public',
    'catalog_items',
    v_catalog_item_id,
    jsonb_build_object('image_path', v_catalog_item.image_path, 'image_mime_type', v_catalog_item.image_mime_type, 'image_size_bytes', v_catalog_item.image_size_bytes),
    jsonb_build_object('image_path', v_image_path, 'image_mime_type', v_image_mime_type, 'image_size_bytes', v_image_size_bytes),
    jsonb_build_object('event', 'CATALOG_ITEM_IMAGE_UPDATED')
  );

  return jsonb_build_object('success', true, 'catalog_item_id', v_catalog_item_id, 'image_path', v_image_path);
end;
$$;

grant execute on function public.normalize_catalog_item_kind(text) to authenticated;
grant execute on function public.search_similar_catalog_items(jsonb) to authenticated;
grant execute on function public.list_logistica_materials(jsonb) to authenticated;
grant execute on function public.create_logistica_material(jsonb) to authenticated;
grant execute on function public.update_logistica_material(jsonb) to authenticated;
grant execute on function public.update_catalog_item_image(jsonb) to authenticated;
