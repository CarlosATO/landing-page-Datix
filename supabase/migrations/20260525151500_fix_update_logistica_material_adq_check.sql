-- ============================================================
-- MIGRACIÓN: fix update_logistica_material — chequeo de adquisiciones
--
-- PROBLEMA:
--   public.has_module_access(company_id, 'adquisiciones') devuelve TRUE
--   para cualquier usuario OWNER, independientemente de si la empresa tiene
--   el módulo realmente contratado en company_modules.
--   Esto provocaba que update_logistica_material bloqueara la edición de
--   campos del catálogo maestro a los owners de empresas que SOLO pagan
--   o usan Logística (lanzando excepciones de bloqueo de campos como SKU, 
--   barcode, name, etc.).
--
-- CAUSA RAÍZ:
--   La función de seguridad has_module_access tiene un atajo implícito
--   para el OWNER: "when public.is_owner(p_company_id) then true".
--   Esto es excelente para políticas RLS, pero erróneo para reglas de negocio.
--
-- CORRECCIÓN:
--   Reemplazar la asignación "v_adquisiciones_contracted := public.has_module_access(...)"
--   por una consulta directa y tenant-aware sobre public.company_modules,
--   validando estrictamente el estado del contrato ('active', 'trial') de Adquisiciones.
-- ============================================================

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
  v_adquisiciones_contracted boolean := false;
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

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  -- [FIX] Consulta directa a company_modules. 
  -- No delegar en has_module_access porque da true a los OWNERs automáticamente.
  select exists (
    select 1
    from public.company_modules cm
    where cm.company_id = v_company_id
      and lower(cm.module_key) = 'adquisiciones'
      and lower(cm.status) in ('active', 'trial')
  ) into v_adquisiciones_contracted;

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

grant execute on function public.update_logistica_material(jsonb) to authenticated;
