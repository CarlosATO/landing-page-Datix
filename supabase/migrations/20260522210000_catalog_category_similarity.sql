create or replace function public.normalize_catalog_text(p_value text)
returns text
language sql
immutable
set search_path = public
as $$
  select nullif(
    regexp_replace(
      regexp_replace(
        translate(
          lower(trim(coalesce(p_value, ''))),
          'áàäâãåÁÀÄÂÃÅéèëêÉÈËÊíìïîÍÌÏÎóòöôõÓÒÖÔÕúùüûÚÙÜÛñÑçÇ',
          'aaaaaaAAAAAAeeeeEEEEiiiiIIIIoooooOOOOOuuuuUUUUnNcC'
        ),
        '[^a-z0-9]+',
        ' ',
        'g'
      ),
      E'\\s+',
      ' ',
      'g'
    ),
    ''
  );
$$;

create or replace function public.search_similar_catalog_categories(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_company_id uuid;
  v_name text;
  v_code text;
  v_name_norm text;
  v_code_norm text;
  v_categories jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_name := nullif(btrim(coalesce(p_payload->>'name', '')), '');
  v_code := nullif(btrim(coalesce(p_payload->>'code', '')), '');
  v_name_norm := public.normalize_catalog_text(v_name);
  v_code_norm := public.normalize_catalog_text(v_code);

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if not public.has_company_access(v_company_id) then
    raise exception 'forbidden';
  end if;

  select coalesce(jsonb_agg(to_jsonb(c) order by c.similarity_score desc, c.name asc), '[]'::jsonb)
    into v_categories
  from (
    select
      cc.id,
      cc.company_id,
      cc.code,
      cc.name,
      cc.description,
      cc.category_type,
      cc.is_active,
      cc.created_at,
      cc.updated_at,
      public.normalize_catalog_text(cc.code) as normalized_code,
      public.normalize_catalog_text(cc.name) as normalized_name,
      case
        when v_code_norm is not null and public.normalize_catalog_text(cc.code) = v_code_norm then 1.0
        when v_name_norm is not null and public.normalize_catalog_text(cc.name) = v_name_norm then 0.98
        when v_name_norm is not null and public.normalize_catalog_text(cc.name) like v_name_norm || '%' then 0.85
        when v_name_norm is not null and v_name_norm like public.normalize_catalog_text(cc.name) || '%' then 0.82
        when v_name_norm is not null and (
          public.normalize_catalog_text(cc.name) like '%' || v_name_norm || '%'
          or v_name_norm like '%' || public.normalize_catalog_text(cc.name) || '%'
        ) then 0.75
        else 0.0
      end as similarity_score,
      case
        when v_code_norm is not null and public.normalize_catalog_text(cc.code) = v_code_norm then 'exact_code'
        when v_name_norm is not null and public.normalize_catalog_text(cc.name) = v_name_norm then 'exact_name'
        else 'similar'
      end as match_type
    from public.catalog_categories cc
    where cc.company_id = v_company_id
      and (
        v_name_norm is not null
        and (
          public.normalize_catalog_text(cc.name) = v_name_norm
          or public.normalize_catalog_text(cc.name) like v_name_norm || '%'
          or v_name_norm like public.normalize_catalog_text(cc.name) || '%'
          or public.normalize_catalog_text(cc.name) like '%' || v_name_norm || '%'
          or v_name_norm like '%' || public.normalize_catalog_text(cc.name) || '%'
        )
      or v_code_norm is not null
        and public.normalize_catalog_text(cc.code) = v_code_norm
      )
    order by similarity_score desc, cc.name asc
  ) c;

  return jsonb_build_object('success', true, 'categories', v_categories);
end;
$$;

create or replace function public.create_catalog_category(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_code text;
  v_name text;
  v_description text;
  v_category_type text := 'general';
  v_is_active boolean := true;
  v_confirm_similar boolean := false;
  v_category_id uuid;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_code := nullif(btrim(coalesce(p_payload->>'code', '')), '');
  v_name := nullif(btrim(coalesce(p_payload->>'name', '')), '');
  v_description := nullif(btrim(coalesce(p_payload->>'description', '')), '');
  v_category_type := lower(coalesce(nullif(btrim(coalesce(p_payload->>'category_type', '')), ''), 'general'));
  v_is_active := coalesce((p_payload->>'is_active')::boolean, true);
  v_confirm_similar := coalesce((p_payload->>'confirm_similar')::boolean, false);

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if v_name is null then
    raise exception 'name es obligatorio';
  end if;

  if not public.has_company_access(v_company_id) then
    raise exception 'forbidden';
  end if;

  if not (
    public.is_owner(v_company_id)
    or public.has_role(v_company_id, 'ADMIN_LOGISTICA', 'logistica')
    or public.has_role(v_company_id, 'ADMIN_ADQUISICIONES', 'adquisiciones')
    or public.has_role(v_company_id, 'ADMIN_CONSTRUCCION', 'construccion')
  ) then
    raise exception 'insufficient role';
  end if;

  v_code := upper(coalesce(v_code, regexp_replace(public.normalize_catalog_text(v_name), '\\s+', '_', 'g')));

  if exists (
    select 1
    from public.catalog_categories cc
    where cc.company_id = v_company_id
      and public.normalize_catalog_text(cc.code) = public.normalize_catalog_text(v_code)
  ) then
    raise exception 'Ya existe una categoría con ese código';
  end if;

  if exists (
    select 1
    from public.catalog_categories cc
    where cc.company_id = v_company_id
      and public.normalize_catalog_text(cc.name) = public.normalize_catalog_text(v_name)
  ) then
    raise exception 'Ya existe una categoría con ese nombre';
  end if;

  if not v_confirm_similar and exists (
    select 1
    from public.catalog_categories cc
    where cc.company_id = v_company_id
      and (
        public.normalize_catalog_text(cc.name) like '%' || public.normalize_catalog_text(v_name) || '%'
        or public.normalize_catalog_text(v_name) like '%' || public.normalize_catalog_text(cc.name) || '%'
      )
  ) then
    raise exception 'categoría similar encontrada';
  end if;

  insert into public.catalog_categories (
    company_id,
    code,
    name,
    description,
    category_type,
    is_active,
    created_by,
    updated_by
  ) values (
    v_company_id,
    v_code,
    v_name,
    v_description,
    v_category_type,
    v_is_active,
    v_user_id,
    v_user_id
  ) returning id into v_category_id;

  return jsonb_build_object('success', true, 'category_id', v_category_id);
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
  v_name text;
  v_name_norm text;
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
  v_name := nullif(btrim(coalesce(p_payload->>'name', '')), '');
  v_name_norm := public.normalize_catalog_text(v_name);

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
      ci.name,
      ci.description,
      ci.item_kind,
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
      ci.is_active as catalog_is_active,
      (li.id is not null) as logistica_enabled,
      coalesce(li.is_active, false) as logistica_is_active,
      li.unit as logistics_unit,
      li.min_stock,
      li.item_type,
      public.normalize_catalog_text(ci.sku) as normalized_sku,
      public.normalize_catalog_text(ci.name) as normalized_name,
      case
        when v_sku is not null and upper(ci.sku) = v_sku then 1.0
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

grant execute on function public.normalize_catalog_text(text) to authenticated;
grant execute on function public.search_similar_catalog_categories(jsonb) to authenticated;
grant execute on function public.create_catalog_category(jsonb) to authenticated;
grant execute on function public.search_similar_catalog_items(jsonb) to authenticated;
