-- Traspasos Internos / Liberación de Cuarentena / Reserva intersucursal transaccional.

CREATE OR REPLACE FUNCTION pharmacy.process_internal_transfer(
  p_transfer_data jsonb,
  p_items jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
DECLARE
  v_company_id uuid := pharmacy.get_my_company_id();
  v_user_id uuid := auth.uid();
  v_source_warehouse_id uuid;
  v_dest_warehouse_id uuid;
  v_source_location_id uuid;
  v_dest_location_id uuid;
  v_source_location record;
  v_dest_location record;
  v_source_batch record;
  v_dest_batch record;
  v_request_id uuid;
  v_request_folio text;
  v_item jsonb;
  v_source_batch_id uuid;
  v_product_id uuid;
  v_batch_number text;
  v_expiry_date date;
  v_notes text;
  v_qty numeric;
  v_source_qty numeric;
  v_source_new_qty numeric;
  v_dest_new_qty numeric;
  v_dest_batch_id uuid;
  v_dest_batch_current numeric;
  v_is_interwarehouse boolean;
  v_source_type text;
  v_dest_type text;
  v_processed_qty numeric := 0;
  v_item_count integer := 0;
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Usuario sin empresa asociada';
  END IF;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado';
  END IF;

  IF p_transfer_data IS NULL OR jsonb_typeof(p_transfer_data) <> 'object' THEN
    RAISE EXCEPTION 'Los datos del traspaso son inválidos.';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'No hay lotes para procesar.';
  END IF;

  v_source_warehouse_id := NULLIF(BTRIM(COALESCE(p_transfer_data->>'source_warehouse_id', '')), '')::uuid;
  v_dest_warehouse_id := NULLIF(BTRIM(COALESCE(p_transfer_data->>'dest_warehouse_id', '')), '')::uuid;
  v_source_location_id := COALESCE(
    NULLIF(BTRIM(COALESCE(p_transfer_data->>'source_location_id', '')), '')::uuid,
    NULLIF(BTRIM(COALESCE(p_transfer_data->>'source_zone_id', '')), '')::uuid
  );
  v_dest_location_id := COALESCE(
    NULLIF(BTRIM(COALESCE(p_transfer_data->>'dest_location_id', '')), '')::uuid,
    NULLIF(BTRIM(COALESCE(p_transfer_data->>'dest_zone_id', '')), '')::uuid
  );
  v_notes := NULLIF(BTRIM(COALESCE(p_transfer_data->>'notes', '')), '');

  IF v_source_warehouse_id IS NULL OR v_dest_warehouse_id IS NULL THEN
    RAISE EXCEPTION 'Debe indicar sucursal origen y destino.';
  END IF;

  IF v_source_location_id IS NULL OR v_dest_location_id IS NULL THEN
    RAISE EXCEPTION 'Debe indicar ubicación origen y destino.';
  END IF;

  v_is_interwarehouse := v_source_warehouse_id <> v_dest_warehouse_id;

  SELECT l.*
    INTO v_source_location
  FROM pharmacy.locations l
  WHERE l.id = v_source_location_id
    AND l.company_id = v_company_id
    AND l.warehouse_id = v_source_warehouse_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La ubicación origen no existe en la sucursal indicada.';
  END IF;

  SELECT l.*
    INTO v_dest_location
  FROM pharmacy.locations l
  WHERE l.id = v_dest_location_id
    AND l.company_id = v_company_id
    AND l.warehouse_id = v_dest_warehouse_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La ubicación destino no existe en la sucursal indicada.';
  END IF;

  v_source_type := UPPER(COALESCE(v_source_location.location_type, ''));
  v_dest_type := UPPER(COALESCE(v_dest_location.location_type, ''));

  IF v_source_location_id = v_dest_location_id THEN
    RAISE EXCEPTION 'La ubicación origen y destino no pueden ser la misma.';
  END IF;

  IF NOT v_is_interwarehouse AND v_source_type = 'QUARANTINE' AND v_dest_type NOT IN ('STORAGE', 'SALES') THEN
    RAISE EXCEPTION 'Desde cuarentena solo se puede liberar a STORAGE o SALES.';
  END IF;

  IF v_is_interwarehouse THEN
    INSERT INTO pharmacy.transfer_requests (
      company_id,
      source_warehouse_id,
      destination_warehouse_id,
      status,
      requested_by,
      notes
    )
    VALUES (
      v_company_id,
      v_source_warehouse_id,
      v_dest_warehouse_id,
      'PENDING',
      v_user_id,
      v_notes
    )
    RETURNING id, folio INTO v_request_id, v_request_folio;
  END IF;

  FOR v_item IN
    SELECT value
    FROM jsonb_array_elements(p_items) AS value
    ORDER BY COALESCE(NULLIF(value->>'batch_id', ''), '')
  LOOP
    v_item_count := v_item_count + 1;

    v_source_batch_id := NULLIF(BTRIM(COALESCE(v_item->>'batch_id', '')), '')::uuid;
    v_product_id := NULLIF(BTRIM(COALESCE(v_item->>'product_id', '')), '')::uuid;
    v_qty := COALESCE((v_item->>'transfer_quantity')::numeric, (v_item->>'quantity')::numeric, 0);
    v_batch_number := NULLIF(BTRIM(COALESCE(v_item->>'batch_number', '')), '');
    v_expiry_date := NULLIF(BTRIM(COALESCE(v_item->>'expiry_date', '')), '')::date;

    IF v_source_batch_id IS NULL OR v_product_id IS NULL THEN
      RAISE EXCEPTION 'Ítem de traspaso inválido.';
    END IF;

    IF v_qty <= 0 THEN
      RAISE EXCEPTION 'La cantidad a mover debe ser mayor a cero.';
    END IF;

    SELECT b.*
      INTO v_source_batch
    FROM pharmacy.inventory_batches b
    WHERE b.id = v_source_batch_id
      AND b.company_id = v_company_id
      AND b.product_id = v_product_id
      AND b.location_id = v_source_location_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'El lote origen no existe o no pertenece a la ubicación seleccionada.';
    END IF;

    v_source_qty := COALESCE(v_source_batch.current_quantity, 0);

    IF v_qty > v_source_qty THEN
      RAISE EXCEPTION 'La cantidad solicitada supera el stock disponible del lote %.', COALESCE(v_source_batch.batch_number, v_batch_number);
    END IF;

    v_source_new_qty := v_source_qty - v_qty;

    UPDATE pharmacy.inventory_batches
       SET current_quantity = v_source_new_qty
     WHERE id = v_source_batch.id;

    IF v_is_interwarehouse THEN
      INSERT INTO pharmacy.transfer_request_items (
        company_id,
        transfer_request_id,
        product_id,
        batch_id,
        source_location_id,
        destination_location_id,
        quantity,
        status,
        received_quantity
      )
      VALUES (
        v_company_id,
        v_request_id,
        v_product_id,
        v_source_batch.id,
        v_source_location_id,
        v_dest_location_id,
        v_qty,
        'PENDING',
        0
      );

      INSERT INTO pharmacy.inventory_movements (
        company_id,
        product_id,
        batch_id,
        batch_number,
        from_location_id,
        to_location_id,
        movement_type,
        quantity,
        notes,
        created_by,
        source_location_id,
        destination_location_id,
        reference_folio,
        balance_after
      )
      VALUES (
        v_company_id,
        v_product_id,
        v_source_batch.id,
        COALESCE(v_source_batch.batch_number, v_batch_number),
        v_source_location_id,
        NULL,
        'OUTBOUND_TRANSFER',
        -ABS(v_qty),
        COALESCE(v_notes, 'Reserva intersucursal') || ' - ' || COALESCE(v_request_folio, 'TR-PENDING'),
        v_user_id,
        v_source_location_id,
        v_dest_location_id,
        COALESCE(v_request_folio, 'TR-PENDING'),
        v_source_new_qty
      );
    ELSE
      SELECT b.id, b.current_quantity
        INTO v_dest_batch_id, v_dest_batch_current
      FROM pharmacy.inventory_batches b
      WHERE b.company_id = v_company_id
        AND b.product_id = v_product_id
        AND b.location_id = v_dest_location_id
        AND b.batch_number = v_source_batch.batch_number
        AND b.expiry_date = v_source_batch.expiry_date
      FOR UPDATE;

      IF FOUND THEN
        v_dest_new_qty := COALESCE(v_dest_batch_current, 0) + v_qty;
        UPDATE pharmacy.inventory_batches
           SET current_quantity = v_dest_new_qty
         WHERE id = v_dest_batch_id;
      ELSE
        INSERT INTO pharmacy.inventory_batches (
          company_id,
          product_id,
          po_id,
          location_id,
          batch_number,
          expiry_date,
          initial_quantity,
          current_quantity
        )
        VALUES (
          v_company_id,
          v_product_id,
          v_source_batch.po_id,
          v_dest_location_id,
          v_source_batch.batch_number,
          v_source_batch.expiry_date,
          v_qty,
          v_qty
        )
        RETURNING id, current_quantity INTO v_dest_batch_id, v_dest_batch_current;

        v_dest_new_qty := v_dest_batch_current;
      END IF;

      INSERT INTO pharmacy.inventory_movements (
        company_id,
        product_id,
        batch_id,
        batch_number,
        from_location_id,
        to_location_id,
        movement_type,
        quantity,
        notes,
        created_by,
        source_location_id,
        destination_location_id,
        reference_folio,
        balance_after
      )
      VALUES (
        v_company_id,
        v_product_id,
        v_source_batch.id,
        v_source_batch.batch_number,
        v_source_location_id,
        v_dest_location_id,
        'INTERNAL_TRANSFER',
        -ABS(v_qty),
        COALESCE(v_notes, 'Acomodo interno') || ' - salida',
        v_user_id,
        v_source_location_id,
        v_dest_location_id,
        COALESCE(v_request_folio, 'TR-INTERNAL'),
        v_source_new_qty
      );

      INSERT INTO pharmacy.inventory_movements (
        company_id,
        product_id,
        batch_id,
        batch_number,
        from_location_id,
        to_location_id,
        movement_type,
        quantity,
        notes,
        created_by,
        source_location_id,
        destination_location_id,
        reference_folio,
        balance_after
      )
      VALUES (
        v_company_id,
        v_product_id,
        v_dest_batch_id,
        COALESCE(v_source_batch.batch_number, v_batch_number),
        v_source_location_id,
        v_dest_location_id,
        'INTERNAL_TRANSFER',
        ABS(v_qty),
        COALESCE(v_notes, 'Acomodo interno') || ' - entrada',
        v_user_id,
        v_source_location_id,
        v_dest_location_id,
        COALESCE(v_request_folio, 'TR-INTERNAL'),
        v_dest_new_qty
      );
    END IF;

    v_processed_qty := v_processed_qty + v_qty;
  END LOOP;

  IF v_is_interwarehouse THEN
    PERFORM pharmacy.log_audit_event(
      'TRANSFER_CREATED',
      'Reserva intersucursal generada transaccionalmente',
      jsonb_build_object(
        'transfer_request_id', v_request_id,
        'folio', v_request_folio,
        'source_warehouse_id', v_source_warehouse_id,
        'destination_warehouse_id', v_dest_warehouse_id,
        'source_location_id', v_source_location_id,
        'destination_location_id', v_dest_location_id,
        'quantity', v_processed_qty,
        'items_count', v_item_count,
        'notes', v_notes
      )
    );

    RETURN jsonb_build_object(
      'type', 'RESERVA',
      'message', 'Reserva intersucursal creada correctamente.',
      'transfer_request_id', v_request_id,
      'folio', v_request_folio,
      'quantity', v_processed_qty,
      'items_count', v_item_count,
      'generated_at', NOW()
    );
  END IF;

  PERFORM pharmacy.log_audit_event(
    'INTERNAL_TRANSFER_COMPLETED',
    'Acomodo interno / liberación de cuarentena ejecutada transaccionalmente',
    jsonb_build_object(
      'source_warehouse_id', v_source_warehouse_id,
      'destination_warehouse_id', v_dest_warehouse_id,
      'source_location_id', v_source_location_id,
      'destination_location_id', v_dest_location_id,
      'quantity', v_processed_qty,
      'items_count', v_item_count,
      'notes', v_notes,
      'source_location_type', v_source_type,
      'destination_location_type', v_dest_type
    )
  );

  RETURN jsonb_build_object(
    'type', 'ACOMODO',
    'message', CASE
      WHEN v_source_type = 'QUARANTINE' THEN 'Liberación desde cuarentena finalizada correctamente.'
      ELSE 'Acomodo interno finalizado correctamente.'
    END,
    'quantity', v_processed_qty,
    'items_count', v_item_count,
    'generated_at', NOW()
  );
END;
$$;

ALTER FUNCTION pharmacy.process_internal_transfer(jsonb, jsonb) OWNER TO postgres;

GRANT EXECUTE ON FUNCTION pharmacy.process_internal_transfer(jsonb, jsonb) TO authenticated;
