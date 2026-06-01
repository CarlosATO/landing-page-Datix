-- Move frontend audit responsibility into backend RPCs that already own the write.

CREATE OR REPLACE FUNCTION pharmacy.upsert_branch_price_config(
  p_company_id uuid,
  p_product_id uuid,
  p_warehouse_id uuid,
  p_use_local_price boolean,
  p_override_sale_price numeric DEFAULT NULL,
  p_override_margin_percent numeric DEFAULT NULL,
  p_active boolean DEFAULT true
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
DECLARE
  v_row pharmacy.product_prices%ROWTYPE;
BEGIN
  IF p_company_id IS NULL OR p_product_id IS NULL OR p_warehouse_id IS NULL THEN
    RAISE EXCEPTION 'Parámetros inválidos para la configuración de precios';
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
    p_company_id,
    p_product_id,
    p_warehouse_id,
    COALESCE(p_override_sale_price, 0),
    p_override_sale_price,
    p_override_margin_percent,
    COALESCE(p_use_local_price, false),
    COALESCE(p_active, true),
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

  PERFORM pharmacy.log_audit_event(
    'PRODUCT_PRICE_UPDATED',
    'Precio de producto actualizado',
    jsonb_build_object(
      'product_id', p_product_id,
      'warehouse_id', p_warehouse_id,
      'amount', COALESCE(p_override_sale_price, 0),
      'use_local_price', COALESCE(p_use_local_price, false),
      'override_margin_percent', p_override_margin_percent
    )
  );

  RETURN jsonb_build_object(
    'id', v_row.id,
    'company_id', v_row.company_id,
    'product_id', v_row.product_id,
    'warehouse_id', v_row.warehouse_id,
    'price_sale', v_row.price_sale,
    'override_sale_price', v_row.override_sale_price,
    'override_margin_percent', v_row.override_margin_percent,
    'use_local_price', v_row.use_local_price,
    'active', v_row.active,
    'created_at', v_row.created_at,
    'updated_at', v_row.updated_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION pharmacy.create_prescription_with_items(
  p_company_id uuid DEFAULT NULL,
  p_diagnosis text DEFAULT NULL,
  p_doctor_id uuid DEFAULT NULL,
  p_folio_electronico text DEFAULT NULL,
  p_issue_date date DEFAULT NULL,
  p_items jsonb DEFAULT '[]'::jsonb,
  p_notes text DEFAULT NULL,
  p_patient_id uuid DEFAULT NULL,
  p_prescriber_name text DEFAULT NULL,
  p_prescriber_rut text DEFAULT NULL,
  p_valid_until date DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
DECLARE
  v_user_id uuid;
  v_company_id uuid;
  v_prescription_id uuid;
  v_item jsonb;
  v_product_id uuid;
  v_quantity numeric;
  v_dosage_instructions text;
  v_prescription_type text;
BEGIN
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado';
  END IF;

  SELECT company_id
  INTO v_company_id
  FROM public.company_users
  WHERE user_id = v_user_id
  LIMIT 1;

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Usuario sin empresa asociada';
  END IF;

  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'La receta no contiene medicamentos';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pharmacy.patients
    WHERE id = p_patient_id
      AND company_id = v_company_id
  ) THEN
    RAISE EXCEPTION 'Paciente no pertenece a la empresa';
  END IF;

  v_prescription_type := pharmacy.derive_prescription_type_from_items(p_items);

  INSERT INTO pharmacy.prescriptions (
    company_id,
    patient_id,
    folio_electronico,
    prescriber_rut,
    prescriber_name,
    institution_name,
    status,
    prescription_type,
    created_by
  )
  VALUES (
    v_company_id,
    p_patient_id,
    p_folio_electronico,
    p_prescriber_rut,
    p_prescriber_name,
    p_notes,
    'PENDING',
    v_prescription_type,
    v_user_id
  )
  RETURNING id INTO v_prescription_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_product_id := COALESCE(
      NULLIF(v_item->>'product_id', '')::uuid,
      NULLIF(v_item->>'id', '')::uuid
    );

    v_quantity := COALESCE(
      NULLIF(v_item->>'quantity_prescribed', '')::numeric,
      NULLIF(v_item->>'quantity', '')::numeric,
      1
    );

    v_dosage_instructions := COALESCE(
      v_item->>'dosage_instructions',
      v_item->>'indications',
      ''
    );

    IF v_product_id IS NULL THEN
      RAISE EXCEPTION 'Producto inválido en receta';
    END IF;

    IF v_quantity <= 0 THEN
      RAISE EXCEPTION 'Cantidad inválida en receta';
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pharmacy.products
      WHERE id = v_product_id
        AND company_id = v_company_id
    ) THEN
      RAISE EXCEPTION 'Producto no pertenece a la empresa';
    END IF;

    INSERT INTO pharmacy.prescription_items (
      prescription_id,
      product_id,
      quantity_prescribed,
      quantity_dispensed,
      dosage_instructions
    )
    VALUES (
      v_prescription_id,
      v_product_id,
      v_quantity,
      0,
      v_dosage_instructions
    );
  END LOOP;

  PERFORM pharmacy.recalculate_prescription_type(v_prescription_id);

  PERFORM pharmacy.log_audit_event(
    'PRESCRIPTION_CREATED',
    'Receta creada',
    jsonb_build_object(
      'prescription_id', v_prescription_id,
      'status', 'PENDING',
      'patient_id', p_patient_id,
      'items', p_items
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'prescription_id', v_prescription_id,
    'prescription_type', v_prescription_type
  );
END;
$$;

CREATE OR REPLACE FUNCTION pharmacy.process_pharmacy_sale(
  p_warehouse_id uuid,
  p_total_amount numeric,
  p_payment_method text,
  p_document_number text,
  p_patient_id uuid DEFAULT NULL,
  p_prescription_id uuid DEFAULT NULL,
  p_items jsonb DEFAULT '[]'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
DECLARE
  v_user_id uuid;
  v_company_id uuid;
  v_session_id uuid;
  v_sale_id uuid;
  v_item jsonb;
  v_product_id uuid;
  v_quantity numeric;
  v_unit_price numeric;
  v_item_prescription_id uuid;
  v_remaining numeric;
  v_qty_to_deduct numeric;
  v_batch record;
  v_balance_after numeric;
  v_sale_condition text;
  v_product_prescription_type text;
  v_is_controlled boolean;
  v_prescription_status text;
  v_prescription_type text;
  v_prescription_patient_id uuid;
  v_qty_prescribed numeric;
  v_qty_dispensed numeric;
  v_qty_pending numeric;
  v_prescription_id uuid;
BEGIN
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado';
  END IF;

  SELECT company_id
  INTO v_company_id
  FROM public.company_users
  WHERE user_id = v_user_id
  LIMIT 1;

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Usuario sin empresa asociada';
  END IF;

  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'La venta no contiene productos';
  END IF;

  SELECT id
  INTO v_session_id
  FROM pharmacy.pos_sessions
  WHERE company_id = v_company_id
    AND user_id = v_user_id
    AND warehouse_id = p_warehouse_id
    AND status = 'OPEN'
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_session_id IS NULL THEN
    RAISE EXCEPTION 'Debes abrir caja antes de vender';
  END IF;

  INSERT INTO pharmacy.sales (
    company_id,
    user_id,
    session_id,
    patient_id,
    total_amount,
    payment_method,
    document_number
  )
  VALUES (
    v_company_id,
    v_user_id,
    v_session_id,
    p_patient_id,
    p_total_amount,
    COALESCE(p_payment_method, 'CASH'),
    COALESCE(p_document_number, 'TICKET-' || extract(epoch from now())::bigint)
  )
  RETURNING id INTO v_sale_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_product_id := COALESCE(
      NULLIF(v_item->>'product_id', '')::uuid,
      NULLIF(v_item->>'id', '')::uuid
    );

    v_item_prescription_id := COALESCE(
      NULLIF(v_item->>'prescription_id', '')::uuid,
      p_prescription_id
    );

    v_quantity := COALESCE((v_item->>'quantity')::numeric, 0);

    v_unit_price := COALESCE(
      NULLIF(v_item->>'unit_price', '')::numeric,
      NULLIF(v_item->>'price_sale', '')::numeric,
      0
    );

    IF v_product_id IS NULL THEN
      RAISE EXCEPTION 'Producto inválido en carrito';
    END IF;

    IF v_quantity <= 0 THEN
      RAISE EXCEPTION 'Cantidad inválida para producto %', v_product_id;
    END IF;

    SELECT
      upper(coalesce(sale_condition, 'VD')),
      upper(coalesce(prescription_type, 'VENTA_LIBRE')),
      coalesce(is_controlled, false)
    INTO
      v_sale_condition,
      v_product_prescription_type,
      v_is_controlled
    FROM pharmacy.products
    WHERE id = v_product_id
      AND company_id = v_company_id;

    IF v_sale_condition IS NULL THEN
      RAISE EXCEPTION 'Producto no encontrado o no pertenece a la empresa';
    END IF;

    IF v_is_controlled = true
       OR v_sale_condition IN ('R', 'RR', 'RCH')
       OR v_product_prescription_type IN ('RECETA_SIMPLE', 'RECETA_RETENIDA', 'RECETA_CHEQUE')
    THEN
      IF v_item_prescription_id IS NULL THEN
        RAISE EXCEPTION 'El producto requiere receta médica válida';
      END IF;

      SELECT
        status,
        upper(coalesce(prescription_type, 'RECETA_SIMPLE')),
        patient_id
      INTO
        v_prescription_status,
        v_prescription_type,
        v_prescription_patient_id
      FROM pharmacy.prescriptions
      WHERE id = v_item_prescription_id
        AND company_id = v_company_id
      FOR UPDATE;

      IF v_prescription_status IS NULL THEN
        RAISE EXCEPTION 'Receta no encontrada';
      END IF;

      IF v_prescription_status NOT IN ('PENDING', 'PARTIAL') THEN
        RAISE EXCEPTION 'La receta no está disponible para despacho';
      END IF;

      IF p_patient_id IS NOT NULL AND v_prescription_patient_id <> p_patient_id THEN
        RAISE EXCEPTION 'La receta no pertenece al paciente seleccionado';
      END IF;

      IF v_sale_condition = 'RR' AND v_prescription_type <> 'RECETA_RETENIDA' THEN
        RAISE EXCEPTION 'Este producto requiere receta retenida';
      END IF;

      IF v_sale_condition = 'RCH' AND v_prescription_type <> 'RECETA_CHEQUE' THEN
        RAISE EXCEPTION 'Este producto requiere receta cheque';
      END IF;

      IF v_product_prescription_type = 'RECETA_RETENIDA' AND v_prescription_type <> 'RECETA_RETENIDA' THEN
        RAISE EXCEPTION 'Este producto requiere receta retenida';
      END IF;

      IF v_product_prescription_type = 'RECETA_CHEQUE' AND v_prescription_type <> 'RECETA_CHEQUE' THEN
        RAISE EXCEPTION 'Este producto requiere receta cheque';
      END IF;

      SELECT
        quantity_prescribed,
        coalesce(quantity_dispensed, 0)
      INTO
        v_qty_prescribed,
        v_qty_dispensed
      FROM pharmacy.prescription_items
      WHERE prescription_id = v_item_prescription_id
        AND product_id = v_product_id
      FOR UPDATE;

      IF v_qty_prescribed IS NULL THEN
        RAISE EXCEPTION 'El producto no está incluido en la receta';
      END IF;

      v_qty_pending := v_qty_prescribed - v_qty_dispensed;

      IF v_qty_pending <= 0 THEN
        RAISE EXCEPTION 'El producto ya fue completamente despachado en esta receta';
      END IF;

      IF v_quantity > v_qty_pending THEN
        RAISE EXCEPTION 'La cantidad vendida supera la cantidad pendiente de la receta';
      END IF;
    END IF;

    v_remaining := v_quantity;

    FOR v_batch IN
      SELECT
        b.id,
        b.product_id,
        b.batch_number,
        b.current_quantity,
        b.location_id,
        b.expiry_date
      FROM pharmacy.inventory_batches b
      JOIN pharmacy.locations l ON l.id = b.location_id
      WHERE b.company_id = v_company_id
        AND b.product_id = v_product_id
        AND b.current_quantity > 0
        AND l.company_id = v_company_id
        AND l.warehouse_id = p_warehouse_id
        AND upper(l.location_type) <> 'QUARANTINE'
      ORDER BY
        CASE WHEN upper(l.location_type) = 'SALES' THEN 0 ELSE 1 END,
        b.expiry_date ASC
      FOR UPDATE OF b
    LOOP
      EXIT WHEN v_remaining <= 0;

      v_qty_to_deduct := LEAST(v_remaining, v_batch.current_quantity);

      UPDATE pharmacy.inventory_batches
      SET current_quantity = current_quantity - v_qty_to_deduct
      WHERE id = v_batch.id
        AND company_id = v_company_id;

      INSERT INTO pharmacy.sale_items (
        company_id,
        sale_id,
        product_id,
        batch_id,
        quantity,
        unit_price,
        subtotal,
        prescription_id
      )
      VALUES (
        v_company_id,
        v_sale_id,
        v_product_id,
        v_batch.id,
        v_qty_to_deduct,
        v_unit_price,
        v_qty_to_deduct * v_unit_price,
        v_item_prescription_id
      );

      SELECT coalesce(sum(current_quantity), 0)
      INTO v_balance_after
      FROM pharmacy.inventory_batches
      WHERE company_id = v_company_id
        AND product_id = v_product_id
        AND location_id = v_batch.location_id;

      INSERT INTO pharmacy.inventory_movements (
        company_id,
        product_id,
        batch_id,
        batch_number,
        from_location_id,
        movement_type,
        quantity,
        balance_after,
        reference_folio,
        created_by
      )
      VALUES (
        v_company_id,
        v_product_id,
        v_batch.id,
        v_batch.batch_number,
        v_batch.location_id,
        'SALE',
        -abs(v_qty_to_deduct),
        v_balance_after,
        COALESCE(p_document_number, 'VENTA_POS'),
        v_user_id
      );

      v_remaining := v_remaining - v_qty_to_deduct;
    END LOOP;

    IF v_remaining > 0 THEN
      RAISE EXCEPTION 'Stock insuficiente para el producto %. Faltan % unidades.', v_product_id, v_remaining;
    END IF;

    IF v_item_prescription_id IS NOT NULL THEN
      UPDATE pharmacy.prescription_items
      SET quantity_dispensed = coalesce(quantity_dispensed, 0) + v_quantity
      WHERE prescription_id = v_item_prescription_id
        AND product_id = v_product_id;
    END IF;
  END LOOP;

  UPDATE pharmacy.prescriptions p
  SET status = CASE
    WHEN totals.total_dispensed <= 0 THEN 'PENDING'
    WHEN totals.total_dispensed < totals.total_prescribed THEN 'PARTIAL'
    ELSE 'DISPENSED'
  END
  FROM (
    SELECT
      pi.prescription_id,
      SUM(pi.quantity_prescribed) AS total_prescribed,
      SUM(coalesce(pi.quantity_dispensed, 0)) AS total_dispensed
    FROM pharmacy.prescription_items pi
    WHERE pi.prescription_id IN (
      SELECT DISTINCT coalesce(
        NULLIF(item->>'prescription_id', '')::uuid,
        p_prescription_id
      )
      FROM jsonb_array_elements(p_items) item
      WHERE coalesce(
        NULLIF(item->>'prescription_id', ''),
        p_prescription_id::text
      ) IS NOT NULL
    )
    GROUP BY pi.prescription_id
  ) totals
  WHERE p.id = totals.prescription_id
    AND p.company_id = v_company_id;

  PERFORM pharmacy.log_audit_event(
    'SALE_COMPLETED',
    'Venta POS exitosa',
    jsonb_build_object(
      'sale_id', v_sale_id,
      'warehouse_id', p_warehouse_id,
      'session_id', v_session_id,
      'operator_id', v_user_id,
      'amount', COALESCE(p_total_amount, 0),
      'payment_method', COALESCE(p_payment_method, 'CASH'),
      'items', p_items
    )
  );

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_items) item
    WHERE coalesce(NULLIF(item->>'prescription_id', ''), p_prescription_id::text) IS NOT NULL
  ) THEN
    PERFORM pharmacy.log_audit_event(
      'SALE_WITH_PRESCRIPTION',
      'Venta POS con receta',
      jsonb_build_object(
        'sale_id', v_sale_id,
        'warehouse_id', p_warehouse_id,
        'session_id', v_session_id,
        'operator_id', v_user_id,
        'amount', COALESCE(p_total_amount, 0),
        'payment_method', COALESCE(p_payment_method, 'CASH'),
        'items', p_items
      )
    );
  END IF;

  FOR v_prescription_id IN
    SELECT DISTINCT coalesce(
      NULLIF(item->>'prescription_id', '')::uuid,
      p_prescription_id
    )
    FROM jsonb_array_elements(p_items) item
    WHERE coalesce(
      NULLIF(item->>'prescription_id', ''),
      p_prescription_id::text
    ) IS NOT NULL
  LOOP
    SELECT status
    INTO v_prescription_status
    FROM pharmacy.prescriptions
    WHERE id = v_prescription_id
      AND company_id = v_company_id;

    IF v_prescription_status IN ('PARTIAL', 'DISPENSED') THEN
      PERFORM pharmacy.log_audit_event(
        CASE WHEN v_prescription_status = 'PARTIAL' THEN 'PRESCRIPTION_PARTIAL' ELSE 'PRESCRIPTION_DISPENSED' END,
        CASE WHEN v_prescription_status = 'PARTIAL' THEN 'Receta dispensada parcialmente' ELSE 'Receta dispensada' END,
        jsonb_build_object(
          'sale_id', v_sale_id,
          'prescription_id', v_prescription_id,
          'warehouse_id', p_warehouse_id,
          'session_id', v_session_id,
          'operator_id', v_user_id
        )
      );
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'sale_id', v_sale_id,
    'session_id', v_session_id,
    'company_id', v_company_id,
    'success', true
  );
END;
$$;
