-- Transactional warehouse creation with default locations and audit.

CREATE OR REPLACE FUNCTION pharmacy.create_warehouse_with_default_locations(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
DECLARE
  v_company_id uuid := pharmacy.get_my_company_id();
  v_user_id uuid := auth.uid();
  v_name text;
  v_description text;
  v_address text;
  v_city text;
  v_manager_name text;
  v_phone text;
  v_opening_hours jsonb;
  v_is_active boolean;
  v_warehouse pharmacy.warehouses%ROWTYPE;
  v_location pharmacy.locations%ROWTYPE;
  v_locations jsonb := '[]'::jsonb;
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Usuario sin empresa asociada';
  END IF;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado';
  END IF;

  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RAISE EXCEPTION 'Payload inválido para crear sucursal';
  END IF;

  v_name := BTRIM(COALESCE(p_payload->>'name', ''));
  IF v_name = '' THEN
    RAISE EXCEPTION 'El nombre de la sucursal es obligatorio';
  END IF;

  v_description := NULLIF(BTRIM(COALESCE(p_payload->>'description', '')), '');
  v_address := NULLIF(BTRIM(COALESCE(p_payload->>'address', '')), '');
  v_city := NULLIF(BTRIM(COALESCE(p_payload->>'city', '')), '');
  v_manager_name := NULLIF(BTRIM(COALESCE(p_payload->>'manager_name', '')), '');
  v_phone := NULLIF(BTRIM(COALESCE(p_payload->>'phone', '')), '');
  v_opening_hours := CASE
    WHEN p_payload ? 'opening_hours' AND p_payload->'opening_hours' IS NOT NULL THEN p_payload->'opening_hours'
    ELSE NULL
  END;
  v_is_active := COALESCE((p_payload->>'is_active')::boolean, true);

  IF EXISTS (
    SELECT 1
    FROM pharmacy.warehouses w
    WHERE w.company_id = v_company_id
      AND COALESCE(w.is_active, true) = true
      AND UPPER(BTRIM(w.name)) = UPPER(v_name)
  ) THEN
    RAISE EXCEPTION 'Ya existe una sucursal activa con el mismo nombre';
  END IF;

  INSERT INTO pharmacy.warehouses (
    company_id,
    name,
    is_active,
    created_by,
    description,
    address,
    city,
    manager_name,
    phone,
    opening_hours
  )
  VALUES (
    v_company_id,
    v_name,
    COALESCE(v_is_active, true),
    v_user_id,
    v_description,
    v_address,
    v_city,
    v_manager_name,
    v_phone,
    v_opening_hours
  )
  RETURNING * INTO v_warehouse;

  FOR v_location IN
    INSERT INTO pharmacy.locations (
      company_id,
      warehouse_id,
      name,
      location_type,
      is_active
    )
    SELECT
      v_company_id,
      v_warehouse.id,
      loc.name,
      loc.location_type,
      true
    FROM (VALUES
      ('CUARENTENA (INBOUND)'::text, 'QUARANTINE'::text),
      ('STORAGE (ALMACENAMIENTO)'::text, 'STORAGE'::text),
      ('SALA DE VENTAS'::text, 'SALES'::text)
    ) AS loc(name, location_type)
    RETURNING *
  LOOP
    v_locations := v_locations || jsonb_build_array(to_jsonb(v_location));
  END LOOP;

  PERFORM pharmacy.log_audit_event(
    'WAREHOUSE_CREATED',
    'Sucursal creada con ubicaciones base',
    jsonb_build_object(
      'warehouse_id', v_warehouse.id,
      'warehouse_name', v_warehouse.name,
      'locations_count', 3,
      'location_types', jsonb_build_array('QUARANTINE', 'STORAGE', 'SALES')
    )
  );

  RETURN jsonb_build_object(
    'warehouse', to_jsonb(v_warehouse),
    'locations', v_locations
  );
END;
$$;

GRANT EXECUTE ON FUNCTION pharmacy.create_warehouse_with_default_locations(jsonb) TO authenticated;
