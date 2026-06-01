-- Harden warehouse edit and soft-deactivate flows with audited RPCs.

CREATE OR REPLACE FUNCTION pharmacy.update_warehouse(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
DECLARE
  v_company_id uuid := pharmacy.get_my_company_id();
  v_user_id uuid := auth.uid();
  v_warehouse_id uuid;
  v_name text;
  v_description text;
  v_address text;
  v_city text;
  v_phone text;
  v_manager_name text;
  v_is_active boolean;
  v_warehouse pharmacy.warehouses%ROWTYPE;
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Usuario sin empresa asociada';
  END IF;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado';
  END IF;

  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RAISE EXCEPTION 'Payload inválido para actualizar sucursal';
  END IF;

  v_warehouse_id := NULLIF(BTRIM(COALESCE(p_payload->>'id', p_payload->>'warehouse_id', '')), '')::uuid;
  IF v_warehouse_id IS NULL THEN
    RAISE EXCEPTION 'warehouse_id es obligatorio';
  END IF;

  v_name := BTRIM(COALESCE(p_payload->>'name', ''));
  IF v_name = '' THEN
    RAISE EXCEPTION 'El nombre de la sucursal es obligatorio';
  END IF;

  SELECT w.*
    INTO v_warehouse
  FROM pharmacy.warehouses w
  WHERE w.id = v_warehouse_id
    AND w.company_id = v_company_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La sucursal no existe o no pertenece a la empresa';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pharmacy.warehouses w
    WHERE w.company_id = v_company_id
      AND w.id <> v_warehouse_id
      AND COALESCE(w.is_active, true) = true
      AND UPPER(BTRIM(w.name)) = UPPER(v_name)
  ) THEN
    RAISE EXCEPTION 'Ya existe otra sucursal activa con el mismo nombre';
  END IF;

  v_description := NULLIF(BTRIM(COALESCE(p_payload->>'description', '')), '');
  v_address := NULLIF(BTRIM(COALESCE(p_payload->>'address', '')), '');
  v_city := NULLIF(BTRIM(COALESCE(p_payload->>'city', '')), '');
  v_phone := NULLIF(BTRIM(COALESCE(p_payload->>'phone', '')), '');
  v_manager_name := NULLIF(BTRIM(COALESCE(p_payload->>'manager_name', p_payload->>'responsible', '')), '');
  v_is_active := COALESCE((p_payload->>'is_active')::boolean, v_warehouse.is_active, true);

  UPDATE pharmacy.warehouses
     SET name = v_name,
         description = v_description,
         address = v_address,
         city = v_city,
         phone = v_phone,
         manager_name = v_manager_name,
         is_active = v_is_active
   WHERE id = v_warehouse_id
     AND company_id = v_company_id
   RETURNING * INTO v_warehouse;

  PERFORM pharmacy.log_audit_event(
    'WAREHOUSE_UPDATED',
    'Sucursal actualizada',
    jsonb_build_object(
      'warehouse_id', v_warehouse.id,
      'warehouse_name', v_warehouse.name,
      'is_active', v_warehouse.is_active
    )
  );

  RETURN jsonb_build_object(
    'warehouse', to_jsonb(v_warehouse)
  );
END;
$$;

CREATE OR REPLACE FUNCTION pharmacy.deactivate_warehouse(p_warehouse_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
DECLARE
  v_company_id uuid := pharmacy.get_my_company_id();
  v_user_id uuid := auth.uid();
  v_warehouse pharmacy.warehouses%ROWTYPE;
  v_active_warehouses_count integer;
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

  SELECT w.*
    INTO v_warehouse
  FROM pharmacy.warehouses w
  WHERE w.id = p_warehouse_id
    AND w.company_id = v_company_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La sucursal no existe o no pertenece a la empresa';
  END IF;

  IF COALESCE(v_warehouse.is_active, true) = false THEN
    RAISE EXCEPTION 'La sucursal ya está desactivada';
  END IF;

  SELECT COUNT(*)
    INTO v_active_warehouses_count
  FROM pharmacy.warehouses w
  WHERE w.company_id = v_company_id
    AND COALESCE(w.is_active, true) = true;

  IF v_active_warehouses_count <= 1 THEN
    RAISE EXCEPTION 'No se puede desactivar el único local activo de la empresa';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pharmacy.pos_sessions s
    WHERE s.company_id = v_company_id
      AND s.warehouse_id = p_warehouse_id
      AND s.status = 'OPEN'
  ) THEN
    RAISE EXCEPTION 'No se puede desactivar la sucursal con caja POS abierta';
  END IF;

  -- TODO: bloquear también por terminales activas si el flujo de negocio lo exige.

  UPDATE pharmacy.warehouses
     SET is_active = false
   WHERE id = p_warehouse_id
     AND company_id = v_company_id
   RETURNING * INTO v_warehouse;

  PERFORM pharmacy.log_audit_event(
    'WAREHOUSE_DEACTIVATED',
    'Sucursal desactivada',
    jsonb_build_object(
      'warehouse_id', v_warehouse.id,
      'warehouse_name', v_warehouse.name
    )
  );

  RETURN jsonb_build_object(
    'warehouse', to_jsonb(v_warehouse)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION pharmacy.update_warehouse(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION pharmacy.deactivate_warehouse(uuid) TO authenticated;
