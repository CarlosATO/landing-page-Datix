-- Harden bulk branch price updates by validating warehouse scope per item.

CREATE OR REPLACE FUNCTION pharmacy.bulk_upsert_branch_prices(p_items jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
DECLARE
  v_company_id uuid := pharmacy.get_my_company_id();
  v_user_id uuid := auth.uid();
  v_item jsonb;
  v_row_index integer := 0;
  v_product_id uuid;
  v_warehouse_id uuid;
  v_use_local_price boolean;
  v_override_sale_price numeric;
  v_override_margin_percent numeric;
  v_active boolean;
  v_row pharmacy.product_prices%ROWTYPE;
  v_saved_count integer := 0;
  v_warehouse_scope uuid := NULL;
  v_product_ids uuid[] := '{}'::uuid[];
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Usuario sin empresa asociada';
  END IF;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'No hay precios para aplicar';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) AS value
  LOOP
    v_row_index := v_row_index + 1;

    v_product_id := NULLIF(BTRIM(COALESCE(v_item->>'product_id', '')), '')::uuid;
    v_warehouse_id := NULLIF(BTRIM(COALESCE(v_item->>'warehouse_id', '')), '')::uuid;
    v_use_local_price := COALESCE(NULLIF(BTRIM(COALESCE(v_item->>'use_local_price', '')), '')::boolean, true);
    v_override_sale_price := COALESCE(NULLIF(BTRIM(COALESCE(v_item->>'override_sale_price', '')), '')::numeric, 0);
    v_override_margin_percent := NULLIF(BTRIM(COALESCE(v_item->>'override_margin_percent', '')), '')::numeric;
    v_active := COALESCE(NULLIF(BTRIM(COALESCE(v_item->>'active', '')), '')::boolean, true);

    IF v_product_id IS NULL THEN
      RAISE EXCEPTION 'Producto inválido en el ítem %', v_row_index;
    END IF;

    IF v_warehouse_id IS NULL THEN
      RAISE EXCEPTION 'Local inválido en el ítem %', v_row_index;
    END IF;

    PERFORM 1
    FROM pharmacy.warehouses w
    WHERE w.id = v_warehouse_id
      AND w.company_id = v_company_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Warehouse inválido o no pertenece a la empresa en el ítem %', v_row_index;
    END IF;

    IF v_warehouse_scope IS NULL THEN
      v_warehouse_scope := v_warehouse_id;
    ELSIF v_warehouse_scope <> v_warehouse_id THEN
      RAISE EXCEPTION 'Todos los precios masivos deben pertenecer al mismo local';
    END IF;

    IF v_override_sale_price < 0 THEN
      RAISE EXCEPTION 'El precio debe ser mayor o igual a cero en el ítem %', v_row_index;
    END IF;

    IF v_override_margin_percent IS NOT NULL AND v_override_margin_percent < 0 THEN
      RAISE EXCEPTION 'El margen debe ser mayor o igual a cero en el ítem %', v_row_index;
    END IF;

    PERFORM 1
    FROM pharmacy.products p
    WHERE p.id = v_product_id
      AND p.company_id = v_company_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Producto no encontrado o no pertenece a la empresa en el ítem %', v_row_index;
    END IF;

    INSERT INTO pharmacy.product_prices (
      company_id,
      product_id,
      warehouse_id,
      price_sale,
      override_sale_price,
      override_margin_percent,
      use_local_price,
      active,
      updated_at,
      created_at
    )
    VALUES (
      v_company_id,
      v_product_id,
      v_warehouse_id,
      COALESCE(v_override_sale_price, 0),
      v_override_sale_price,
      v_override_margin_percent,
      COALESCE(v_use_local_price, false),
      COALESCE(v_active, true),
      now(),
      now()
    )
    ON CONFLICT (company_id, warehouse_id, product_id)
    DO UPDATE SET
      override_sale_price = EXCLUDED.override_sale_price,
      override_margin_percent = EXCLUDED.override_margin_percent,
      use_local_price = EXCLUDED.use_local_price,
      active = EXCLUDED.active,
      price_sale = EXCLUDED.price_sale,
      updated_at = now()
    RETURNING * INTO v_row;

    v_saved_count := v_saved_count + 1;
    v_product_ids := array_append(v_product_ids, v_row.product_id);
  END LOOP;

  PERFORM pharmacy.log_audit_event(
    'PRODUCT_PRICE_BULK_UPDATED',
    'Actualización masiva de precios por local',
    jsonb_build_object(
      'company_id', v_company_id,
      'warehouse_id', v_warehouse_scope,
      'updated_count', v_saved_count,
      'product_ids', to_jsonb(v_product_ids)
    )
  );

  RETURN jsonb_build_object(
    'updated_count', v_saved_count,
    'warehouse_id', v_warehouse_scope,
    'product_ids', to_jsonb(v_product_ids)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION pharmacy.bulk_upsert_branch_prices(jsonb) TO authenticated;
