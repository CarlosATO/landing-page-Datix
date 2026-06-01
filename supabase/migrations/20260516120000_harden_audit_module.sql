-- Harden audit read paths behind SECURITY DEFINER RPCs.

CREATE OR REPLACE FUNCTION pharmacy.fetch_batch_registry(
  p_batch_number text DEFAULT NULL,
  p_limit integer DEFAULT 200,
  p_offset integer DEFAULT 0
) RETURNS SETOF pharmacy.view_batch_registry
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
  WITH my_company AS (
    SELECT pharmacy.get_my_company_id() AS company_id
  )
  SELECT v.*
  FROM pharmacy.view_batch_registry v
  JOIN my_company mc ON mc.company_id = v.company_id
  WHERE (p_batch_number IS NULL OR v.batch_number = p_batch_number)
  ORDER BY v.received_date DESC NULLS LAST, v.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 200), 0), 500)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
$$;

CREATE OR REPLACE FUNCTION pharmacy.fetch_batch_audit(
  p_batch_id uuid DEFAULT NULL,
  p_batch_number text DEFAULT NULL,
  p_from timestamptz DEFAULT NULL,
  p_to timestamptz DEFAULT NULL,
  p_product_id uuid DEFAULT NULL,
  p_limit integer DEFAULT 500,
  p_offset integer DEFAULT 0
) RETURNS SETOF pharmacy.view_batch_audit
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
  WITH my_company AS (
    SELECT pharmacy.get_my_company_id() AS company_id
  )
  SELECT v.*
  FROM pharmacy.view_batch_audit v
  JOIN my_company mc ON mc.company_id = v.company_id
  WHERE (p_batch_id IS NULL OR v.batch_id = p_batch_id)
    AND (p_batch_number IS NULL OR v.batch_number = p_batch_number)
    AND (p_from IS NULL OR v.created_at >= p_from)
    AND (p_to IS NULL OR v.created_at <= p_to)
    AND (p_product_id IS NULL OR v.product_id = p_product_id)
  ORDER BY v.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 500), 0), 500)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
$$;

CREATE OR REPLACE FUNCTION pharmacy.fetch_prescription_audit(
  p_patient_rut text DEFAULT NULL,
  p_folio_electronico text DEFAULT NULL,
  p_from timestamptz DEFAULT NULL,
  p_to timestamptz DEFAULT NULL,
  p_limit integer DEFAULT 200,
  p_offset integer DEFAULT 0
) RETURNS SETOF pharmacy.view_prescription_audit
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
  WITH my_company AS (
    SELECT pharmacy.get_my_company_id() AS company_id
  )
  SELECT v.*
  FROM pharmacy.view_prescription_audit v
  JOIN my_company mc ON mc.company_id = v.company_id
  WHERE (p_patient_rut IS NULL OR v.patient_rut ILIKE '%' || p_patient_rut || '%')
    AND (p_folio_electronico IS NULL OR v.folio_electronico ILIKE '%' || p_folio_electronico || '%')
    AND (p_from IS NULL OR v.sale_date >= p_from)
    AND (p_to IS NULL OR v.sale_date <= p_to)
  ORDER BY v.sale_date DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 200), 0), 500)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
$$;

CREATE OR REPLACE FUNCTION pharmacy.fetch_controlled_audit(
  p_patient_rut text DEFAULT NULL,
  p_product_id uuid DEFAULT NULL,
  p_from timestamptz DEFAULT NULL,
  p_to timestamptz DEFAULT NULL,
  p_limit integer DEFAULT 200,
  p_offset integer DEFAULT 0
) RETURNS SETOF pharmacy.view_controlled_audit
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
  WITH my_company AS (
    SELECT pharmacy.get_my_company_id() AS company_id
  )
  SELECT v.*
  FROM pharmacy.view_controlled_audit v
  JOIN my_company mc ON mc.company_id = v.company_id
  WHERE (p_patient_rut IS NULL OR v.patient_rut ILIKE '%' || p_patient_rut || '%')
    AND (p_product_id IS NULL OR v.product_id = p_product_id)
    AND (p_from IS NULL OR v.created_at >= p_from)
    AND (p_to IS NULL OR v.created_at <= p_to)
  ORDER BY v.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 200), 0), 500)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
$$;

CREATE OR REPLACE FUNCTION pharmacy.fetch_audit_log_detail(p_audit_log_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
DECLARE
  v_company_id uuid;
  v_log record;
  v_warehouse record;
  v_operator record;
  v_sale record;
  v_session record;
  v_batch record;
  v_prescription record;
  v_products jsonb := '[]'::jsonb;
  v_prescriptions jsonb := '[]'::jsonb;
  v_items jsonb;
  v_item jsonb;
  v_product_ids uuid[] := ARRAY[]::uuid[];
  v_prescription_ids uuid[] := ARRAY[]::uuid[];
BEGIN
  v_company_id := pharmacy.get_my_company_id();
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Usuario sin empresa asociada';
  END IF;

  SELECT
    a.id,
    a.company_id,
    a.user_id,
    a.event_type,
    a.description,
    a.metadata,
    a.ip_address,
    a.created_at,
    COALESCE(cu.full_name, po.full_name, 'Sistema') AS user_name
  INTO v_log
  FROM pharmacy.audit_logs a
  LEFT JOIN public.company_users cu
    ON cu.user_id = a.user_id
   AND cu.company_id = a.company_id
  LEFT JOIN pharmacy.pos_operators po
    ON po.id = NULLIF(a.metadata->>'operator_id', '')::uuid
   AND po.company_id = a.company_id
  WHERE a.id = p_audit_log_id
    AND a.company_id = v_company_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Registro de auditoria no encontrado';
  END IF;

  v_items := COALESCE(v_log.metadata->'items', '[]'::jsonb);

  IF v_log.metadata ? 'warehouse_id' AND NULLIF(v_log.metadata->>'warehouse_id', '') IS NOT NULL THEN
    SELECT id, name
    INTO v_warehouse
    FROM pharmacy.warehouses
    WHERE id = (v_log.metadata->>'warehouse_id')::uuid
      AND company_id = v_company_id
    LIMIT 1;
  END IF;

  IF v_log.metadata ? 'operator_id' AND NULLIF(v_log.metadata->>'operator_id', '') IS NOT NULL THEN
    SELECT id, full_name
    INTO v_operator
    FROM pharmacy.pos_operators
    WHERE id = (v_log.metadata->>'operator_id')::uuid
      AND company_id = v_company_id
    LIMIT 1;
  END IF;

  IF v_log.metadata ? 'sale_id' AND NULLIF(v_log.metadata->>'sale_id', '') IS NOT NULL THEN
    SELECT
      s.id,
      s.document_number,
      s.created_at,
      s.payment_method,
      s.total_amount,
      pat.full_name AS patient_name,
      pat.rut AS patient_rut
    INTO v_sale
    FROM pharmacy.sales s
    LEFT JOIN pharmacy.patients pat ON pat.id = s.patient_id
    WHERE s.id = (v_log.metadata->>'sale_id')::uuid
      AND s.company_id = v_company_id
    LIMIT 1;
  END IF;

  IF v_log.metadata ? 'session_id' AND NULLIF(v_log.metadata->>'session_id', '') IS NOT NULL THEN
    SELECT
      sess.id,
      sess.start_time,
      sess.end_time,
      sess.warehouse_id,
      sess.user_id,
      op.full_name AS operator_name
    INTO v_session
    FROM pharmacy.pos_sessions sess
    LEFT JOIN pharmacy.pos_operators op ON op.id = sess.user_id AND op.company_id = v_company_id
    WHERE sess.id = (v_log.metadata->>'session_id')::uuid
      AND sess.company_id = v_company_id
    LIMIT 1;
  END IF;

  IF v_log.metadata ? 'batch_id' AND NULLIF(v_log.metadata->>'batch_id', '') IS NOT NULL THEN
    SELECT *
    INTO v_batch
    FROM pharmacy.view_batch_registry
    WHERE id = (v_log.metadata->>'batch_id')::uuid
      AND company_id = v_company_id
    LIMIT 1;
  END IF;

  IF v_log.metadata ? 'prescription_id' AND NULLIF(v_log.metadata->>'prescription_id', '') IS NOT NULL THEN
    SELECT
      p.id,
      p.folio_electronico,
      p.prescriber_name,
      p.prescriber_rut,
      pat.full_name AS patient_name,
      pat.rut AS patient_rut
    INTO v_prescription
    FROM pharmacy.prescriptions p
    LEFT JOIN pharmacy.patients pat ON pat.id = p.patient_id
    WHERE p.id = (v_log.metadata->>'prescription_id')::uuid
      AND p.company_id = v_company_id
    LIMIT 1;
  END IF;

  FOR v_item IN
    SELECT value
    FROM jsonb_array_elements(v_items)
  LOOP
    IF NULLIF(v_item->>'product_id', '') IS NOT NULL THEN
      v_product_ids := array_append(v_product_ids, (v_item->>'product_id')::uuid);
    END IF;

    IF NULLIF(v_item->>'prescription_id', '') IS NOT NULL THEN
      v_prescription_ids := array_append(v_prescription_ids, (v_item->>'prescription_id')::uuid);
    END IF;
  END LOOP;

  IF array_length(v_product_ids, 1) IS NOT NULL THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(prod)), '[]'::jsonb)
    INTO v_products
    FROM (
      SELECT id, name, dci, barcode
      FROM pharmacy.products
      WHERE company_id = v_company_id
        AND id = ANY (v_product_ids)
      ORDER BY name
    ) prod;
  END IF;

  IF array_length(v_prescription_ids, 1) IS NOT NULL THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(rx)), '[]'::jsonb)
    INTO v_prescriptions
    FROM (
      SELECT
        p.id,
        p.folio_electronico,
        p.prescriber_name,
        p.prescriber_rut,
        pat.full_name AS patient_name,
        pat.rut AS patient_rut
      FROM pharmacy.prescriptions p
      LEFT JOIN pharmacy.patients pat ON pat.id = p.patient_id
      WHERE p.company_id = v_company_id
        AND p.id = ANY (v_prescription_ids)
      ORDER BY p.created_at DESC
    ) rx;
  END IF;

  RETURN jsonb_build_object(
    'audit_log', jsonb_build_object(
      'id', v_log.id,
      'company_id', v_log.company_id,
      'user_id', v_log.user_id,
      'user_name', v_log.user_name,
      'event_type', v_log.event_type,
      'description', v_log.description,
      'metadata', v_log.metadata,
      'ip_address', v_log.ip_address,
      'created_at', v_log.created_at
    ),
    'warehouse', to_jsonb(v_warehouse),
    'operator', to_jsonb(v_operator),
    'sale', to_jsonb(v_sale),
    'session', to_jsonb(v_session),
    'batch', to_jsonb(v_batch),
    'prescription', to_jsonb(v_prescription),
    'products', v_products,
    'prescriptions', v_prescriptions
  );
END;
$$;

GRANT ALL ON FUNCTION pharmacy.fetch_audit_log_detail(uuid) TO authenticated;
GRANT ALL ON FUNCTION pharmacy.fetch_batch_audit(uuid, text, timestamptz, timestamptz, uuid, integer, integer) TO authenticated;
GRANT ALL ON FUNCTION pharmacy.fetch_batch_registry(text, integer, integer) TO authenticated;
GRANT ALL ON FUNCTION pharmacy.fetch_controlled_audit(text, uuid, timestamptz, timestamptz, integer, integer) TO authenticated;
GRANT ALL ON FUNCTION pharmacy.fetch_prescription_audit(text, text, timestamptz, timestamptz, integer, integer) TO authenticated;
