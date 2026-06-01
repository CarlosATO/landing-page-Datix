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
      ci.unit as catalog_unit,
      coalesce(li.unit, ci.unit, 'UN') as logistics_unit,
      ci.is_stockable,
      ci.is_purchasable,
      ci.is_service,
      ci.is_expense,
      ci.is_returnable,
      ci.tracks_lot,
      ci.tracks_serial,
      ci.tracks_expiration,
      ci.default_tax_rate,
      ci.default_cost,
      ci.image_path,
      ci.image_mime_type,
      ci.image_size_bytes,
      ci.image_updated_at,
      ci.is_active as catalog_is_active,
      coalesce(li.is_active, coalesce(ci.is_active, true)) as is_active,
      coalesce(li.min_stock, 0) as min_stock,
      (li.id is not null) as logistica_configured,
      (li.id is not null) as logistica_enabled,
      case
        when public.normalize_catalog_item_kind(ci.item_kind) = 'tool' then 'tool'
        when public.normalize_catalog_item_kind(ci.item_kind) = 'equipment' then 'equipment'
        else 'material'
      end as item_type
    from public.catalog_items ci
    left join public.catalog_categories cc on cc.id = ci.category_id
    left join logistica.items li
      on li.catalog_item_id = ci.id
     and li.company_id = v_company_id
    where ci.company_id = v_company_id
      and public.normalize_catalog_item_kind(ci.item_kind) in ('material', 'tool', 'equipment')
      and coalesce(ci.is_service, false) = false
      and coalesce(ci.is_expense, false) = false
      and coalesce(ci.is_stockable, false) = true
      and (
        v_search is null
        or upper(ci.sku) like '%' || upper(v_search) || '%'
        or upper(coalesce(ci.barcode, '')) like '%' || upper(v_search) || '%'
        or upper(ci.name) like '%' || upper(v_search) || '%'
        or upper(coalesce(ci.brand, '')) like '%' || upper(v_search) || '%'
        or upper(coalesce(ci.model, '')) like '%' || upper(v_search) || '%'
        or upper(coalesce(cc.name, '')) like '%' || upper(v_search) || '%'
      )
      and (v_item_kind is null or public.normalize_catalog_item_kind(ci.item_kind) = v_item_kind)
      and (not v_is_active or coalesce(ci.is_active, true) = true)
      and (v_tracks_serial is null or coalesce(ci.tracks_serial, false) = v_tracks_serial)
      and (v_tracks_lot is null or coalesce(ci.tracks_lot, false) = v_tracks_lot)
      and (v_tracks_expiration is null or coalesce(ci.tracks_expiration, false) = v_tracks_expiration)
    order by ci.name asc
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

  if public.has_module_access(v_company_id, 'adquisiciones') and v_catalog_item_id is null then
    raise exception 'catalog managed by adquisiciones';
  end if;

  if v_item_kind is null or v_item_kind not in ('material', 'tool', 'equipment') then
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

    if not public.has_module_access(v_company_id, 'adquisiciones') then
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

      if not v_confirm_similar and exists (
        select 1
        from public.catalog_items ci
        where ci.company_id = v_company_id
          and ci.id <> v_catalog_item_id
          and (
            public.normalize_catalog_text(ci.name) = public.normalize_catalog_text(v_name)
            or public.normalize_catalog_text(ci.name) like '%' || public.normalize_catalog_text(v_name) || '%'
            or public.normalize_catalog_text(v_name) like '%' || public.normalize_catalog_text(ci.name) || '%'
          )
      ) then
        raise exception 'similar catalog item found';
      end if;

      update public.catalog_items
         set sku = coalesce(nullif(v_sku, ''), sku),
             barcode = coalesce(v_barcode, barcode),
             name = coalesce(nullif(v_name, ''), name),
             description = coalesce(v_description, description),
             observation = coalesce(v_observation, observation),
             brand = coalesce(v_brand, brand),
             model = coalesce(v_model, model),
            item_kind = case
              when v_item_kind = 'tool' then 'tool'
              when v_item_kind = 'equipment' then 'equipment'
              else 'physical'
            end,
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
    case
      when v_item_kind = 'tool' then 'tool'
      when v_item_kind = 'equipment' then 'equipment'
      else 'physical'
    end,
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
  v_adquisiciones_contracted boolean;
  v_catalog_item public.catalog_items%rowtype;
  v_logistica_item logistica.items%rowtype;
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
  v_category_id uuid;
  v_created_result jsonb;
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
  v_category_id := nullif(btrim(coalesce(p_payload->>'category_id', '')), '')::uuid;
  v_adquisiciones_contracted := public.has_module_access(v_company_id, 'adquisiciones');

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if v_item_kind is null or v_item_kind not in ('material', 'tool', 'equipment') then
    raise exception 'Logística solo permite material, tool y equipment';
  end if;

  if v_logistica_item_id is null and v_catalog_item_id is null then
    raise exception 'catalog_item_id es obligatorio';
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

  if v_logistica_item_id is not null then
    select * into v_logistica_item
    from logistica.items li
    where li.id = v_logistica_item_id
      and li.company_id = v_company_id;
  end if;

  if v_catalog_item_id is null and found then
    v_catalog_item_id := v_logistica_item.catalog_item_id;
  end if;

  if v_catalog_item_id is null then
    raise exception 'catalog item not found';
  end if;

  select * into v_catalog_item
  from public.catalog_items ci
  where ci.id = v_catalog_item_id
    and ci.company_id = v_company_id;

  if not found then
    raise exception 'catalog item not found';
  end if;

  if v_adquisiciones_contracted then
    if coalesce(nullif(v_sku, ''), v_catalog_item.sku) is distinct from v_catalog_item.sku then
      raise exception 'sku is managed from adquisiciones';
    end if;
    if coalesce(v_barcode, v_catalog_item.barcode) is distinct from v_catalog_item.barcode then
      raise exception 'barcode is managed from adquisiciones';
    end if;
    if coalesce(nullif(v_name, ''), v_catalog_item.name) is distinct from v_catalog_item.name then
      raise exception 'name is managed from adquisiciones';
    end if;
    if coalesce(v_description, v_catalog_item.description) is distinct from v_catalog_item.description then
      raise exception 'description is managed from adquisiciones';
    end if;
    if coalesce(v_observation, v_catalog_item.observation) is distinct from v_catalog_item.observation then
      raise exception 'observation is managed from adquisiciones';
    end if;
    if coalesce(v_brand, v_catalog_item.brand) is distinct from v_catalog_item.brand then
      raise exception 'brand is managed from adquisiciones';
    end if;
    if coalesce(v_model, v_catalog_item.model) is distinct from v_catalog_item.model then
      raise exception 'model is managed from adquisiciones';
    end if;
    if coalesce(v_category_id, v_catalog_item.category_id) is distinct from v_catalog_item.category_id then
      raise exception 'category is managed from adquisiciones';
    end if;
    if public.normalize_catalog_item_kind(coalesce(v_item_kind, v_catalog_item.item_kind)) is distinct from public.normalize_catalog_item_kind(v_catalog_item.item_kind) then
      raise exception 'item_kind is managed from adquisiciones';
    end if;
  end if;

  if not v_adquisiciones_contracted then
    update public.catalog_items
       set sku = coalesce(nullif(v_sku, ''), sku),
           barcode = coalesce(v_barcode, barcode),
           name = coalesce(nullif(v_name, ''), name),
           description = coalesce(v_description, description),
           observation = coalesce(v_observation, observation),
           brand = coalesce(v_brand, brand),
           model = coalesce(v_model, model),
             item_kind = case
               when v_item_kind = 'tool' then 'tool'
               when v_item_kind = 'equipment' then 'equipment'
               else 'physical'
             end,
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
           updated_by = v_user_id
     where id = v_catalog_item_id
       and company_id = v_company_id;
  end if;

  if v_logistica_item_id is null then
    if found and v_logistica_item.catalog_item_id = v_catalog_item_id then
      v_logistica_item_id := v_logistica_item.id;
    else
      v_created_result := logistica.create_logistica_item_from_catalog(jsonb_build_object(
        'company_id', v_company_id,
        'catalog_item_id', v_catalog_item_id,
        'min_stock', coalesce(v_min_stock, 0),
        'logistics_unit', nullif(coalesce(v_unit, v_catalog_item.unit), 'UN'),
        'overrides', jsonb_build_object(
          'unit', coalesce(v_unit, v_catalog_item.unit),
          'description', coalesce(v_description, v_catalog_item.description),
          'observation', coalesce(v_observation, v_catalog_item.observation),
          'brand', coalesce(v_brand, v_catalog_item.brand),
          'model', coalesce(v_model, v_catalog_item.model),
          'barcode', coalesce(v_barcode, v_catalog_item.barcode),
          'is_returnable', coalesce(v_is_returnable, v_catalog_item.is_returnable),
          'tracks_lot', coalesce(v_tracks_lot, v_catalog_item.tracks_lot),
          'tracks_serial', coalesce(v_tracks_serial, v_catalog_item.tracks_serial),
          'tracks_expiration', coalesce(v_tracks_expiration, v_catalog_item.tracks_expiration),
          'min_stock', coalesce(v_min_stock, 0),
          'is_active', coalesce((p_payload->>'is_active')::boolean, true)
        )
      ));

      v_logistica_item_id := nullif(v_created_result->>'logistica_item_id', '')::uuid;
    end if;
  end if;

  if v_logistica_item_id is null then
    raise exception 'logistica item not found';
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

  return jsonb_build_object('success', true, 'catalog_item_id', v_catalog_item_id, 'logistica_item_id', v_logistica_item_id);
end;
$$;

grant execute on function public.list_logistica_materials(jsonb) to authenticated;
grant execute on function public.create_logistica_material(jsonb) to authenticated;
grant execute on function public.update_logistica_material(jsonb) to authenticated;
