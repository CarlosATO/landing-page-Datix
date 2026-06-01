-- Hardening migration: DTE permissions, idempotent function, graceful error capture
-- Resolves: generate_internal_dte not returning dte_id / RLS blocking upsert

-- 0. Drop existing function signatures to allow clean recreation
DROP FUNCTION IF EXISTS pharmacy.generate_internal_dte(uuid) CASCADE;
DROP FUNCTION IF EXISTS pharmacy.process_pharmacy_sale(uuid, numeric, text, text, uuid, uuid, jsonb) CASCADE;

-- 1. RLS: replace policies with WITH CHECK clause for upsert support
ALTER TABLE "pharmacy"."dte_folios" DISABLE ROW LEVEL SECURITY;
ALTER TABLE "pharmacy"."dte_documents" DISABLE ROW LEVEL SECURITY;
ALTER TABLE "pharmacy"."dte_folios" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "pharmacy"."dte_documents" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "DTE Folios Isolation"       ON "pharmacy"."dte_folios";
DROP POLICY IF EXISTS "DTE Documents Isolation"    ON "pharmacy"."dte_documents";
DROP POLICY IF EXISTS "dte_folios_isolation"       ON "pharmacy"."dte_folios";
DROP POLICY IF EXISTS "dte_documents_isolation"    ON "pharmacy"."dte_documents";

CREATE POLICY "dte_folios_isolation" ON "pharmacy"."dte_folios"
    FOR ALL TO authenticated
    USING (company_id IN (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()))
    WITH CHECK (company_id IN (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

CREATE POLICY "dte_documents_isolation" ON "pharmacy"."dte_documents"
    FOR ALL TO authenticated
    USING (company_id IN (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()))
    WITH CHECK (company_id IN (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

-- 2. Hardened generate_internal_dte
CREATE FUNCTION pharmacy.generate_internal_dte(p_sale_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
declare
    v_sale     record;
    v_folio    bigint;
    v_dte_id   uuid;
    v_dte_type text := 'BOLETA';
begin
    -- Idempotent: return existing DTE if already created for this sale
    SELECT id INTO v_dte_id FROM pharmacy.dte_documents WHERE sale_id = p_sale_id LIMIT 1;
    IF FOUND THEN RETURN v_dte_id; END IF;

    -- Load sale row
    SELECT * INTO v_sale FROM pharmacy.sales WHERE id = p_sale_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'generate_internal_dte: Venta no encontrada (sale_id=%)', p_sale_id;
    END IF;

    -- Atomically allocate next folio
    INSERT INTO pharmacy.dte_folios (company_id, dte_type, current_folio)
    VALUES (v_sale.company_id, v_dte_type, 1)
    ON CONFLICT (company_id, dte_type)
    DO UPDATE SET current_folio = pharmacy.dte_folios.current_folio + 1
    RETURNING current_folio INTO v_folio;

    IF v_folio IS NULL THEN
        RAISE EXCEPTION 'generate_internal_dte: No se pudo asignar folio para company_id=%', v_sale.company_id;
    END IF;

    -- Create DTE document row
    INSERT INTO pharmacy.dte_documents (
        company_id, sale_id, customer_id, dte_type, folio, status,
        subtotal, tax_amount, total_amount, created_by, issued_at
    )
    VALUES (
        v_sale.company_id, v_sale.id, v_sale.patient_id, v_dte_type, v_folio, 'PENDING',
        ROUND(v_sale.total_amount / 1.19, 2),
        ROUND(v_sale.total_amount - (v_sale.total_amount / 1.19), 2),
        v_sale.total_amount, v_sale.user_id, now()
    )
    RETURNING id INTO v_dte_id;

    RETURN v_dte_id;
END;
$$;

GRANT EXECUTE ON FUNCTION pharmacy.generate_internal_dte(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION pharmacy.generate_internal_dte(uuid) TO service_role;

-- 3. Hardened process_pharmacy_sale (returns dte_id + dte_error for diagnostics)
CREATE FUNCTION pharmacy.process_pharmacy_sale(
    p_warehouse_id    uuid,
    p_total_amount    numeric,
    p_payment_method  text,
    p_document_number text,
    p_patient_id      uuid    DEFAULT NULL,
    p_prescription_id uuid    DEFAULT NULL,
    p_items           jsonb   DEFAULT '[]'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
declare
  v_user_id    uuid;
  v_company_id uuid;
  v_session_id uuid;
  v_sale_id    uuid;
  v_dte_id     uuid;
  v_dte_error  text;

  v_item                      jsonb;
  v_product_id                uuid;
  v_quantity                  numeric;
  v_unit_price                numeric;
  v_item_prescription_id      uuid;

  v_remaining      numeric;
  v_qty_to_deduct  numeric;
  v_batch          record;
  v_balance_after  numeric;

  v_sale_condition            text;
  v_product_prescription_type text;
  v_is_controlled             boolean;

  v_prescription_status       text;
  v_prescription_type         text;
  v_prescription_patient_id   uuid;
  v_prescription_valid_until  timestamptz;
  v_qty_prescribed            numeric;
  v_qty_dispensed             numeric;
  v_qty_pending               numeric;
begin
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Usuario no autenticado'; END IF;

  SELECT company_id INTO v_company_id FROM public.company_users WHERE user_id = v_user_id LIMIT 1;
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Usuario sin empresa asociada'; END IF;

  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN RAISE EXCEPTION 'La venta no contiene productos'; END IF;

  -- Lock POS session
  BEGIN
    SELECT id INTO v_session_id
    FROM pharmacy.pos_sessions
    WHERE company_id = v_company_id AND user_id = v_user_id AND warehouse_id = p_warehouse_id AND status = 'OPEN'
    ORDER BY created_at DESC LIMIT 1 FOR UPDATE NOWAIT;
  EXCEPTION WHEN lock_not_available THEN
    RAISE EXCEPTION 'Su sesión de caja está siendo procesada en otra transacción.';
  END;

  IF v_session_id IS NULL THEN RAISE EXCEPTION 'Debes abrir caja antes de vender'; END IF;

  -- Insert sale header
  INSERT INTO pharmacy.sales (company_id, user_id, session_id, patient_id, total_amount, payment_method, document_number)
  VALUES (
    v_company_id, v_user_id, v_session_id, p_patient_id, p_total_amount,
    COALESCE(p_payment_method, 'CASH'),
    COALESCE(p_document_number, 'TICKET-' || EXTRACT(epoch FROM now())::bigint)
  )
  RETURNING id INTO v_sale_id;

  -- Process each cart item
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_product_id := COALESCE(NULLIF(v_item->>'product_id','')::uuid, NULLIF(v_item->>'id','')::uuid);
    v_item_prescription_id := COALESCE(NULLIF(v_item->>'prescription_id','')::uuid, p_prescription_id);
    v_quantity   := COALESCE((v_item->>'quantity')::numeric, 0);
    v_unit_price := COALESCE(NULLIF(v_item->>'unit_price','')::numeric, NULLIF(v_item->>'price_sale','')::numeric, 0);

    IF v_product_id IS NULL THEN RAISE EXCEPTION 'Producto inválido en carrito'; END IF;
    IF v_quantity <= 0 THEN RAISE EXCEPTION 'Cantidad inválida para producto %', v_product_id; END IF;

    SELECT UPPER(COALESCE(sale_condition,'VD')), UPPER(COALESCE(prescription_type,'VENTA_LIBRE')), COALESCE(is_controlled,false)
    INTO v_sale_condition, v_product_prescription_type, v_is_controlled
    FROM pharmacy.products WHERE id = v_product_id AND company_id = v_company_id;

    IF v_sale_condition IS NULL THEN RAISE EXCEPTION 'Producto no encontrado o no pertenece a la empresa'; END IF;

    IF v_is_controlled OR v_sale_condition IN ('R','RR','RCH') OR v_product_prescription_type IN ('RECETA_SIMPLE','RECETA_RETENIDA','RECETA_CHEQUE') THEN
      IF v_item_prescription_id IS NULL THEN RAISE EXCEPTION 'El producto requiere receta médica válida'; END IF;

      BEGIN
        SELECT status, UPPER(COALESCE(prescription_type,'RECETA_SIMPLE')), patient_id, valid_until
        INTO v_prescription_status, v_prescription_type, v_prescription_patient_id, v_prescription_valid_until
        FROM pharmacy.prescriptions WHERE id = v_item_prescription_id AND company_id = v_company_id FOR UPDATE NOWAIT;
      EXCEPTION WHEN lock_not_available THEN
        RAISE EXCEPTION 'La receta está siendo procesada en otra caja.';
      END;

      IF v_prescription_status IS NULL THEN RAISE EXCEPTION 'Receta no encontrada'; END IF;

      IF v_prescription_valid_until IS NOT NULL AND now() > (v_prescription_valid_until + INTERVAL '1 day') THEN
        UPDATE pharmacy.prescriptions SET status='EXPIRED', expired_at=now() WHERE id=v_item_prescription_id;
        RAISE EXCEPTION 'La receta se encuentra vencida';
      END IF;

      IF v_prescription_status NOT IN ('PENDING','PARTIAL') THEN
        RAISE EXCEPTION 'La receta ya no está disponible para despacho (Estado: %)', v_prescription_status;
      END IF;

      IF p_patient_id IS NOT NULL AND v_prescription_patient_id <> p_patient_id THEN
        RAISE EXCEPTION 'La receta no pertenece al paciente seleccionado';
      END IF;

      IF (v_sale_condition='RR' OR v_product_prescription_type='RECETA_RETENIDA') AND v_prescription_type<>'RECETA_RETENIDA' THEN
        RAISE EXCEPTION 'Este producto requiere receta retenida';
      END IF;

      IF (v_sale_condition='RCH' OR v_product_prescription_type='RECETA_CHEQUE') AND v_prescription_type<>'RECETA_CHEQUE' THEN
        RAISE EXCEPTION 'Este producto requiere receta cheque';
      END IF;

      BEGIN
        SELECT quantity_prescribed, COALESCE(quantity_dispensed,0)
        INTO v_qty_prescribed, v_qty_dispensed
        FROM pharmacy.prescription_items WHERE prescription_id=v_item_prescription_id AND product_id=v_product_id FOR UPDATE NOWAIT;
      EXCEPTION WHEN lock_not_available THEN
        RAISE EXCEPTION 'Los items de esta receta están bloqueados por otra operación.';
      END;

      IF v_qty_prescribed IS NULL THEN RAISE EXCEPTION 'El producto no está incluido en la receta'; END IF;
      v_qty_pending := v_qty_prescribed - v_qty_dispensed;
      IF v_qty_pending <= 0 THEN RAISE EXCEPTION 'El producto ya fue completamente despachado en esta receta.'; END IF;
      IF v_quantity > v_qty_pending THEN
        RAISE EXCEPTION 'La cantidad vendida (%) supera la cantidad pendiente de la receta (%)', v_quantity, v_qty_pending;
      END IF;
    END IF;

    -- FEFO batch consumption
    v_remaining := v_quantity;
    FOR v_batch IN
      SELECT b.id, b.product_id, b.batch_number, b.current_quantity, b.location_id, b.expiry_date
      FROM pharmacy.inventory_batches b
      JOIN pharmacy.locations l ON l.id = b.location_id
      WHERE b.company_id=v_company_id AND b.product_id=v_product_id AND b.current_quantity>0
        AND l.company_id=v_company_id AND l.warehouse_id=p_warehouse_id AND UPPER(l.location_type)<>'QUARANTINE'
      ORDER BY CASE WHEN UPPER(l.location_type)='SALES' THEN 0 ELSE 1 END, b.expiry_date ASC
      FOR UPDATE OF b NOWAIT
    LOOP
      EXIT WHEN v_remaining <= 0;
      IF v_batch.current_quantity <= 0 THEN CONTINUE; END IF;

      v_qty_to_deduct := LEAST(v_remaining, v_batch.current_quantity);

      UPDATE pharmacy.inventory_batches
      SET current_quantity = current_quantity - v_qty_to_deduct
      WHERE id=v_batch.id AND company_id=v_company_id AND current_quantity>=v_qty_to_deduct;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Error de concurrencia: El stock del lote % cambió durante la transacción.', v_batch.batch_number;
      END IF;

      INSERT INTO pharmacy.sale_items (company_id, sale_id, product_id, batch_id, quantity, unit_price, subtotal, prescription_id)
      VALUES (v_company_id, v_sale_id, v_product_id, v_batch.id, v_qty_to_deduct, v_unit_price, v_qty_to_deduct*v_unit_price, v_item_prescription_id);

      SELECT COALESCE(SUM(current_quantity),0) INTO v_balance_after
      FROM pharmacy.inventory_batches WHERE company_id=v_company_id AND product_id=v_product_id AND location_id=v_batch.location_id;

      INSERT INTO pharmacy.inventory_movements (company_id, product_id, batch_id, batch_number, from_location_id, movement_type, quantity, balance_after, reference_folio, created_by)
      VALUES (v_company_id, v_product_id, v_batch.id, v_batch.batch_number, v_batch.location_id, 'SALE', -ABS(v_qty_to_deduct), v_balance_after, COALESCE(p_document_number,'VENTA_POS'), v_user_id);

      v_remaining := v_remaining - v_qty_to_deduct;
    END LOOP;

    IF v_remaining > 0 THEN
      RAISE EXCEPTION 'Stock insuficiente para el producto %. Faltan % unidades (posible venta simultánea).', v_product_id, v_remaining;
    END IF;

    IF v_item_prescription_id IS NOT NULL THEN
      UPDATE pharmacy.prescription_items
      SET quantity_dispensed = COALESCE(quantity_dispensed,0) + v_quantity
      WHERE prescription_id=v_item_prescription_id AND product_id=v_product_id;
    END IF;
  END LOOP;

  -- Update prescription statuses
  UPDATE pharmacy.prescriptions p
  SET status = CASE
    WHEN totals.total_dispensed <= 0 THEN 'PENDING'
    WHEN totals.total_dispensed < totals.total_prescribed THEN 'PARTIAL'
    ELSE 'DISPENSED'
  END
  FROM (
    SELECT pi.prescription_id,
      SUM(pi.quantity_prescribed) AS total_prescribed,
      SUM(COALESCE(pi.quantity_dispensed,0)) AS total_dispensed
    FROM pharmacy.prescription_items pi
    WHERE pi.prescription_id IN (
      SELECT DISTINCT COALESCE(NULLIF(item->>'prescription_id','')::uuid, p_prescription_id)
      FROM jsonb_array_elements(p_items) item
      WHERE COALESCE(NULLIF(item->>'prescription_id',''), p_prescription_id::text) IS NOT NULL
    )
    GROUP BY pi.prescription_id
  ) totals
  WHERE p.id = totals.prescription_id AND p.company_id = v_company_id;

  -- Generate internal DTE — graceful (sale is NEVER rolled back for DTE failure)
  BEGIN
    v_dte_id := pharmacy.generate_internal_dte(v_sale_id);
  EXCEPTION WHEN OTHERS THEN
    v_dte_id    := NULL;
    v_dte_error := SQLERRM;
    RAISE WARNING 'process_pharmacy_sale: DTE generation failed for sale_id=% — %', v_sale_id, v_dte_error;
  END;

  RETURN jsonb_build_object(
    'sale_id',    v_sale_id,
    'session_id', v_session_id,
    'company_id', v_company_id,
    'dte_id',     v_dte_id,
    'dte_error',  v_dte_error,
    'success',    true
  );

EXCEPTION
  WHEN lock_not_available THEN
    RAISE EXCEPTION 'Conflicto de concurrencia: Los recursos (stock o receta) están siendo usados por otra caja. Intente nuevamente.';
END;
$$;

GRANT EXECUTE ON FUNCTION pharmacy.process_pharmacy_sale(uuid, numeric, text, text, uuid, uuid, jsonb) TO authenticated;
