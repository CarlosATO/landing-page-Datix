-- Harden locations behind audited backend RPCs.

CREATE OR REPLACE FUNCTION pharmacy.create_location(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
DECLARE
  v_company_id uuid := pharmacy.get_my_company_id();
  v_user_id uuid := auth.uid();
  v_warehouse_id uuid;
  v_parent_location_id uuid;
  v_parent_location pharmacy.locations%ROWTYPE;
  v_name text;
  v_location_type text;
  v_barcode text;
  v_location pharmacy.locations%ROWTYPE;
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Usuario sin empresa asociada';
  END IF;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado';
  END IF;

  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RAISE EXCEPTION 'Payload inválido para crear ubicación';
  END IF;

  v_warehouse_id := NULLIF(BTRIM(COALESCE(p_payload->>'warehouse_id', '')), '')::uuid;
  v_parent_location_id := NULLIF(BTRIM(COALESCE(p_payload->>'parent_location_id', '')), '')::uuid;
  v_name := BTRIM(COALESCE(p_payload->>'name', ''));
  v_location_type := UPPER(BTRIM(COALESCE(p_payload->>'location_type', '')));
  v_barcode := NULLIF(BTRIM(COALESCE(p_payload->>'barcode', p_payload->>'code', p_payload->>'prefix', '')), '');

  IF v_warehouse_id IS NULL THEN
    RAISE EXCEPTION 'warehouse_id es obligatorio';
  END IF;

  IF v_name = '' THEN
    RAISE EXCEPTION 'El nombre de la ubicación es obligatorio';
  END IF;

  SELECT *
    INTO v_parent_location
  FROM pharmacy.locations l
  WHERE l.id = v_parent_location_id
    AND l.company_id = v_company_id
    AND l.warehouse_id = v_warehouse_id
    AND COALESCE(l.is_active, true) = true
  LIMIT 1;

  IF v_parent_location_id IS NOT NULL AND NOT FOUND THEN
    RAISE EXCEPTION 'La ubicación padre no pertenece a la empresa o no está activa';
  END IF;

  IF v_location_type = '' THEN
    v_location_type := COALESCE(UPPER(v_parent_location.location_type), '');
  END IF;

  IF v_location_type = '' THEN
    RAISE EXCEPTION 'location_type es obligatorio';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pharmacy.warehouses w
    WHERE w.id = v_warehouse_id
      AND w.company_id = v_company_id
      AND COALESCE(w.is_active, true) = true
  ) THEN
    RAISE EXCEPTION 'La bodega no pertenece a la empresa o no está activa';
  END IF;

  IF v_parent_location_id IS NOT NULL AND UPPER(v_parent_location.location_type) <> v_location_type THEN
    RAISE EXCEPTION 'La ubicación hija debe mantener el mismo tipo que su ubicación padre';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pharmacy.locations l
    WHERE l.company_id = v_company_id
      AND l.warehouse_id = v_warehouse_id
      AND COALESCE(l.is_active, true) = true
      AND UPPER(BTRIM(l.name)) = UPPER(v_name)
  ) THEN
    RAISE EXCEPTION 'Ya existe una ubicación activa con el mismo nombre en esta bodega';
  END IF;

  IF v_barcode IS NOT NULL AND EXISTS (
    SELECT 1
    FROM pharmacy.locations l
    WHERE l.company_id = v_company_id
      AND l.warehouse_id = v_warehouse_id
      AND COALESCE(l.is_active, true) = true
      AND UPPER(BTRIM(COALESCE(l.barcode, ''))) = UPPER(v_barcode)
  ) THEN
    RAISE EXCEPTION 'Ya existe una ubicación activa con el mismo código/prefijo en esta bodega';
  END IF;

  INSERT INTO pharmacy.locations (
    company_id,
    warehouse_id,
    name,
    location_type,
    parent_location_id,
    barcode,
    is_active
  )
  VALUES (
    v_company_id,
    v_warehouse_id,
    v_name,
    v_location_type,
    v_parent_location_id,
    v_barcode,
    true
  )
  RETURNING * INTO v_location;

  PERFORM pharmacy.log_audit_event(
    'LOCATION_CREATED',
    'Ubicación creada',
    jsonb_build_object(
      'location_id', v_location.id,
      'warehouse_id', v_location.warehouse_id,
      'name', v_location.name,
      'location_type', v_location.location_type,
      'parent_location_id', v_location.parent_location_id,
      'barcode', v_location.barcode
    )
  );

  RETURN jsonb_build_object('location', to_jsonb(v_location));
END;
$$;

CREATE OR REPLACE FUNCTION pharmacy.create_locations_bulk(p_items jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
DECLARE
  v_company_id uuid := pharmacy.get_my_company_id();
  v_user_id uuid := auth.uid();
  v_warehouse_id uuid;
  v_parent_location_id uuid;
  v_parent_location pharmacy.locations%ROWTYPE;
  v_location_type text;
  v_locations jsonb := '[]'::jsonb;
  v_count integer := 0;
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Usuario sin empresa asociada';
  END IF;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Payload inválido para creación masiva de ubicaciones';
  END IF;

  WITH normalized AS (
    SELECT
      ord,
      NULLIF(BTRIM(COALESCE(item->>'name', '')), '') AS name,
      NULLIF(BTRIM(COALESCE(item->>'warehouse_id', '')), '')::uuid AS warehouse_id,
      NULLIF(BTRIM(COALESCE(item->>'parent_location_id', '')), '')::uuid AS parent_location_id,
      UPPER(BTRIM(COALESCE(item->>'location_type', ''))) AS location_type,
      NULLIF(BTRIM(COALESCE(item->>'barcode', item->>'code', item->>'prefix', '')), '') AS barcode
    FROM jsonb_array_elements(p_items) WITH ORDINALITY AS arr(item, ord)
  )
  SELECT warehouse_id, parent_location_id, location_type
    INTO v_warehouse_id, v_parent_location_id, v_location_type
  FROM normalized
  ORDER BY ord
  LIMIT 1;

  IF v_warehouse_id IS NULL THEN
    RAISE EXCEPTION 'warehouse_id es obligatorio en la creación masiva';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pharmacy.warehouses w
    WHERE w.id = v_warehouse_id
      AND w.company_id = v_company_id
      AND COALESCE(w.is_active, true) = true
  ) THEN
    RAISE EXCEPTION 'La bodega no pertenece a la empresa o no está activa';
  END IF;

  IF v_parent_location_id IS NOT NULL THEN
    SELECT *
      INTO v_parent_location
    FROM pharmacy.locations l
    WHERE l.id = v_parent_location_id
      AND l.company_id = v_company_id
      AND l.warehouse_id = v_warehouse_id
      AND COALESCE(l.is_active, true) = true
    LIMIT 1;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'La ubicación padre no pertenece a la empresa o no está activa';
    END IF;

    IF v_location_type = '' THEN
      v_location_type := UPPER(v_parent_location.location_type);
    END IF;
  END IF;

  IF v_location_type = '' THEN
    RAISE EXCEPTION 'location_type es obligatorio';
  END IF;

  IF EXISTS (
    WITH normalized AS (
      SELECT
        NULLIF(BTRIM(COALESCE(item->>'name', '')), '') AS name,
        NULLIF(BTRIM(COALESCE(item->>'barcode', item->>'code', item->>'prefix', '')), '') AS barcode
      FROM jsonb_array_elements(p_items) AS arr(item)
    )
    SELECT 1
    FROM normalized
    WHERE name IS NULL
    LIMIT 1
  ) THEN
    RAISE EXCEPTION 'Cada ubicación requiere un nombre';
  END IF;

  IF EXISTS (
    WITH normalized AS (
      SELECT
        NULLIF(BTRIM(COALESCE(item->>'name', '')), '') AS name
      FROM jsonb_array_elements(p_items) AS arr(item)
    )
    SELECT lower(name)
    FROM normalized
    GROUP BY lower(name)
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION 'Hay nombres duplicados dentro del payload de creación masiva';
  END IF;

  IF EXISTS (
    WITH normalized AS (
      SELECT
        NULLIF(BTRIM(COALESCE(item->>'barcode', item->>'code', item->>'prefix', '')), '') AS barcode
      FROM jsonb_array_elements(p_items) AS arr(item)
    )
    SELECT lower(barcode)
    FROM normalized
    WHERE barcode IS NOT NULL
    GROUP BY lower(barcode)
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION 'Hay códigos/prefijos duplicados dentro del payload de creación masiva';
  END IF;

  IF EXISTS (
    WITH normalized AS (
      SELECT
        NULLIF(BTRIM(COALESCE(item->>'name', '')), '') AS name,
        NULLIF(BTRIM(COALESCE(item->>'barcode', item->>'code', item->>'prefix', '')), '') AS barcode
      FROM jsonb_array_elements(p_items) AS arr(item)
    )
    SELECT 1
    FROM normalized n
    JOIN pharmacy.locations l
      ON l.company_id = v_company_id
     AND l.warehouse_id = v_warehouse_id
     AND COALESCE(l.is_active, true) = true
     AND UPPER(BTRIM(l.name)) = UPPER(n.name)
    LIMIT 1
  ) THEN
    RAISE EXCEPTION 'Ya existe una ubicación activa con el mismo nombre en esta bodega';
  END IF;

  IF EXISTS (
    WITH normalized AS (
      SELECT
        NULLIF(BTRIM(COALESCE(item->>'barcode', item->>'code', item->>'prefix', '')), '') AS barcode
      FROM jsonb_array_elements(p_items) AS arr(item)
    )
    SELECT 1
    FROM normalized n
    JOIN pharmacy.locations l
      ON l.company_id = v_company_id
     AND l.warehouse_id = v_warehouse_id
     AND COALESCE(l.is_active, true) = true
     AND n.barcode IS NOT NULL
     AND UPPER(BTRIM(COALESCE(l.barcode, ''))) = UPPER(n.barcode)
    LIMIT 1
  ) THEN
    RAISE EXCEPTION 'Ya existe una ubicación activa con el mismo código/prefijo en esta bodega';
  END IF;

  WITH normalized AS (
    SELECT
      ord,
      NULLIF(BTRIM(COALESCE(item->>'name', '')), '') AS name,
      NULLIF(BTRIM(COALESCE(item->>'warehouse_id', '')), '')::uuid AS warehouse_id,
      NULLIF(BTRIM(COALESCE(item->>'parent_location_id', '')), '')::uuid AS parent_location_id,
      UPPER(BTRIM(COALESCE(item->>'location_type', ''))) AS location_type,
      NULLIF(BTRIM(COALESCE(item->>'barcode', item->>'code', item->>'prefix', '')), '') AS barcode
    FROM jsonb_array_elements(p_items) WITH ORDINALITY AS arr(item, ord)
  ),
  inserted AS (
    INSERT INTO pharmacy.locations (
      company_id,
      warehouse_id,
      name,
      location_type,
      parent_location_id,
      barcode,
      is_active
    )
    SELECT
      v_company_id,
      v_warehouse_id,
      n.name,
      COALESCE(NULLIF(n.location_type, ''), v_location_type),
      COALESCE(n.parent_location_id, v_parent_location_id),
      n.barcode,
      true
    FROM normalized n
    ORDER BY n.ord
    RETURNING *
  )
  SELECT COALESCE(jsonb_agg(to_jsonb(inserted)), '[]'::jsonb), COUNT(*)
    INTO v_locations, v_count
  FROM inserted;

  PERFORM pharmacy.log_audit_event(
    'LOCATION_BULK_CREATED',
    'Ubicaciones creadas masivamente',
    jsonb_build_object(
      'warehouse_id', v_warehouse_id,
      'parent_location_id', v_parent_location_id,
      'location_type', v_location_type,
      'count', v_count,
      'locations', v_locations
    )
  );

  RETURN jsonb_build_object('count', v_count, 'locations', v_locations);
END;
$$;

CREATE OR REPLACE FUNCTION pharmacy.update_location(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
DECLARE
  v_company_id uuid := pharmacy.get_my_company_id();
  v_user_id uuid := auth.uid();
  v_location_id uuid;
  v_warehouse_id uuid;
  v_target pharmacy.locations%ROWTYPE;
  v_new_name text;
  v_new_barcode text;
  v_new_location_type text;
  v_prefix_from text;
  v_prefix_to text;
  v_locations jsonb := '[]'::jsonb;
  v_count integer := 0;
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Usuario sin empresa asociada';
  END IF;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado';
  END IF;

  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RAISE EXCEPTION 'Payload inválido para actualizar ubicación';
  END IF;

  v_location_id := NULLIF(BTRIM(COALESCE(p_payload->>'location_id', p_payload->>'id', '')), '')::uuid;
  v_warehouse_id := NULLIF(BTRIM(COALESCE(p_payload->>'warehouse_id', '')), '')::uuid;
  v_new_name := NULLIF(BTRIM(COALESCE(p_payload->>'name', '')), '');
  v_new_barcode := NULLIF(BTRIM(COALESCE(p_payload->>'barcode', p_payload->>'code', p_payload->>'prefix', '')), '');
  v_new_location_type := UPPER(BTRIM(COALESCE(p_payload->>'location_type', '')));
  v_prefix_from := NULLIF(BTRIM(COALESCE(p_payload->>'prefix_from', '')), '');
  v_prefix_to := NULLIF(BTRIM(COALESCE(p_payload->>'prefix_to', '')), '');

  IF v_prefix_from IS NOT NULL OR v_prefix_to IS NOT NULL THEN
    IF v_prefix_from IS NULL OR v_prefix_to IS NULL THEN
      RAISE EXCEPTION 'prefix_from y prefix_to son obligatorios para renombrar por prefijo';
    END IF;

    IF v_warehouse_id IS NULL THEN
      RAISE EXCEPTION 'warehouse_id es obligatorio para renombrar por prefijo';
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pharmacy.warehouses w
      WHERE w.id = v_warehouse_id
        AND w.company_id = v_company_id
        AND COALESCE(w.is_active, true) = true
    ) THEN
      RAISE EXCEPTION 'La bodega no pertenece a la empresa o no está activa';
    END IF;

    IF EXISTS (
      WITH targets AS (
        SELECT l.id, l.name, l.location_type, l.parent_location_id,
               v_prefix_to || SUBSTRING(l.name FROM CHAR_LENGTH(v_prefix_from) + 1) AS new_name
        FROM pharmacy.locations l
        WHERE l.company_id = v_company_id
          AND l.warehouse_id = v_warehouse_id
          AND COALESCE(l.is_active, true) = true
          AND l.name LIKE v_prefix_from || '%'
      )
      SELECT 1
      FROM targets
      WHERE UPPER(location_type) IN ('SALES', 'STORAGE', 'QUARANTINE')
        AND parent_location_id IS NULL
      LIMIT 1
    ) THEN
      RAISE EXCEPTION 'Las ubicaciones base no se pueden renombrar';
    END IF;

    IF NOT EXISTS (
      WITH targets AS (
        SELECT l.id, l.name,
               v_prefix_to || SUBSTRING(l.name FROM CHAR_LENGTH(v_prefix_from) + 1) AS new_name
        FROM pharmacy.locations l
        WHERE l.company_id = v_company_id
          AND l.warehouse_id = v_warehouse_id
          AND COALESCE(l.is_active, true) = true
          AND l.name LIKE v_prefix_from || '%'
      )
      SELECT 1 FROM targets LIMIT 1
    ) THEN
      RAISE EXCEPTION 'No se encontraron ubicaciones con el prefijo indicado';
    END IF;

    IF EXISTS (
      WITH targets AS (
        SELECT l.id, l.name,
               v_prefix_to || SUBSTRING(l.name FROM CHAR_LENGTH(v_prefix_from) + 1) AS new_name
        FROM pharmacy.locations l
        WHERE l.company_id = v_company_id
          AND l.warehouse_id = v_warehouse_id
          AND COALESCE(l.is_active, true) = true
          AND l.name LIKE v_prefix_from || '%'
      ),
      duplicates AS (
        SELECT new_name
        FROM targets
        GROUP BY new_name
        HAVING COUNT(*) > 1
      )
      SELECT 1 FROM duplicates LIMIT 1
    ) THEN
      RAISE EXCEPTION 'El nuevo prefijo genera nombres duplicados';
    END IF;

    IF EXISTS (
      WITH targets AS (
        SELECT l.id, l.name,
               v_prefix_to || SUBSTRING(l.name FROM CHAR_LENGTH(v_prefix_from) + 1) AS new_name
        FROM pharmacy.locations l
        WHERE l.company_id = v_company_id
          AND l.warehouse_id = v_warehouse_id
          AND COALESCE(l.is_active, true) = true
          AND l.name LIKE v_prefix_from || '%'
      )
      SELECT 1
      FROM targets t
      JOIN pharmacy.locations l
        ON l.company_id = v_company_id
       AND l.warehouse_id = v_warehouse_id
       AND COALESCE(l.is_active, true) = true
       AND l.id <> t.id
       AND UPPER(BTRIM(l.name)) = UPPER(t.new_name)
      LIMIT 1
    ) THEN
      RAISE EXCEPTION 'El nuevo prefijo entra en conflicto con otra ubicación activa';
    END IF;

    WITH targets AS (
      SELECT l.id, l.name,
             v_prefix_to || SUBSTRING(l.name FROM CHAR_LENGTH(v_prefix_from) + 1) AS new_name
      FROM pharmacy.locations l
      WHERE l.company_id = v_company_id
        AND l.warehouse_id = v_warehouse_id
        AND COALESCE(l.is_active, true) = true
        AND l.name LIKE v_prefix_from || '%'
    ),
    updated AS (
      UPDATE pharmacy.locations l
      SET name = t.new_name
      FROM targets t
      WHERE l.id = t.id
      RETURNING l.*
    )
    SELECT COALESCE(jsonb_agg(to_jsonb(updated)), '[]'::jsonb), COUNT(*)
      INTO v_locations, v_count
    FROM updated;

    PERFORM pharmacy.log_audit_event(
      'LOCATION_UPDATED',
      'Ubicaciones renombradas por prefijo',
      jsonb_build_object(
        'warehouse_id', v_warehouse_id,
        'prefix_from', v_prefix_from,
        'prefix_to', v_prefix_to,
        'count', v_count,
        'locations', v_locations
      )
    );

    RETURN jsonb_build_object('count', v_count, 'locations', v_locations);
  END IF;

  IF v_location_id IS NULL THEN
    RAISE EXCEPTION 'location_id es obligatorio';
  END IF;

  SELECT *
    INTO v_target
  FROM pharmacy.locations l
  WHERE l.id = v_location_id
    AND l.company_id = v_company_id
    AND COALESCE(l.is_active, true) = true
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La ubicación no existe o no pertenece a la empresa';
  END IF;

  v_warehouse_id := v_target.warehouse_id;

  IF v_target.parent_location_id IS NULL AND UPPER(v_target.location_type) IN ('SALES', 'STORAGE', 'QUARANTINE') THEN
    IF (v_new_name IS NOT NULL AND UPPER(BTRIM(v_new_name)) <> UPPER(BTRIM(v_target.name)))
       OR (v_new_barcode IS NOT NULL AND UPPER(BTRIM(v_new_barcode)) <> UPPER(BTRIM(COALESCE(v_target.barcode, ''))))
       OR (v_new_location_type IS NOT NULL AND v_new_location_type <> UPPER(v_target.location_type)) THEN
      RAISE EXCEPTION 'Las ubicaciones base no se pueden renombrar ni reconfigurar';
    END IF;
    RETURN jsonb_build_object('location', to_jsonb(v_target));
  END IF;

  IF v_new_name IS NULL AND v_new_barcode IS NULL AND v_new_location_type = '' THEN
    RAISE EXCEPTION 'No se enviaron campos para actualizar';
  END IF;

  IF v_new_name IS NOT NULL AND UPPER(BTRIM(v_new_name)) <> UPPER(BTRIM(v_target.name)) THEN
    IF EXISTS (
      SELECT 1
      FROM pharmacy.locations l
      WHERE l.company_id = v_company_id
        AND l.warehouse_id = v_warehouse_id
        AND COALESCE(l.is_active, true) = true
        AND l.id <> v_target.id
        AND UPPER(BTRIM(l.name)) = UPPER(v_new_name)
    ) THEN
      RAISE EXCEPTION 'Ya existe una ubicación activa con ese nombre en la bodega';
    END IF;
  END IF;

  IF v_new_barcode IS NOT NULL AND UPPER(BTRIM(v_new_barcode)) <> UPPER(BTRIM(COALESCE(v_target.barcode, ''))) THEN
    IF EXISTS (
      SELECT 1
      FROM pharmacy.locations l
      WHERE l.company_id = v_company_id
        AND l.warehouse_id = v_warehouse_id
        AND COALESCE(l.is_active, true) = true
        AND l.id <> v_target.id
        AND UPPER(BTRIM(COALESCE(l.barcode, ''))) = UPPER(v_new_barcode)
    ) THEN
      RAISE EXCEPTION 'Ya existe una ubicación activa con ese código/prefijo en la bodega';
    END IF;
  END IF;

  IF v_new_location_type <> '' AND v_new_location_type NOT IN ('QUARANTINE', 'STORAGE', 'SALES', 'COLD_CHAIN', 'SECURE') THEN
    RAISE EXCEPTION 'location_type inválido';
  END IF;

  UPDATE pharmacy.locations
     SET name = COALESCE(v_new_name, name),
         barcode = COALESCE(v_new_barcode, barcode),
         location_type = CASE WHEN v_new_location_type = '' THEN location_type ELSE v_new_location_type END
   WHERE id = v_target.id
   RETURNING * INTO v_target;

  PERFORM pharmacy.log_audit_event(
    'LOCATION_UPDATED',
    'Ubicación actualizada',
    jsonb_build_object(
      'location_id', v_target.id,
      'warehouse_id', v_target.warehouse_id,
      'name', v_target.name,
      'location_type', v_target.location_type,
      'barcode', v_target.barcode
    )
  );

  RETURN jsonb_build_object('location', to_jsonb(v_target));
END;
$$;

CREATE OR REPLACE FUNCTION pharmacy.deactivate_location(p_location_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
DECLARE
  v_company_id uuid := pharmacy.get_my_company_id();
  v_user_id uuid := auth.uid();
  v_location pharmacy.locations%ROWTYPE;
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Usuario sin empresa asociada';
  END IF;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado';
  END IF;

  IF p_location_id IS NULL THEN
    RAISE EXCEPTION 'location_id es obligatorio';
  END IF;

  SELECT *
    INTO v_location
  FROM pharmacy.locations l
  WHERE l.id = p_location_id
    AND l.company_id = v_company_id
    AND COALESCE(l.is_active, true) = true
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La ubicación no existe o no pertenece a la empresa';
  END IF;

  IF v_location.parent_location_id IS NULL AND UPPER(v_location.location_type) IN ('SALES', 'STORAGE', 'QUARANTINE') THEN
    RAISE EXCEPTION 'Las ubicaciones base no se pueden desactivar';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pharmacy.locations child
    WHERE child.company_id = v_company_id
      AND child.parent_location_id = v_location.id
      AND COALESCE(child.is_active, true) = true
  ) THEN
    RAISE EXCEPTION 'No se puede desactivar una ubicación con sububicaciones activas';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pharmacy.inventory_batches b
    WHERE b.company_id = v_company_id
      AND b.location_id = v_location.id
      AND COALESCE(b.current_quantity, 0) > 0
  ) THEN
    RAISE EXCEPTION 'No se puede desactivar una ubicación con stock activo';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pharmacy.inventory_movements m
    WHERE m.company_id = v_company_id
      AND (
        m.from_location_id = v_location.id
        OR m.to_location_id = v_location.id
        OR m.source_location_id = v_location.id
        OR m.destination_location_id = v_location.id
      )
  ) THEN
    RAISE EXCEPTION 'No se puede desactivar una ubicación con movimientos históricos asociados';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pharmacy.transfer_request_items tri
    WHERE tri.company_id = v_company_id
      AND tri.status NOT IN ('COMPLETED', 'CANCELLED')
      AND (
        tri.source_location_id = v_location.id
        OR tri.destination_location_id = v_location.id
      )
  ) THEN
    RAISE EXCEPTION 'No se puede desactivar una ubicación con transferencias activas';
  END IF;

  UPDATE pharmacy.locations
     SET is_active = false
   WHERE id = v_location.id
   RETURNING * INTO v_location;

  PERFORM pharmacy.log_audit_event(
    'LOCATION_DEACTIVATED',
    'Ubicación desactivada',
    jsonb_build_object(
      'location_id', v_location.id,
      'warehouse_id', v_location.warehouse_id,
      'name', v_location.name,
      'location_type', v_location.location_type
    )
  );

  RETURN jsonb_build_object('location', to_jsonb(v_location));
END;
$$;

REVOKE INSERT, UPDATE, DELETE ON TABLE pharmacy.locations FROM authenticated;

GRANT EXECUTE ON FUNCTION pharmacy.create_location(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION pharmacy.create_locations_bulk(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION pharmacy.update_location(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION pharmacy.deactivate_location(uuid) TO authenticated;
