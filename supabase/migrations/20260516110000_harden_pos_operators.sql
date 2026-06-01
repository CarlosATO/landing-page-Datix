-- Harden POS operators with tenant-aware audited RPCs.

DROP FUNCTION IF EXISTS pharmacy.create_pos_operator(text, text, uuid);
DROP FUNCTION IF EXISTS pharmacy.create_pos_operator(uuid, uuid, text, text);
DROP FUNCTION IF EXISTS pharmacy.update_pos_operator(jsonb);
DROP FUNCTION IF EXISTS pharmacy.deactivate_pos_operator(uuid);
DROP FUNCTION IF EXISTS pharmacy.reset_pos_operator_pin(uuid, uuid, uuid, text);
DROP FUNCTION IF EXISTS pharmacy.reset_pos_operator_pin(uuid, text);
DROP FUNCTION IF EXISTS pharmacy.verify_pos_operator_pin(uuid, uuid, uuid, text);
DROP FUNCTION IF EXISTS pharmacy.verify_pos_operator_pin(uuid, text);

CREATE OR REPLACE FUNCTION pharmacy.create_pos_operator(
  p_warehouse_id uuid,
  p_full_name text,
  p_pin_code text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
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
    crypt(BTRIM(p_pin_code), gen_salt('bf')),
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

CREATE OR REPLACE FUNCTION pharmacy.update_pos_operator(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
DECLARE
  v_company_id uuid := pharmacy.get_my_company_id();
  v_user_id uuid := auth.uid();
  v_operator_id uuid;
  v_warehouse_id uuid;
  v_full_name text;
  v_is_active boolean;
  v_operator pharmacy.pos_operators%ROWTYPE;
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Usuario sin empresa asociada';
  END IF;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado';
  END IF;

  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RAISE EXCEPTION 'Payload inválido para actualizar operador POS';
  END IF;

  v_operator_id := NULLIF(BTRIM(COALESCE(p_payload->>'operator_id', p_payload->>'id', '')), '')::uuid;
  IF v_operator_id IS NULL THEN
    RAISE EXCEPTION 'operator_id es obligatorio';
  END IF;

  v_full_name := BTRIM(COALESCE(p_payload->>'full_name', p_payload->>'operator_name', p_payload->>'name', ''));
  IF v_full_name = '' THEN
    RAISE EXCEPTION 'El nombre del operador es obligatorio';
  END IF;

  SELECT po.*
    INTO v_operator
  FROM pharmacy.pos_operators po
  WHERE po.id = v_operator_id
    AND po.company_id = v_company_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Operador POS no encontrado o no pertenece a la empresa';
  END IF;

  v_warehouse_id := NULLIF(BTRIM(COALESCE(p_payload->>'warehouse_id', '')), '')::uuid;
  IF v_warehouse_id IS NULL THEN
    v_warehouse_id := v_operator.warehouse_id;
  ELSE
    PERFORM 1
    FROM pharmacy.warehouses w
    WHERE w.id = v_warehouse_id
      AND w.company_id = v_company_id
      AND COALESCE(w.is_active, true) = true;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'El local no existe o no pertenece a la empresa';
    END IF;
  END IF;

  v_full_name := UPPER(BTRIM(v_full_name));
  v_is_active := COALESCE(NULLIF(BTRIM(COALESCE(p_payload->>'is_active', '')), '')::boolean, v_operator.is_active);

  IF EXISTS (
    SELECT 1
    FROM pharmacy.pos_operators po
    WHERE po.company_id = v_company_id
      AND po.warehouse_id = v_warehouse_id
      AND po.id <> v_operator_id
      AND po.is_active = true
      AND UPPER(BTRIM(po.full_name)) = v_full_name
  ) THEN
    RAISE EXCEPTION 'Ya existe otro operador activo con ese nombre en esta sucursal';
  END IF;

  UPDATE pharmacy.pos_operators
     SET full_name = v_full_name,
         warehouse_id = v_warehouse_id,
         is_active = v_is_active
   WHERE id = v_operator_id
     AND company_id = v_company_id
   RETURNING * INTO v_operator;

  PERFORM pharmacy.log_audit_event(
    'POS_OPERATOR_UPDATED',
    'Operador POS actualizado',
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

CREATE OR REPLACE FUNCTION pharmacy.deactivate_pos_operator(p_operator_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
DECLARE
  v_company_id uuid := pharmacy.get_my_company_id();
  v_user_id uuid := auth.uid();
  v_operator pharmacy.pos_operators%ROWTYPE;
  v_open_sessions integer;
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

  SELECT po.*
    INTO v_operator
  FROM pharmacy.pos_operators po
  WHERE po.id = p_operator_id
    AND po.company_id = v_company_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Operador POS no encontrado o no pertenece a la empresa';
  END IF;

  IF COALESCE(v_operator.is_active, true) = false THEN
    RAISE EXCEPTION 'El operador ya está desactivado';
  END IF;

  SELECT COUNT(*)
    INTO v_open_sessions
  FROM pharmacy.pos_sessions s
  WHERE s.company_id = v_company_id
    AND s.operator_id = p_operator_id
    AND s.status = 'OPEN';

  IF v_open_sessions > 0 THEN
    RAISE EXCEPTION 'No se puede desactivar un operador con caja POS abierta';
  END IF;

  UPDATE pharmacy.pos_operators
     SET is_active = false
   WHERE id = p_operator_id
     AND company_id = v_company_id
   RETURNING * INTO v_operator;

  PERFORM pharmacy.log_audit_event(
    'POS_OPERATOR_DEACTIVATED',
    'Operador POS desactivado',
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

CREATE OR REPLACE FUNCTION pharmacy.reset_pos_operator_pin(
  p_operator_id uuid,
  p_warehouse_id uuid,
  p_pin_code text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
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
     SET pin_hash = crypt(BTRIM(p_pin_code), gen_salt('bf'))
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

CREATE OR REPLACE FUNCTION pharmacy.verify_pos_operator_pin(
  p_operator_id uuid,
  p_warehouse_id uuid,
  p_pin_code text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
DECLARE
  v_company_id uuid := pharmacy.get_my_company_id();
  v_operator record;
  v_valid boolean := false;
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Usuario sin empresa asociada';
  END IF;

  IF p_operator_id IS NULL THEN
    RAISE EXCEPTION 'operator_id es obligatorio';
  END IF;

  IF p_pin_code IS NULL OR LENGTH(BTRIM(p_pin_code)) <> 4 OR BTRIM(p_pin_code) !~ '^[0-9]{4}$' THEN
    RAISE EXCEPTION 'El PIN debe tener exactamente 4 dígitos';
  END IF;

  SELECT
    po.id AS operator_id,
    po.full_name AS operator_name,
    po.warehouse_id,
    po.is_active,
    po.pin_hash
  INTO v_operator
  FROM pharmacy.pos_operators po
  JOIN pharmacy.warehouses w ON w.id = po.warehouse_id AND w.company_id = v_company_id AND COALESCE(w.is_active, true) = true
  WHERE po.id = p_operator_id
    AND po.company_id = v_company_id
    AND po.is_active = true
    AND (p_warehouse_id IS NULL OR po.warehouse_id = p_warehouse_id)
  LIMIT 1;

  IF FOUND THEN
    v_valid := (v_operator.pin_hash = crypt(BTRIM(p_pin_code), v_operator.pin_hash));
  END IF;

  -- TODO: registrar intentos fallidos en una tabla de seguridad si el proyecto ya la incorpora.

  RETURN jsonb_build_object(
    'operator_id', COALESCE(v_operator.operator_id, p_operator_id),
    'operator_name', COALESCE(v_operator.operator_name, null),
    'warehouse_id', COALESCE(v_operator.warehouse_id, p_warehouse_id),
    'is_valid', COALESCE(v_valid, false)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION pharmacy.create_pos_operator(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION pharmacy.update_pos_operator(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION pharmacy.deactivate_pos_operator(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION pharmacy.reset_pos_operator_pin(uuid, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION pharmacy.verify_pos_operator_pin(uuid, uuid, text) TO authenticated;
