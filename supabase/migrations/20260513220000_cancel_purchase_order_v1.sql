-- Compras v2.1 - Anulación controlada de órdenes de compra.

ALTER TABLE pharmacy.purchase_orders
  ADD COLUMN IF NOT EXISTS cancelled_at timestamptz,
  ADD COLUMN IF NOT EXISTS cancelled_by uuid,
  ADD COLUMN IF NOT EXISTS cancellation_reason text;

COMMENT ON COLUMN pharmacy.purchase_orders.cancelled_at IS 'Marca temporal de anulación de la OC.';
COMMENT ON COLUMN pharmacy.purchase_orders.cancelled_by IS 'Usuario que anuló la OC.';
COMMENT ON COLUMN pharmacy.purchase_orders.cancellation_reason IS 'Motivo de anulación de la OC.';

CREATE OR REPLACE FUNCTION pharmacy.cancel_purchase_order(
  p_purchase_order_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
DECLARE
  v_company_id uuid := pharmacy.get_my_company_id();
  v_user_id uuid := auth.uid();
  v_status text;
  v_warehouse_id uuid;
  v_po_number integer;
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'No se pudo resolver la compañía.';
  END IF;

  IF p_purchase_order_id IS NULL THEN
    RAISE EXCEPTION 'Debe indicar la orden a anular.';
  END IF;

  IF btrim(COALESCE(p_reason, '')) = '' THEN
    RAISE EXCEPTION 'Debe indicar un motivo de anulación.';
  END IF;

  SELECT po.status, po.warehouse_id, po.po_number
    INTO v_status, v_warehouse_id, v_po_number
  FROM pharmacy.purchase_orders po
  WHERE po.id = p_purchase_order_id
    AND po.company_id = v_company_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La orden no existe en la compañía actual.';
  END IF;

  IF v_status NOT IN ('DRAFT', 'PENDING') THEN
    RAISE EXCEPTION 'Solo se pueden anular órdenes en estado DRAFT o PENDING.';
  END IF;

  UPDATE pharmacy.purchase_orders
     SET status = 'CANCELLED',
         cancelled_at = NOW(),
         cancelled_by = v_user_id,
         cancellation_reason = btrim(p_reason),
         updated_by = v_user_id
   WHERE id = p_purchase_order_id
     AND company_id = v_company_id;

  PERFORM pharmacy.log_audit_event(
    'PURCHASE_ORDER_CANCELLED',
    'Anulación de orden de compra',
    jsonb_build_object(
      'purchase_order_id', p_purchase_order_id,
      'po_number', v_po_number,
      'warehouse_id', v_warehouse_id,
      'reason', btrim(p_reason),
      'previous_status', v_status,
      'cancelled_by', v_user_id
    )
  );

  RETURN jsonb_build_object(
    'po_id', p_purchase_order_id,
    'po_number', v_po_number,
    'status', 'CANCELLED',
    'cancelled_at', NOW(),
    'generated_at', NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION pharmacy.cancel_purchase_order(uuid, text) TO authenticated;
