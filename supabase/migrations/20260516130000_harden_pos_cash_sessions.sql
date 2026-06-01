-- Harden POS cash/session flows behind backend RPCs.

CREATE OR REPLACE FUNCTION pharmacy.pre_open_pos_session(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public', 'extensions'
AS $$
DECLARE
  v_company_id uuid := pharmacy.get_my_company_id();
  v_user_id uuid := auth.uid();
  v_warehouse_id uuid;
  v_terminal_id uuid;
  v_operator_id uuid;
  v_initial_cash numeric := 0;
  v_session pharmacy.pos_sessions%ROWTYPE;
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Usuario sin empresa asociada';
  END IF;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado';
  END IF;

  v_warehouse_id := NULLIF(BTRIM(COALESCE(p_payload->>'warehouse_id', '')), '')::uuid;
  v_terminal_id := NULLIF(BTRIM(COALESCE(p_payload->>'terminal_id', '')), '')::uuid;
  v_operator_id := NULLIF(BTRIM(COALESCE(p_payload->>'operator_id', '')), '')::uuid;
  v_initial_cash := COALESCE(
    NULLIF(BTRIM(COALESCE(p_payload->>'initial_cash', '')), '')::numeric,
    NULLIF(BTRIM(COALESCE(p_payload->>'opening_balance', '')), '')::numeric,
    0
  );

  IF v_warehouse_id IS NULL THEN
    RAISE EXCEPTION 'warehouse_id es obligatorio';
  END IF;

  IF v_initial_cash < 0 THEN
    RAISE EXCEPTION 'El efectivo inicial no puede ser negativo';
  END IF;

  IF v_operator_id IS NULL THEN
    RAISE EXCEPTION 'operator_id es obligatorio';
  END IF;

  PERFORM 1
  FROM pharmacy.warehouses w
  WHERE w.id = v_warehouse_id
    AND w.company_id = v_company_id
    AND COALESCE(w.is_active, true) = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La sucursal no existe o no pertenece a la empresa';
  END IF;

  IF v_terminal_id IS NOT NULL THEN
    PERFORM 1
    FROM pharmacy.pos_terminals t
    WHERE t.id = v_terminal_id
      AND t.company_id = v_company_id
      AND t.warehouse_id = v_warehouse_id
      AND COALESCE(t.is_active, true) = true;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'La terminal no existe o no pertenece a la sucursal';
    END IF;
  END IF;

  IF v_operator_id IS NOT NULL THEN
    PERFORM 1
    FROM pharmacy.pos_operators o
    WHERE o.id = v_operator_id
      AND o.company_id = v_company_id
      AND o.warehouse_id = v_warehouse_id
      AND COALESCE(o.is_active, true) = true;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Operador POS no válido para la sucursal';
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pharmacy.pos_sessions s
    WHERE s.company_id = v_company_id
      AND s.warehouse_id = v_warehouse_id
      AND COALESCE(s.status, 'PENDING') IN ('PENDING', 'OPEN')
      AND (v_terminal_id IS NULL OR s.terminal_id = v_terminal_id)
  ) THEN
    RAISE EXCEPTION 'Ya existe una sesión POS activa o pendiente para este terminal o sucursal';
  END IF;

  INSERT INTO pharmacy.pos_sessions (
    company_id,
    user_id,
    warehouse_id,
    terminal_id,
    operator_id,
    opening_balance,
    status,
    start_time
  )
  VALUES (
    v_company_id,
    v_user_id,
    v_warehouse_id,
    v_terminal_id,
    v_operator_id,
    v_initial_cash,
    'PENDING',
    NOW()
  )
  RETURNING * INTO v_session;

  PERFORM pharmacy.log_audit_event(
    'POS_SESSION_PREOPENED',
    'Caja pre-abierta',
    jsonb_build_object(
      'session_id', v_session.id,
      'warehouse_id', v_session.warehouse_id,
      'terminal_id', v_session.terminal_id,
      'operator_id', v_session.operator_id,
      'amount', v_session.opening_balance
    )
  );

  RETURN jsonb_build_object('session', to_jsonb(v_session));
END;
$$;

CREATE OR REPLACE FUNCTION pharmacy.activate_pos_session(
  p_session_id uuid,
  p_operator_id uuid,
  p_pin_code text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public', 'extensions'
AS $$
DECLARE
  v_company_id uuid := pharmacy.get_my_company_id();
  v_user_id uuid := auth.uid();
  v_session pharmacy.pos_sessions%ROWTYPE;
  v_operator pharmacy.pos_operators%ROWTYPE;
  v_pin_ok boolean := false;
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Usuario sin empresa asociada';
  END IF;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado';
  END IF;

  IF p_session_id IS NULL THEN
    RAISE EXCEPTION 'session_id es obligatorio';
  END IF;

  IF p_operator_id IS NULL THEN
    RAISE EXCEPTION 'operator_id es obligatorio';
  END IF;

  IF p_pin_code IS NULL OR LENGTH(BTRIM(p_pin_code)) <> 4 OR BTRIM(p_pin_code) !~ '^[0-9]{4}$' THEN
    RAISE EXCEPTION 'El PIN debe tener exactamente 4 dígitos';
  END IF;

  SELECT s.*
  INTO v_session
  FROM pharmacy.pos_sessions s
  WHERE s.id = p_session_id
    AND s.company_id = v_company_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sesión POS no encontrada para la empresa';
  END IF;

  IF v_session.status <> 'PENDING' THEN
    RAISE EXCEPTION 'La sesión no está en estado pendiente';
  END IF;

  IF v_session.operator_id IS NOT NULL AND v_session.operator_id <> p_operator_id THEN
    RAISE EXCEPTION 'La sesión fue asignada a otro operador';
  END IF;

  SELECT o.*
  INTO v_operator
  FROM pharmacy.pos_operators o
  WHERE o.id = p_operator_id
    AND o.company_id = v_company_id
    AND o.warehouse_id = v_session.warehouse_id
    AND COALESCE(o.is_active, true) = true
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Operador POS no válido para la sesión';
  END IF;

  v_pin_ok := (v_operator.pin_hash = extensions.crypt(BTRIM(p_pin_code), v_operator.pin_hash));

  IF NOT v_pin_ok THEN
    RAISE EXCEPTION 'PIN inválido';
  END IF;

  UPDATE pharmacy.pos_sessions
  SET status = 'OPEN',
      operator_id = p_operator_id,
      start_time = COALESCE(start_time, NOW())
  WHERE id = v_session.id
  RETURNING * INTO v_session;

  PERFORM pharmacy.log_audit_event(
    'POS_SESSION_ACTIVATED',
    'Caja activada',
    jsonb_build_object(
      'session_id', v_session.id,
      'warehouse_id', v_session.warehouse_id,
      'terminal_id', v_session.terminal_id,
      'operator_id', v_session.operator_id,
      'amount', v_session.opening_balance
    )
  );

  RETURN jsonb_build_object('session', to_jsonb(v_session));
END;
$$;

CREATE OR REPLACE FUNCTION pharmacy.open_pos_session(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public', 'extensions'
AS $$
DECLARE
  v_company_id uuid := pharmacy.get_my_company_id();
  v_user_id uuid := auth.uid();
  v_warehouse_id uuid;
  v_terminal_id uuid;
  v_operator_id uuid;
  v_pin_code text;
  v_initial_cash numeric := 0;
  v_session pharmacy.pos_sessions%ROWTYPE;
  v_operator pharmacy.pos_operators%ROWTYPE;
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Usuario sin empresa asociada';
  END IF;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado';
  END IF;

  v_warehouse_id := NULLIF(BTRIM(COALESCE(p_payload->>'warehouse_id', '')), '')::uuid;
  v_terminal_id := NULLIF(BTRIM(COALESCE(p_payload->>'terminal_id', '')), '')::uuid;
  v_operator_id := NULLIF(BTRIM(COALESCE(p_payload->>'operator_id', '')), '')::uuid;
  v_pin_code := NULLIF(BTRIM(COALESCE(p_payload->>'pin_code', '')), '');
  v_initial_cash := COALESCE(
    NULLIF(BTRIM(COALESCE(p_payload->>'initial_cash', '')), '')::numeric,
    NULLIF(BTRIM(COALESCE(p_payload->>'opening_balance', '')), '')::numeric,
    0
  );

  IF v_warehouse_id IS NULL THEN
    RAISE EXCEPTION 'warehouse_id es obligatorio';
  END IF;

  IF v_initial_cash < 0 THEN
    RAISE EXCEPTION 'El efectivo inicial no puede ser negativo';
  END IF;

  PERFORM 1
  FROM pharmacy.warehouses w
  WHERE w.id = v_warehouse_id
    AND w.company_id = v_company_id
    AND COALESCE(w.is_active, true) = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La sucursal no existe o no pertenece a la empresa';
  END IF;

  IF v_terminal_id IS NOT NULL THEN
    PERFORM 1
    FROM pharmacy.pos_terminals t
    WHERE t.id = v_terminal_id
      AND t.company_id = v_company_id
      AND t.warehouse_id = v_warehouse_id
      AND COALESCE(t.is_active, true) = true;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'La terminal no existe o no pertenece a la sucursal';
    END IF;
  END IF;

  IF v_operator_id IS NULL THEN
    RAISE EXCEPTION 'operator_id es obligatorio';
  END IF;

  SELECT o.*
  INTO v_operator
  FROM pharmacy.pos_operators o
  WHERE o.id = v_operator_id
    AND o.company_id = v_company_id
    AND o.warehouse_id = v_warehouse_id
    AND COALESCE(o.is_active, true) = true
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Operador POS no válido para la sucursal';
  END IF;

  IF v_pin_code IS NULL OR LENGTH(BTRIM(v_pin_code)) <> 4 OR BTRIM(v_pin_code) !~ '^[0-9]{4}$' THEN
    RAISE EXCEPTION 'El PIN debe tener exactamente 4 dígitos';
  END IF;

  IF v_operator.pin_hash <> extensions.crypt(BTRIM(v_pin_code), v_operator.pin_hash) THEN
    RAISE EXCEPTION 'PIN inválido';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pharmacy.pos_sessions s
    WHERE s.company_id = v_company_id
      AND s.warehouse_id = v_warehouse_id
      AND COALESCE(s.status, 'OPEN') IN ('PENDING', 'OPEN')
      AND (v_terminal_id IS NULL OR s.terminal_id = v_terminal_id)
  ) THEN
    RAISE EXCEPTION 'Ya existe una sesión POS activa o pendiente para este terminal o sucursal';
  END IF;

  INSERT INTO pharmacy.pos_sessions (
    company_id,
    user_id,
    warehouse_id,
    terminal_id,
    operator_id,
    opening_balance,
    status,
    start_time
  )
  VALUES (
    v_company_id,
    v_user_id,
    v_warehouse_id,
    v_terminal_id,
    v_operator_id,
    v_initial_cash,
    'OPEN',
    NOW()
  )
  RETURNING * INTO v_session;

  PERFORM pharmacy.log_audit_event(
    'POS_SESSION_OPENED',
    'Caja abierta',
    jsonb_build_object(
      'session_id', v_session.id,
      'warehouse_id', v_session.warehouse_id,
      'terminal_id', v_session.terminal_id,
      'operator_id', v_session.operator_id,
      'amount', v_session.opening_balance
    )
  );

  RETURN jsonb_build_object('session', to_jsonb(v_session));
END;
$$;

CREATE OR REPLACE FUNCTION pharmacy.create_cash_movement(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
DECLARE
  v_company_id uuid := pharmacy.get_my_company_id();
  v_user_id uuid := auth.uid();
  v_session_id uuid;
  v_movement_type text;
  v_amount numeric := 0;
  v_reason text;
  v_session pharmacy.pos_sessions%ROWTYPE;
  v_movement pharmacy.cash_movements%ROWTYPE;
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Usuario sin empresa asociada';
  END IF;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado';
  END IF;

  v_session_id := NULLIF(BTRIM(COALESCE(p_payload->>'session_id', '')), '')::uuid;
  v_movement_type := UPPER(BTRIM(COALESCE(p_payload->>'movement_type', '')));
  v_amount := COALESCE(NULLIF(BTRIM(COALESCE(p_payload->>'amount', '')), '')::numeric, 0);
  v_reason := BTRIM(COALESCE(p_payload->>'reason', p_payload->>'description', ''));

  IF v_session_id IS NULL THEN
    RAISE EXCEPTION 'session_id es obligatorio';
  END IF;

  IF v_movement_type NOT IN ('IN', 'OUT') THEN
    RAISE EXCEPTION 'movement_type inválido';
  END IF;

  IF v_amount <= 0 THEN
    RAISE EXCEPTION 'El monto debe ser mayor a cero';
  END IF;

  IF v_reason = '' THEN
    RAISE EXCEPTION 'El motivo es obligatorio';
  END IF;

  SELECT s.*
  INTO v_session
  FROM pharmacy.pos_sessions s
  WHERE s.id = v_session_id
    AND s.company_id = v_company_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sesión POS no encontrada para la empresa';
  END IF;

  IF v_session.status <> 'OPEN' THEN
    RAISE EXCEPTION 'La sesión no está abierta';
  END IF;

  INSERT INTO pharmacy.cash_movements (
    company_id,
    session_id,
    user_id,
    movement_type,
    amount,
    reason
  )
  VALUES (
    v_company_id,
    v_session_id,
    v_user_id,
    v_movement_type,
    v_amount,
    v_reason
  )
  RETURNING * INTO v_movement;

  PERFORM pharmacy.log_audit_event(
    'CASH_MOVEMENT_CREATED',
    CASE WHEN v_movement_type = 'IN' THEN 'Ingreso de efectivo' ELSE 'Retiro de efectivo' END,
    jsonb_build_object(
      'cash_movement_id', v_movement.id,
      'session_id', v_session_id,
      'warehouse_id', v_session.warehouse_id,
      'operator_id', v_session.operator_id,
      'movement_type', v_movement_type,
      'amount', v_amount,
      'reason', v_reason
    )
  );

  RETURN jsonb_build_object('movement', to_jsonb(v_movement));
END;
$$;

CREATE OR REPLACE FUNCTION pharmacy.close_pos_session(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public', 'extensions'
AS $$
DECLARE
  v_company_id uuid := pharmacy.get_my_company_id();
  v_user_id uuid := auth.uid();
  v_session_id uuid;
  v_operator_id uuid;
  v_pin_code text;
  v_counted_cash numeric := 0;
  v_session pharmacy.pos_sessions%ROWTYPE;
  v_operator pharmacy.pos_operators%ROWTYPE;
  v_cash_sales numeric := 0;
  v_card_sales numeric := 0;
  v_transfer_sales numeric := 0;
  v_total_sales numeric := 0;
  v_cash_entries numeric := 0;
  v_cash_outflows numeric := 0;
  v_total_cash_movements numeric := 0;
  v_expected_cash numeric := 0;
  v_difference numeric := 0;
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Usuario sin empresa asociada';
  END IF;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado';
  END IF;

  v_session_id := NULLIF(BTRIM(COALESCE(p_payload->>'session_id', '')), '')::uuid;
  v_operator_id := NULLIF(BTRIM(COALESCE(p_payload->>'operator_id', '')), '')::uuid;
  v_pin_code := NULLIF(BTRIM(COALESCE(p_payload->>'pin_code', '')), '');
  v_counted_cash := COALESCE(
    NULLIF(BTRIM(COALESCE(p_payload->>'counted_cash', '')), '')::numeric,
    NULLIF(BTRIM(COALESCE(p_payload->>'closing_balance', '')), '')::numeric,
    0
  );

  IF v_session_id IS NULL THEN
    RAISE EXCEPTION 'session_id es obligatorio';
  END IF;

  IF v_counted_cash < 0 THEN
    RAISE EXCEPTION 'El efectivo contado no puede ser negativo';
  END IF;

  IF v_operator_id IS NULL THEN
    RAISE EXCEPTION 'operator_id es obligatorio';
  END IF;

  IF v_pin_code IS NULL OR LENGTH(BTRIM(v_pin_code)) <> 4 OR BTRIM(v_pin_code) !~ '^[0-9]{4}$' THEN
    RAISE EXCEPTION 'El PIN debe tener exactamente 4 dígitos';
  END IF;

  SELECT s.*
  INTO v_session
  FROM pharmacy.pos_sessions s
  WHERE s.id = v_session_id
    AND s.company_id = v_company_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sesión POS no encontrada para la empresa';
  END IF;

  IF v_session.status <> 'OPEN' THEN
    RAISE EXCEPTION 'La sesión no está abierta';
  END IF;

  SELECT o.*
  INTO v_operator
  FROM pharmacy.pos_operators o
  WHERE o.id = v_operator_id
    AND o.company_id = v_company_id
    AND o.warehouse_id = v_session.warehouse_id
    AND COALESCE(o.is_active, true) = true
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Operador POS no válido para la sesión';
  END IF;

  IF v_operator.pin_hash <> extensions.crypt(BTRIM(v_pin_code), v_operator.pin_hash) THEN
    RAISE EXCEPTION 'PIN inválido';
  END IF;

  SELECT
    COALESCE(SUM(CASE WHEN UPPER(COALESCE(s.payment_method, 'CASH')) = 'CASH' THEN s.total_amount ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN UPPER(COALESCE(s.payment_method, 'CASH')) = 'CARD' THEN s.total_amount ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN UPPER(COALESCE(s.payment_method, 'CASH')) = 'TRANSFER' THEN s.total_amount ELSE 0 END), 0),
    COALESCE(SUM(s.total_amount), 0)
  INTO v_cash_sales, v_card_sales, v_transfer_sales, v_total_sales
  FROM pharmacy.sales s
  WHERE s.company_id = v_company_id
    AND s.session_id = v_session_id;

  SELECT
    COALESCE(SUM(CASE WHEN cm.movement_type = 'IN' THEN cm.amount ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN cm.movement_type = 'OUT' THEN cm.amount ELSE 0 END), 0)
  INTO v_cash_entries, v_cash_outflows
  FROM pharmacy.cash_movements cm
  WHERE cm.company_id = v_company_id
    AND cm.session_id = v_session_id;

  v_total_cash_movements := v_cash_entries - v_cash_outflows;
  v_expected_cash := COALESCE(v_session.opening_balance, 0) + v_cash_sales + v_cash_entries - v_cash_outflows;
  v_difference := v_counted_cash - v_expected_cash;

  UPDATE pharmacy.pos_sessions
  SET status = 'CLOSED',
      closing_balance = v_counted_cash,
      difference = v_difference,
      end_time = NOW(),
      operator_id = COALESCE(v_session.operator_id, v_operator_id)
  WHERE id = v_session_id
  RETURNING * INTO v_session;

  PERFORM pharmacy.log_audit_event(
    'POS_SESSION_CLOSED',
    'Caja cerrada',
    jsonb_build_object(
      'session_id', v_session.id,
      'warehouse_id', v_session.warehouse_id,
      'terminal_id', v_session.terminal_id,
      'operator_id', v_session.operator_id,
      'counted_cash', v_counted_cash,
      'expected_cash', v_expected_cash,
      'difference', v_difference,
      'cash_sales', v_cash_sales,
      'card_sales', v_card_sales,
      'transfer_sales', v_transfer_sales,
      'cash_entries', v_cash_entries,
      'cash_outflows', v_cash_outflows
    )
  );

  RETURN jsonb_build_object(
    'session', to_jsonb(v_session),
    'summary', jsonb_build_object(
      'cash_sales', v_cash_sales,
      'card_sales', v_card_sales,
      'transfer_sales', v_transfer_sales,
      'total_sales', v_total_sales,
      'cash_entries', v_cash_entries,
      'cash_outflows', v_cash_outflows,
      'total_cash_movements', v_total_cash_movements,
      'expected_cash', v_expected_cash,
      'counted_cash', v_counted_cash,
      'difference', v_difference
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION pharmacy.fetch_pos_session_history(
  p_warehouse_id uuid DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
) RETURNS TABLE(
  session_id uuid,
  warehouse jsonb,
  terminal jsonb,
  operator jsonb,
  opened_at timestamptz,
  closed_at timestamptz,
  status text,
  initial_cash numeric,
  counted_cash numeric,
  expected_cash numeric,
  difference numeric,
  total_sales numeric,
  total_cash_movements numeric
) 
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
  WITH my_company AS (
    SELECT pharmacy.get_my_company_id() AS company_id
  ),
  sessions AS (
    SELECT s.*
    FROM pharmacy.pos_sessions s
    JOIN my_company mc ON mc.company_id = s.company_id
    WHERE p_warehouse_id IS NULL OR s.warehouse_id = p_warehouse_id
  ),
  sales_totals AS (
    SELECT
      s.session_id,
      COALESCE(SUM(CASE WHEN UPPER(COALESCE(s.payment_method, 'CASH')) = 'CASH' THEN s.total_amount ELSE 0 END), 0) AS cash_sales,
      COALESCE(SUM(CASE WHEN UPPER(COALESCE(s.payment_method, 'CASH')) = 'CARD' THEN s.total_amount ELSE 0 END), 0) AS card_sales,
      COALESCE(SUM(CASE WHEN UPPER(COALESCE(s.payment_method, 'CASH')) = 'TRANSFER' THEN s.total_amount ELSE 0 END), 0) AS transfer_sales,
      COALESCE(SUM(s.total_amount), 0) AS total_sales
    FROM pharmacy.sales s
    JOIN my_company mc ON mc.company_id = s.company_id
    WHERE s.session_id IN (SELECT id FROM sessions)
    GROUP BY s.session_id
  ),
  movement_totals AS (
    SELECT
      cm.session_id,
      COALESCE(SUM(CASE WHEN cm.movement_type = 'IN' THEN cm.amount ELSE 0 END), 0) AS cash_entries,
      COALESCE(SUM(CASE WHEN cm.movement_type = 'OUT' THEN cm.amount ELSE 0 END), 0) AS cash_outflows,
      COALESCE(SUM(CASE WHEN cm.movement_type = 'IN' THEN cm.amount ELSE -cm.amount END), 0) AS total_cash_movements
    FROM pharmacy.cash_movements cm
    JOIN my_company mc ON mc.company_id = cm.company_id
    WHERE cm.session_id IN (SELECT id FROM sessions)
    GROUP BY cm.session_id
  )
  SELECT
    s.id AS session_id,
    jsonb_build_object('id', w.id, 'name', w.name) AS warehouse,
    CASE WHEN t.id IS NULL THEN NULL ELSE jsonb_build_object('id', t.id, 'name', t.name) END AS terminal,
    CASE WHEN o.id IS NULL THEN NULL ELSE jsonb_build_object('id', o.id, 'full_name', o.full_name) END AS operator,
    s.start_time AS opened_at,
    s.end_time AS closed_at,
    s.status,
    s.opening_balance AS initial_cash,
    s.closing_balance AS counted_cash,
    (COALESCE(s.opening_balance, 0) + COALESCE(st.cash_sales, 0) + COALESCE(mt.cash_entries, 0) - COALESCE(mt.cash_outflows, 0)) AS expected_cash,
    s.difference,
    COALESCE(st.total_sales, 0) AS total_sales,
    COALESCE(mt.total_cash_movements, 0) AS total_cash_movements
  FROM sessions s
  JOIN pharmacy.warehouses w ON w.id = s.warehouse_id
  LEFT JOIN pharmacy.pos_terminals t ON t.id = s.terminal_id
  LEFT JOIN pharmacy.pos_operators o ON o.id = s.operator_id
  LEFT JOIN sales_totals st ON st.session_id = s.id
  LEFT JOIN movement_totals mt ON mt.session_id = s.id
  ORDER BY COALESCE(s.end_time, s.start_time) DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 0), 500)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
$$;

GRANT EXECUTE ON FUNCTION pharmacy.pre_open_pos_session(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION pharmacy.activate_pos_session(uuid, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION pharmacy.open_pos_session(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION pharmacy.create_cash_movement(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION pharmacy.close_pos_session(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION pharmacy.fetch_pos_session_history(uuid, integer, integer) TO authenticated;

REVOKE INSERT, UPDATE, DELETE ON TABLE pharmacy.pos_sessions FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE pharmacy.cash_movements FROM authenticated;
