-- Ajusta el flujo de OC para usar pre-aprobación.

ALTER TABLE pharmacy.purchase_orders
  DROP CONSTRAINT IF EXISTS purchase_orders_status_check;

ALTER TABLE pharmacy.purchase_orders
  ADD CONSTRAINT purchase_orders_status_check
  CHECK (
    status = ANY (
      ARRAY[
        'DRAFT'::text,
        'WAITING_APPROVAL'::text,
        'APPROVED'::text,
        'PENDING'::text,
        'PARTIAL'::text,
        'RECEIVED'::text,
        'CANCELLED'::text
      ]
    )
  );

ALTER TABLE pharmacy.purchase_orders
  ADD COLUMN IF NOT EXISTS approved_by uuid;

ALTER TABLE pharmacy.purchase_orders
  ADD COLUMN IF NOT EXISTS approval_date timestamptz;

CREATE OR REPLACE FUNCTION pharmacy.update_purchase_order_draft(
  p_purchase_order_id uuid,
  p_supplier_id uuid DEFAULT NULL,
  p_expected_delivery_date date DEFAULT NULL,
  p_observation_notes text DEFAULT NULL,
  p_payment_terms_days integer DEFAULT NULL,
  p_items jsonb DEFAULT '[]'::jsonb,
  p_emit boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
DECLARE
  v_company_id uuid := pharmacy.get_my_company_id();
  v_user_id uuid := auth.uid();
  v_current_status text;
  v_warehouse_id uuid;
  v_po_number integer;
  v_net numeric := 0;
  v_tax numeric := 0;
  v_total numeric := 0;
  v_items_count integer := 0;
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'No se pudo resolver la compañía.';
  END IF;

  IF p_purchase_order_id IS NULL THEN
    RAISE EXCEPTION 'Debe indicar la orden a editar.';
  END IF;

  SELECT po.status, po.po_number, po.warehouse_id
    INTO v_current_status, v_po_number, v_warehouse_id
  FROM pharmacy.purchase_orders po
  WHERE po.id = p_purchase_order_id
    AND po.company_id = v_company_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La orden no existe en la compañía actual.';
  END IF;

  IF v_current_status <> 'DRAFT' THEN
    RAISE EXCEPTION 'Solo se pueden editar órdenes en estado DRAFT.';
  END IF;

  IF p_emit AND p_supplier_id IS NULL THEN
    RAISE EXCEPTION 'Debe seleccionar un proveedor para emitir la orden.';
  END IF;

  WITH requested_items AS (
    SELECT
      (item->>'product_id')::uuid AS product_id,
      GREATEST(0, COALESCE(NULLIF(item->>'quantity', ''), '0')::numeric) AS quantity,
      GREATEST(0, COALESCE(NULLIF(item->>'unit_cost', ''), '0')::numeric) AS unit_cost,
      GREATEST(COALESCE(NULLIF(item->>'conversion_factor', ''), '1')::numeric, 1) AS conversion_factor
    FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb)) AS item
    WHERE item ? 'product_id'
      AND item ? 'quantity'
  ),
  normalized_items AS (
    SELECT
      ri.product_id,
      SUM(ri.quantity) AS quantity,
      COALESCE(MAX(NULLIF(ri.unit_cost, 0)), pharmacy.get_last_purchase_unit_cost(v_company_id, v_warehouse_id, ri.product_id)) AS unit_cost,
      MAX(ri.conversion_factor) AS conversion_factor
    FROM requested_items ri
    JOIN pharmacy.products p
      ON p.id = ri.product_id
     AND p.company_id = v_company_id
    GROUP BY ri.product_id
    HAVING SUM(ri.quantity) > 0
  )
  SELECT COUNT(*), COALESCE(SUM(quantity * unit_cost), 0)
    INTO v_items_count, v_net
  FROM normalized_items;

  IF v_items_count = 0 THEN
    RAISE EXCEPTION 'La orden debe contener al menos una línea válida.';
  END IF;

  v_tax := ROUND(v_net * 0.19, 2);
  v_total := v_net + v_tax;

  UPDATE pharmacy.purchase_orders
     SET supplier_id = p_supplier_id,
         expected_delivery_date = p_expected_delivery_date,
         observation_notes = p_observation_notes,
         payment_terms_days = p_payment_terms_days,
         total_neto = v_net,
         total_net = v_net,
         tax_amount = v_tax,
         total_amount = v_total,
         status = CASE WHEN p_emit THEN 'WAITING_APPROVAL' ELSE 'DRAFT' END,
         updated_by = v_user_id
   WHERE id = p_purchase_order_id
     AND company_id = v_company_id;

  DELETE FROM pharmacy.purchase_order_items
   WHERE po_id = p_purchase_order_id;

  WITH requested_items AS (
    SELECT
      (item->>'product_id')::uuid AS product_id,
      GREATEST(0, COALESCE(NULLIF(item->>'quantity', ''), '0')::numeric) AS quantity,
      GREATEST(0, COALESCE(NULLIF(item->>'unit_cost', ''), '0')::numeric) AS unit_cost,
      GREATEST(COALESCE(NULLIF(item->>'conversion_factor', ''), '1')::numeric, 1) AS conversion_factor
    FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb)) AS item
    WHERE item ? 'product_id'
      AND item ? 'quantity'
  ),
  normalized_items AS (
    SELECT
      ri.product_id,
      SUM(ri.quantity) AS quantity,
      COALESCE(MAX(NULLIF(ri.unit_cost, 0)), pharmacy.get_last_purchase_unit_cost(v_company_id, v_warehouse_id, ri.product_id)) AS unit_cost,
      MAX(ri.conversion_factor) AS conversion_factor
    FROM requested_items ri
    JOIN pharmacy.products p
      ON p.id = ri.product_id
     AND p.company_id = v_company_id
    GROUP BY ri.product_id
    HAVING SUM(ri.quantity) > 0
  )
  INSERT INTO pharmacy.purchase_order_items (
    po_id,
    product_id,
    quantity,
    unit_cost,
    total_cost,
    conversion_factor,
    updated_by
  )
  SELECT
    p_purchase_order_id,
    ni.product_id,
    ni.quantity,
    ni.unit_cost,
    ni.quantity * ni.unit_cost,
    ni.conversion_factor,
    v_user_id
  FROM normalized_items ni;

  RETURN jsonb_build_object(
    'po_id', p_purchase_order_id,
    'po_number', v_po_number,
    'status', CASE WHEN p_emit THEN 'WAITING_APPROVAL' ELSE 'DRAFT' END,
    'supplier_id', p_supplier_id,
    'total_net', v_net,
    'tax_amount', v_tax,
    'total_amount', v_total,
    'items_count', v_items_count,
    'generated_at', NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION pharmacy.update_purchase_order_draft(uuid, uuid, date, text, integer, jsonb, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION pharmacy.approve_purchase_order(
  p_purchase_order_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
DECLARE
  v_company_id uuid := pharmacy.get_my_company_id();
  v_user_id uuid := auth.uid();
  v_po_number integer;
  v_current_status text;
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'No se pudo resolver la compañía.';
  END IF;

  SELECT po.po_number, po.status
    INTO v_po_number, v_current_status
  FROM pharmacy.purchase_orders po
  WHERE po.id = p_purchase_order_id
    AND po.company_id = v_company_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La orden no existe en la compañía actual.';
  END IF;

  IF v_current_status <> 'WAITING_APPROVAL' THEN
    RAISE EXCEPTION 'Solo se pueden aprobar órdenes en estado WAITING_APPROVAL.';
  END IF;

  UPDATE pharmacy.purchase_orders
     SET status = 'APPROVED',
         approved_by = v_user_id,
         approval_date = NOW(),
         updated_by = v_user_id
   WHERE id = p_purchase_order_id
     AND company_id = v_company_id;

  PERFORM pharmacy.log_audit_event(
    'PURCHASE_ORDER_APPROVED',
    'Orden de compra aprobada',
    jsonb_build_object(
      'purchase_order_id', p_purchase_order_id,
      'po_number', v_po_number,
      'approved_by', v_user_id
    )
  );

  RETURN jsonb_build_object(
    'po_id', p_purchase_order_id,
    'po_number', v_po_number,
    'status', 'APPROVED',
    'approved_by', v_user_id,
    'approval_date', NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION pharmacy.approve_purchase_order(uuid) TO authenticated;
