-- Hardening for bulk catalog import validation.

CREATE OR REPLACE FUNCTION pharmacy.import_products_bulk(p_items jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
declare
  v_user_id uuid;
  v_company_id uuid;
  v_item jsonb;
  v_product_id uuid;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_row_index integer := 0;
  v_name text;
  v_dci text;
  v_laboratory text;
  v_concentration text;
  v_presentation text;
  v_barcode text;
  v_sku text;
  v_sale_condition text;
  v_prescription_type text;
  v_is_controlled boolean;
  v_is_bioequivalent boolean;
  v_min_stock numeric;
  v_price_sale numeric;
  v_seen_barcodes text[] := '{}'::text[];
  v_seen_skus text[] := '{}'::text[];
  v_seen_composites text[] := '{}'::text[];
  v_composite_key text;
  v_raw_boolean text;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Usuario no autenticado';
  end if;

  v_company_id := pharmacy.get_my_company_id();
  if v_company_id is null then
    raise exception 'Empresa no encontrada';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'Formato inválido para importación masiva';
  end if;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_row_index := v_row_index + 1;
    v_product_id := null;

    begin
      v_name := upper(trim(coalesce(v_item->>'nombre', '')));
      v_dci := upper(trim(coalesce(v_item->>'dci', '')));
      v_laboratory := upper(trim(coalesce(v_item->>'laboratorio', '')));
      v_concentration := upper(trim(coalesce(v_item->>'concentracion', '')));
      v_presentation := upper(trim(coalesce(v_item->>'forma_farmaceutica', '')));
      v_barcode := nullif(trim(coalesce(v_item->>'barcode', '')), '');
      v_sku := nullif(upper(trim(coalesce(v_item->>'sku', ''))), '');
      v_min_stock := coalesce(nullif(v_item->>'stock_minimo', '')::numeric, 0);
      v_price_sale := coalesce(nullif(v_item->>'precio_venta', '')::numeric, 0);

      if v_name = '' then
        raise exception 'Nombre obligatorio';
      end if;

      if v_dci = '' then
        raise exception 'DCI obligatorio';
      end if;

      v_sale_condition := upper(trim(coalesce(v_item->>'sale_condition', '')));
      if v_sale_condition not in ('VD', 'R', 'RR', 'RCH') then
        raise exception 'sale_condition inválido';
      end if;

      v_prescription_type := upper(trim(coalesce(v_item->>'prescription_type', '')));
      if v_prescription_type = '' then
        v_prescription_type := case v_sale_condition
          when 'VD' then 'VENTA_LIBRE'
          when 'R' then 'RECETA_SIMPLE'
          when 'RR' then 'RECETA_RETENIDA'
          when 'RCH' then 'RECETA_CHEQUE'
        end;
      end if;

      if v_prescription_type not in ('VENTA_LIBRE', 'RECETA_SIMPLE', 'RECETA_RETENIDA', 'RECETA_CHEQUE') then
        raise exception 'prescription_type inválido';
      end if;

      v_raw_boolean := lower(trim(coalesce(v_item->>'is_controlled', 'false')));
      if v_raw_boolean not in ('true', 'false', '') then
        raise exception 'is_controlled inválido';
      end if;
      v_is_controlled := coalesce(nullif(v_raw_boolean, ''), 'false')::boolean;

      v_raw_boolean := lower(trim(coalesce(v_item->>'bioequivalente', 'false')));
      if v_raw_boolean not in ('true', 'false', '') then
        raise exception 'bioequivalente inválido';
      end if;
      v_is_bioequivalent := coalesce(nullif(v_raw_boolean, ''), 'false')::boolean;

      if v_min_stock < 0 then
        raise exception 'stock_minimo debe ser >= 0';
      end if;

      if v_price_sale < 0 then
        raise exception 'precio_venta debe ser >= 0';
      end if;

      if v_barcode is not null then
        if v_barcode = any(v_seen_barcodes) then
          raise exception 'barcode duplicado en archivo';
        end if;
        v_seen_barcodes := array_append(v_seen_barcodes, v_barcode);
      end if;

      if v_sku is not null then
        if v_sku = any(v_seen_skus) then
          raise exception 'sku duplicado en archivo';
        end if;
        v_seen_skus := array_append(v_seen_skus, v_sku);
      end if;

      v_composite_key := v_name || '|' || v_dci || '|' || coalesce(v_concentration, '');
      if v_composite_key = any(v_seen_composites) then
        raise exception 'nombre+dci+concentracion duplicado en archivo';
      end if;
      v_seen_composites := array_append(v_seen_composites, v_composite_key);

      if v_barcode is not null then
        select id into v_product_id
        from pharmacy.products
        where company_id = v_company_id
          and barcode = v_barcode
        limit 1;
      end if;

      if v_product_id is null and v_sku is not null then
        select id into v_product_id
        from pharmacy.products
        where company_id = v_company_id
          and sku = v_sku
        limit 1;
      end if;

      if v_product_id is null then
        select id into v_product_id
        from pharmacy.products
        where company_id = v_company_id
          and upper(name) = v_name
          and upper(dci) = v_dci
          and upper(coalesce(concentration, '')) = coalesce(v_concentration, '')
        limit 1;
      end if;

      if v_product_id is null then
        insert into pharmacy.products (
          company_id,
          sku,
          barcode,
          name,
          dci,
          laboratory_name,
          concentration,
          presentation,
          sale_condition,
          prescription_type,
          is_controlled,
          is_bioequivalent,
          min_stock,
          price_sale,
          unit_price,
          registro_sanitario,
          created_by
        ) values (
          v_company_id,
          v_sku,
          v_barcode,
          v_name,
          v_dci,
          nullif(v_laboratory, ''),
          nullif(v_concentration, ''),
          nullif(v_presentation, ''),
          v_sale_condition,
          v_prescription_type,
          v_is_controlled,
          v_is_bioequivalent,
          v_min_stock,
          v_price_sale,
          v_price_sale,
          coalesce(nullif(upper(trim(coalesce(v_item->>'registro_sanitario', ''))), ''), 'PENDIENTE'),
          v_user_id
        );

        v_inserted := v_inserted + 1;
      else
        update pharmacy.products
        set sku = coalesce(v_sku, sku),
            barcode = coalesce(v_barcode, barcode),
            name = v_name,
            dci = v_dci,
            laboratory_name = nullif(v_laboratory, ''),
            concentration = nullif(v_concentration, ''),
            presentation = nullif(v_presentation, ''),
            sale_condition = v_sale_condition,
            prescription_type = v_prescription_type,
            is_controlled = v_is_controlled,
            is_bioequivalent = v_is_bioequivalent,
            min_stock = v_min_stock,
            price_sale = v_price_sale,
            unit_price = v_price_sale,
            updated_by = v_user_id,
            updated_at = now()
        where id = v_product_id
          and company_id = v_company_id;

        v_updated := v_updated + 1;
      end if;
    exception when others then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'row', v_row_index,
        'message', sqlerrm,
        'nombre', coalesce(v_item->>'nombre', null),
        'dci', coalesce(v_item->>'dci', null),
        'barcode', coalesce(v_item->>'barcode', null),
        'sku', coalesce(v_item->>'sku', null)
      ));
    end;
  end loop;

  return jsonb_build_object(
    'inserted', v_inserted,
    'updated', v_updated,
    'errors', v_errors
  );
end;
$$;

GRANT EXECUTE ON FUNCTION pharmacy.import_products_bulk(jsonb) TO authenticated;
