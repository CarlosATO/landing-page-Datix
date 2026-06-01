-- Fix POS operator PIN hashing to use the extensions schema explicitly.

CREATE OR REPLACE FUNCTION pharmacy.create_pos_operator(
  p_warehouse_id uuid,
  p_full_name text,
  p_pin_code text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public', 'extensions'
AS $$
DECLARE
  v_company_id uuid := pharmacy.get_my_company_id();
  v_user_id uuid := auth.uid();
  v_operator_name text;
  v_operator pharmacy.pos_operators%ROWTYPE;
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Usuario sin empresa asociada';
  END IF;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado';
  END IF;

  IF p_warehouse_id IS NULL THEN
    RAISE EXCEPTION 'warehouse_id es obligatorio';
  END IF;

  IF BTRIM(COALESCE(p_full_name, '')) = '' THEN
    RAISE EXCEPTION 'El nombre del operador es obligatorio';
  END IF;

  IF p_pin_code IS NULL OR LENGTH(BTRIM(p_pin_code)) <> 4 OR BTRIM(p_pin_code) !~ '^[0-9]{4}$' THEN
    RAISE EXCEPTION 'El PIN debe tener exactamente 4 dígitos';
  END IF;

  PERFORM 1
    FROM pharmacy.warehouses w
   WHERE w.id = p_warehouse_id
     AND w.company_id = v_company_id
     AND COALESCE(w.is_active, true) = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El local no existe o no pertenece a la empresa';
  END IF;

  v_operator_name := UPPER(BTRIM(p_full_name));

  IF EXISTS (
    SELECT 1
    FROM pharmacy.pos_operators po
    WHERE po.company_id = v_company_id
      AND po.warehouse_id = p_warehouse_id
      AND po.is_active = true
      AND UPPER(BTRIM(po.full_name)) = v_operator_name
  ) THEN
    RAISE EXCEPTION 'Ya existe un operador activo con ese nombre en esta sucursal';
  END IF;

  INSERT INTO pharmacy.pos_operators (
    company_id,
    warehouse_id,
    full_name,
    pin_hash,
    is_active
  )
  VALUES (
    v_company_id,
    p_warehouse_id,
    v_operator_name,
    crypt(BTRIM(p_pin_code), extensions.gen_salt('bf')),
    true
  )
  RETURNING * INTO v_operator;

  PERFORM pharmacy.log_audit_event(
    'POS_OPERATOR_CREATED',
    'Operador POS creado',
    jsonb_build_object(
      'operator_id', v_operator.id,
      'warehouse_id', v_operator.warehouse_id,
      'operator_name', v_operator.full_name,
      'is_active', v_operator.is_active
    )
  );

  RETURN jsonb_build_object(
    'operator', jsonb_build_object(
      'id', v_operator.id,
      'company_id', v_operator.company_id,
      'warehouse_id', v_operator.warehouse_id,
      'full_name', v_operator.full_name,
      'is_active', v_operator.is_active,
      'created_at', v_operator.created_at
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION pharmacy.reset_pos_operator_pin(
  p_operator_id uuid,
  p_warehouse_id uuid,
  p_pin_code text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public', 'extensions'
AS $$
DECLARE
  v_company_id uuid := pharmacy.get_my_company_id();
  v_user_id uuid := auth.uid();
  v_operator pharmacy.pos_operators%ROWTYPE;
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Usuario sin empresa asociada';
  END IF;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado';
  END IF;

  IF p_operator_id IS NULL THEN
    RAISE EXCEPTION 'operator_id es obligatorio';
  END IF;

  IF p_warehouse_id IS NULL THEN
    RAISE EXCEPTION 'warehouse_id es obligatorio';
  END IF;

  IF p_pin_code IS NULL OR LENGTH(BTRIM(p_pin_code)) <> 4 OR BTRIM(p_pin_code) !~ '^[0-9]{4}$' THEN
    RAISE EXCEPTION 'El PIN debe tener exactamente 4 dígitos';
  END IF;

  SELECT po.*
    INTO v_operator
  FROM pharmacy.pos_operators po
  JOIN pharmacy.warehouses w ON w.id = po.warehouse_id AND w.company_id = v_company_id AND COALESCE(w.is_active, true) = true
  WHERE po.id = p_operator_id
    AND po.company_id = v_company_id
    AND po.warehouse_id = p_warehouse_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Operador POS no encontrado para la empresa/sucursal indicada';
  END IF;

  UPDATE pharmacy.pos_operators
     SET pin_hash = crypt(BTRIM(p_pin_code), extensions.gen_salt('bf'))
   WHERE id = p_operator_id
     AND company_id = v_company_id
   RETURNING * INTO v_operator;

  PERFORM pharmacy.log_audit_event(
    'POS_OPERATOR_PIN_RESET',
    'PIN de operador POS restablecido',
    jsonb_build_object(
      'operator_id', v_operator.id,
      'warehouse_id', v_operator.warehouse_id,
      'operator_name', v_operator.full_name
    )
  );

  RETURN jsonb_build_object(
    'operator', jsonb_build_object(
      'id', v_operator.id,
      'company_id', v_operator.company_id,
      'warehouse_id', v_operator.warehouse_id,
      'full_name', v_operator.full_name,
      'is_active', v_operator.is_active,
      'created_at', v_operator.created_at
    )
  );
END;
$$;
