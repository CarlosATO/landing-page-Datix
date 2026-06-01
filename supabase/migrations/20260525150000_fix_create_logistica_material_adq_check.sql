-- ============================================================
-- MIGRACIÓN: fix create_logistica_material — chequeo de adquisiciones
--
-- PROBLEMA:
--   public.has_module_access(company_id, 'adquisiciones') devuelve TRUE
--   para cualquier usuario OWNER, sin importar si la empresa tiene
--   Adquisiciones contratado o no. Esto bloqueaba create_logistica_material
--   incluso para empresas que SOLO tienen Logística contratado.
--
-- CAUSA RAÍZ:
--   has_module_access tiene la lógica:
--     when is_owner(company_id) then true
--   Lo que da acceso implícito a todos los módulos a los owners.
--   Esta lógica es correcta para control de acceso a datos (RLS),
--   pero NO es válida para determinar si un módulo está CONTRATADO.
--
-- CORRECCIÓN:
--   En create_logistica_material, reemplazar has_module_access por
--   una consulta directa y explícita a company_modules, filtrando
--   por company_id y status en ('active', 'trial').
--   Esta es la única fuente de verdad para módulos contratados.
-- ============================================================

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
  -- [FIX] Variable explícita para el check de Adquisiciones.
  -- NO usa has_module_access porque esa función retorna true para OWNER
  -- independientemente de los módulos contratados.
  v_adquisiciones_contracted boolean := false;
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

  -- [FIX] Consulta directa y explícita a company_modules.
  -- NO delegar en has_module_access porque retorna true para OWNER sin importar módulos contratados.
  -- La única fuente de verdad para "¿tiene adquisiciones contratado?" es esta tabla.
  select exists (
    select 1
    from public.company_modules cm
    where cm.company_id = v_company_id
      and lower(cm.module_key) = 'adquisiciones'
      and lower(cm.status) in ('active', 'trial')
  ) into v_adquisiciones_contracted;

  -- Solo bloquear creación nueva si la empresa tiene Adquisiciones contratado
  -- Y no se está vinculando un catalog_item existente.
  if v_adquisiciones_contracted and v_catalog_item_id is null then
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

    if not v_adquisiciones_contracted then
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

grant execute on function public.create_logistica_material(jsonb) to authenticated;
