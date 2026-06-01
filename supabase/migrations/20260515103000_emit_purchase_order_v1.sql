-- Permite emitir una OC aprobada hacia PENDING sin tocar inventario.

CREATE OR REPLACE FUNCTION pharmacy.emit_purchase_order(
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
  v_has_updated_at boolean := false;
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

  IF v_current_status <> 'APPROVED' THEN
    RAISE EXCEPTION 'Solo se pueden emitir órdenes en estado APPROVED.';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'pharmacy'
      AND table_name = 'purchase_orders'
      AND column_name = 'updated_at'
  ) INTO v_has_updated_at;

  IF v_has_updated_at THEN
    EXECUTE '
      UPDATE pharmacy.purchase_orders
         SET status = $1,
             updated_by = $2,
             updated_at = NOW()
       WHERE id = $3
         AND company_id = $4
    ' USING 'PENDING', v_user_id, p_purchase_order_id, v_company_id;
  ELSE
    UPDATE pharmacy.purchase_orders
       SET status = 'PENDING',
           updated_by = v_user_id
     WHERE id = p_purchase_order_id
       AND company_id = v_company_id;
  END IF;

  IF to_regclass('pharmacy.audit_logs') IS NOT NULL THEN
    PERFORM pharmacy.log_audit_event(
      'PURCHASE_ORDER_EMITTED',
      'Orden de compra emitida',
      jsonb_build_object(
        'purchase_order_id', p_purchase_order_id,
        'po_number', v_po_number,
        'emitted_by', v_user_id,
        'status_from', v_current_status,
        'status_to', 'PENDING'
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'po_id', p_purchase_order_id,
    'po_number', v_po_number,
    'status', 'PENDING',
    'emitted_by', v_user_id,
    'generated_at', NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION pharmacy.emit_purchase_order(uuid) TO authenticated;
