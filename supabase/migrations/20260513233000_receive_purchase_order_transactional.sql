-- Recepción de OC transaccional para evitar inconsistencias parciales.

CREATE OR REPLACE FUNCTION pharmacy.receive_purchase_order_transactional(
  p_purchase_order_id uuid,
  p_warehouse_id uuid,
  p_receipt_data jsonb,
  p_batches jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
DECLARE
  v_company_id uuid := pharmacy.get_my_company_id();
  v_user_id uuid := auth.uid();
  v_purchase_order pharmacy.purchase_orders%ROWTYPE;
  v_receipt_id uuid;
  v_location_id uuid;
  v_receipt_supplier_id uuid;
  v_document_type text;
  v_document_number text;
  v_notes text;
  v_po_reference text;
  v_batch jsonb;
  v_po_item record;
  v_product record;
  v_po_item_id uuid;
  v_product_id uuid;
  v_batch_id uuid;
  v_entered_qty numeric;
  v_unit_cost numeric;
  v_conversion_factor numeric;
  v_sale_qty numeric;
  v_real_unit_cost numeric;
  v_pending_qty numeric;
  v_current_received numeric;
  v_old_stock numeric;
  v_old_avg_cost numeric;
  v_new_stock numeric;
  v_new_avg_cost numeric;
  v_new_status text;
  v_all_received boolean;
  v_total_purchase_qty numeric := 0;
  v_total_sale_qty numeric := 0;
  v_batches_count integer := 0;
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Usuario sin empresa asociada';
  END IF;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado';
  END IF;

  IF p_purchase_order_id IS NULL THEN
    RAISE EXCEPTION 'Debe indicar la orden de compra.';
  END IF;

  IF p_warehouse_id IS NULL THEN
    RAISE EXCEPTION 'Debe indicar la bodega de recepción.';
  END IF;

  IF p_receipt_data IS NULL OR jsonb_typeof(p_receipt_data) <> 'object' THEN
    RAISE EXCEPTION 'Los datos de recepción son inválidos.';
  END IF;

  IF p_batches IS NULL OR jsonb_typeof(p_batches) <> 'array' OR jsonb_array_length(p_batches) = 0 THEN
    RAISE EXCEPTION 'No hay lotes ingresados para recibir.';
  END IF;

  v_document_type := UPPER(BTRIM(COALESCE(p_receipt_data->>'document_type', '')));
  v_document_number := UPPER(BTRIM(COALESCE(p_receipt_data->>'document_number', '')));
  v_notes := NULLIF(BTRIM(COALESCE(p_receipt_data->>'notes', '')), '');

  IF v_document_type = '' THEN
    RAISE EXCEPTION 'Debe indicar el tipo de documento.';
  END IF;

  IF v_document_number = '' THEN
    RAISE EXCEPTION 'Debe indicar el número de documento.';
  END IF;

  IF v_document_type NOT IN ('GUIA_DESPACHO', 'FACTURA', 'BOLETA', 'AJUSTE') THEN
    RAISE EXCEPTION 'Tipo de documento inválido.';
  END IF;

  SELECT po.*
    INTO v_purchase_order
  FROM pharmacy.purchase_orders po
  WHERE po.id = p_purchase_order_id
    AND po.company_id = v_company_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La orden no existe en la compañía actual.';
  END IF;

  IF v_purchase_order.status IN ('CANCELLED', 'RECEIVED') THEN
    RAISE EXCEPTION 'La orden no puede recepcionarse en su estado actual.';
  END IF;

  IF v_purchase_order.status NOT IN ('PENDING', 'PARTIAL') THEN
    RAISE EXCEPTION 'Solo se pueden recibir órdenes en estado PENDING o PARTIAL.';
  END IF;

  PERFORM 1
  FROM pharmacy.purchase_order_items poi
  WHERE poi.po_id = p_purchase_order_id
  ORDER BY poi.id
  FOR UPDATE;

  v_po_reference := 'OC-' || LPAD(COALESCE(v_purchase_order.po_number, 0)::text, 5, '0');

  IF p_receipt_data ? 'supplier_id' AND BTRIM(COALESCE(p_receipt_data->>'supplier_id', '')) <> '' THEN
    v_receipt_supplier_id := (p_receipt_data->>'supplier_id')::uuid;
    IF v_receipt_supplier_id <> v_purchase_order.supplier_id THEN
      RAISE EXCEPTION 'El proveedor de la recepción no coincide con la orden.';
    END IF;
  ELSE
    v_receipt_supplier_id := v_purchase_order.supplier_id;
  END IF;

  SELECT l.id
    INTO v_location_id
  FROM pharmacy.locations l
  WHERE l.company_id = v_company_id
    AND l.warehouse_id = p_warehouse_id
    AND UPPER(l.location_type) = 'QUARANTINE'
    AND COALESCE(l.is_active, true) = true
  ORDER BY l.created_at ASC
  LIMIT 1;

  IF v_location_id IS NULL THEN
    RAISE EXCEPTION 'No se encontró la ubicación QUARANTINE para la bodega seleccionada.';
  END IF;

  INSERT INTO pharmacy.inventory_receipts (
    company_id,
    po_id,
    supplier_id,
    document_type,
    document_number,
    notes,
    created_by
  )
  VALUES (
    v_company_id,
    p_purchase_order_id,
    v_receipt_supplier_id,
    v_document_type,
    v_document_number,
    v_notes,
    v_user_id
  )
  RETURNING id INTO v_receipt_id;

  FOR v_batch IN SELECT value FROM jsonb_array_elements(p_batches)
  LOOP
    v_batches_count := v_batches_count + 1;

    v_po_item_id := NULLIF(BTRIM(COALESCE(v_batch->>'po_item_id', '')), '')::uuid;
    v_product_id := COALESCE(NULLIF(BTRIM(COALESCE(v_batch->>'product_id', '')), '')::uuid, NULL);
    v_entered_qty := COALESCE((v_batch->>'entered_quantity')::numeric, 0);
    v_unit_cost := COALESCE((v_batch->>'unit_cost')::numeric, 0);
    v_conversion_factor := COALESCE((v_batch->>'conversion_factor')::numeric, 0);

    IF v_po_item_id IS NULL THEN
      RAISE EXCEPTION 'Línea de OC inválida en recepción.';
    END IF;

    IF v_product_id IS NULL THEN
      RAISE EXCEPTION 'Producto inválido en recepción.';
    END IF;

    IF v_entered_qty <= 0 THEN
      RAISE EXCEPTION 'La cantidad ingresada debe ser mayor a cero.';
    END IF;

    IF v_conversion_factor <= 0 THEN
      RAISE EXCEPTION 'El factor de conversión debe ser mayor a cero.';
    END IF;

    IF BTRIM(COALESCE(v_batch->>'batch_number', '')) = '' THEN
      RAISE EXCEPTION 'El número de lote es obligatorio.';
    END IF;

    IF BTRIM(COALESCE(v_batch->>'expiry_date', '')) = '' THEN
      RAISE EXCEPTION 'La fecha de vencimiento es obligatoria.';
    END IF;

    IF v_unit_cost <= 0 THEN
      RAISE EXCEPTION 'El costo unitario de compra debe ser mayor a cero.';
    END IF;

    SELECT
      poi.id,
      poi.po_id,
      poi.product_id,
      poi.quantity,
      COALESCE(poi.quantity_received, 0) AS quantity_received,
      poi.unit_cost,
      COALESCE(poi.conversion_factor, 1) AS conversion_factor,
      p.stock_quantity,
      COALESCE(p.average_cost, 0) AS average_cost,
      COALESCE(p.last_cost, 0) AS last_cost
    INTO v_po_item
    FROM pharmacy.purchase_order_items poi
    JOIN pharmacy.products p
      ON p.id = poi.product_id
     AND p.company_id = v_company_id
    WHERE poi.id = v_po_item_id
      AND poi.po_id = p_purchase_order_id
      AND poi.product_id = v_product_id
    FOR UPDATE OF poi, p;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'La línea de OC no existe o no corresponde al producto indicado.';
    END IF;

    v_pending_qty := COALESCE(v_po_item.quantity, 0) - COALESCE(v_po_item.quantity_received, 0);

    IF v_entered_qty > v_pending_qty THEN
      RAISE EXCEPTION 'La cantidad a recibir supera la cantidad pendiente para el producto %.', v_product_id;
    END IF;

    IF ABS(v_unit_cost - COALESCE(v_po_item.unit_cost, 0)) > 0.0001 THEN
      RAISE EXCEPTION 'El costo informado no coincide con el costo de la orden para el producto %.', v_product_id;
    END IF;

    IF ABS(v_conversion_factor - COALESCE(v_po_item.conversion_factor, 1)) > 0.0001 THEN
      RAISE EXCEPTION 'El factor de conversión informado no coincide con la orden para el producto %.', v_product_id;
    END IF;

    v_sale_qty := v_entered_qty * v_conversion_factor;
    v_real_unit_cost := v_unit_cost / v_conversion_factor;

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
      p_purchase_order_id,
      v_location_id,
      BTRIM(v_batch->>'batch_number'),
      (v_batch->>'expiry_date')::date,
      v_sale_qty,
      v_sale_qty
    )
    RETURNING id INTO v_batch_id;

    SELECT
      COALESCE(p.stock_quantity, 0),
      COALESCE(p.average_cost, 0)
    INTO
      v_old_stock,
      v_old_avg_cost
    FROM pharmacy.products p
    WHERE p.id = v_product_id
      AND p.company_id = v_company_id
    FOR UPDATE;

    v_new_stock := COALESCE(v_old_stock, 0) + v_sale_qty;

    IF v_new_stock <= 0 THEN
      v_new_avg_cost := v_real_unit_cost;
    ELSIF COALESCE(v_old_stock, 0) <= 0 THEN
      v_new_avg_cost := v_real_unit_cost;
    ELSE
      v_new_avg_cost := ((COALESCE(v_old_stock, 0) * COALESCE(v_old_avg_cost, 0)) + (v_sale_qty * v_real_unit_cost)) / v_new_stock;
    END IF;

    UPDATE pharmacy.products
       SET stock_quantity = v_new_stock,
           last_cost = v_real_unit_cost,
           average_cost = v_new_avg_cost,
           updated_by = v_user_id,
           updated_at = NOW()
     WHERE id = v_product_id
       AND company_id = v_company_id;

    v_current_received := COALESCE(v_po_item.quantity_received, 0);

    UPDATE pharmacy.purchase_order_items
       SET quantity_received = v_current_received + v_entered_qty,
           updated_by = v_user_id
     WHERE id = v_po_item_id
       AND po_id = p_purchase_order_id
     RETURNING quantity_received INTO v_current_received;

    INSERT INTO pharmacy.inventory_movements (
      company_id,
      product_id,
      batch_id,
      batch_number,
      from_location_id,
      to_location_id,
      movement_type,
      quantity,
      unit_cost,
      notes,
      created_by,
      receipt_id,
      source_location_id,
      destination_location_id,
      reference_folio,
      balance_after
    )
    VALUES (
      v_company_id,
      v_product_id,
      v_batch_id,
      BTRIM(v_batch->>'batch_number'),
      NULL,
      v_location_id,
      'IN_PURCHASE',
      v_sale_qty,
      v_real_unit_cost,
      'Lote ' || BTRIM(v_batch->>'batch_number') || ' - ' || v_po_reference,
      v_user_id,
      v_receipt_id,
      NULL,
      v_location_id,
      v_po_reference,
      v_new_stock
    );

    v_total_purchase_qty := v_total_purchase_qty + v_entered_qty;
    v_total_sale_qty := v_total_sale_qty + v_sale_qty;
  END LOOP;

  SELECT BOOL_AND(COALESCE(quantity_received, 0) >= quantity)
    INTO v_all_received
  FROM pharmacy.purchase_order_items
  WHERE po_id = p_purchase_order_id;

  IF v_all_received IS NULL THEN
    RAISE EXCEPTION 'La orden no tiene líneas para recepcionar.';
  END IF;

  UPDATE pharmacy.purchase_orders
     SET status = CASE WHEN v_all_received THEN 'RECEIVED' ELSE 'PARTIAL' END,
         updated_by = v_user_id
   WHERE id = p_purchase_order_id
     AND company_id = v_company_id
   RETURNING status INTO v_new_status;

  PERFORM pharmacy.log_audit_event(
    'PURCHASE_ORDER_RECEIVED',
    'Recepción transaccional de orden de compra',
    jsonb_build_object(
      'purchase_order_id', p_purchase_order_id,
      'po_number', v_purchase_order.po_number,
      'receipt_id', v_receipt_id,
      'warehouse_id', p_warehouse_id,
      'document_type', v_document_type,
      'document_number', v_document_number,
      'status', v_new_status,
      'purchase_quantity', v_total_purchase_qty,
      'sale_quantity', v_total_sale_qty,
      'batch_count', v_batches_count
    )
  );

  RETURN jsonb_build_object(
    'purchase_order_id', p_purchase_order_id,
    'receipt_id', v_receipt_id,
    'warehouse_id', p_warehouse_id,
    'document_type', v_document_type,
    'document_number', v_document_number,
    'status', v_new_status,
    'purchase_quantity', v_total_purchase_qty,
    'sale_quantity', v_total_sale_qty,
    'generated_at', NOW()
  );
END;
$$;

ALTER FUNCTION pharmacy.receive_purchase_order_transactional(uuid, uuid, jsonb, jsonb) OWNER TO postgres;

GRANT EXECUTE ON FUNCTION pharmacy.receive_purchase_order_transactional(uuid, uuid, jsonb, jsonb) TO authenticated;
