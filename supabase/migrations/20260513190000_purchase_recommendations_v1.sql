-- Reposición Inteligente v1.
-- Motor inicial de sugerencias de compra y riesgo de quiebre, sin IA ni predicción avanzada.
--
-- Fórmulas usadas:
-- - stock_actual_sales = suma de current_quantity en ubicaciones SALES con lote no vencido.
-- - ventas_30d = suma de quantity en sale_items de los últimos 30 días en la misma sucursal.
-- - promedio_venta_diaria = ventas_30d / 30.
-- - dias_cobertura = stock_actual_sales / promedio_venta_diaria.
-- - cantidad_sugerida = ceil(max(min_stock, promedio_venta_diaria * 30) - stock_actual_sales), con mínimo 0.
-- - riesgo = CRITICO / BAJO / NORMAL / SOBRE_STOCK según stock y cobertura.
--
-- Exclusiones:
-- - productos con ventas_30d = 0.
-- - productos con stock vencido.
-- - productos con stock en cuarentena.

ALTER TABLE pharmacy.purchase_orders
  ALTER COLUMN supplier_id DROP NOT NULL;

ALTER TABLE pharmacy.purchase_orders
  ADD COLUMN IF NOT EXISTS origin_source text NOT NULL DEFAULT 'MANUAL';

COMMENT ON COLUMN pharmacy.purchase_orders.origin_source IS
  'Origen funcional de la orden. Ej.: MANUAL, REPOSICION_INTELIGENTE.';

DROP FUNCTION IF EXISTS pharmacy.get_last_purchase_unit_cost(uuid, uuid, uuid);
DROP FUNCTION IF EXISTS pharmacy.get_purchase_recommendations(uuid);

CREATE OR REPLACE FUNCTION pharmacy.get_last_purchase_unit_cost(
  p_company_id uuid,
  p_warehouse_id uuid,
  p_product_id uuid
)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
  SELECT COALESCE((
    SELECT poi.unit_cost
    FROM pharmacy.purchase_order_items poi
    JOIN pharmacy.purchase_orders po
      ON po.id = poi.po_id
    WHERE po.company_id = p_company_id
      AND po.warehouse_id = p_warehouse_id
      AND poi.product_id = p_product_id
      AND po.status IN ('RECEIVED', 'PARTIAL')
      AND COALESCE(poi.unit_cost, 0) > 0
    ORDER BY po.issue_date DESC NULLS LAST, po.created_at DESC, poi.created_at DESC
    LIMIT 1
  ), 0);
$$;

GRANT EXECUTE ON FUNCTION pharmacy.get_last_purchase_unit_cost(uuid, uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION pharmacy.get_purchase_recommendations(
  p_warehouse_id uuid DEFAULT NULL
)
RETURNS TABLE (
  company_id uuid,
  warehouse_id uuid,
  product_id uuid,
  product_name text,
  dci text,
  sale_condition text,
  is_controlled boolean,
  purchase_uom text,
  sale_uom text,
  conversion_factor numeric,
  last_purchase_unit_cost numeric,
  last_purchase_at timestamptz,
  min_stock numeric,
  stock_actual_sales numeric,
  sales_30d numeric,
  average_daily_sales numeric,
  coverage_days numeric,
  risk_state text,
  suggested_purchase_qty numeric,
  priority_rank integer,
  last_sale_at timestamptz,
  generated_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
  WITH my_company AS (
    SELECT pharmacy.get_my_company_id() AS company_id
  ),
  warehouse_scope AS (
    SELECT
      w.company_id,
      w.id AS warehouse_id
    FROM pharmacy.warehouses w
    JOIN my_company mc ON mc.company_id = w.company_id
    WHERE w.id = p_warehouse_id
      AND COALESCE(w.is_active, true) = true
  ),
  stock_scope AS (
    SELECT
      b.company_id,
      l.warehouse_id,
      b.product_id,
      SUM(
        CASE
          WHEN UPPER(l.location_type) = 'SALES'
           AND COALESCE(b.current_quantity, 0) > 0
           AND b.expiry_date >= CURRENT_DATE
            THEN COALESCE(b.current_quantity, 0)
          ELSE 0
        END
      ) AS stock_actual_sales,
      SUM(
        CASE
          WHEN UPPER(l.location_type) = 'QUARANTINE'
           AND COALESCE(b.current_quantity, 0) > 0
            THEN COALESCE(b.current_quantity, 0)
          ELSE 0
        END
      ) AS stock_quarantine,
      SUM(
        CASE
          WHEN COALESCE(b.current_quantity, 0) > 0
           AND b.expiry_date < CURRENT_DATE
            THEN COALESCE(b.current_quantity, 0)
          ELSE 0
        END
      ) AS stock_expired,
      MAX(COALESCE(p.min_stock, 0)) AS min_stock
    FROM pharmacy.inventory_batches b
    JOIN pharmacy.locations l
      ON l.id = b.location_id
     AND l.company_id = b.company_id
    JOIN pharmacy.products p
      ON p.id = b.product_id
     AND p.company_id = b.company_id
    JOIN warehouse_scope ws
      ON ws.company_id = b.company_id
     AND ws.warehouse_id = l.warehouse_id
    GROUP BY b.company_id, l.warehouse_id, b.product_id
  ),
  sales_30d AS (
    SELECT
      s.company_id,
      ps.warehouse_id,
      si.product_id,
      SUM(COALESCE(si.quantity, 0)) AS sales_30d,
      MAX(s.created_at) AS last_sale_at
    FROM pharmacy.sale_items si
    JOIN pharmacy.sales s
      ON s.id = si.sale_id
     AND s.company_id = si.company_id
    JOIN pharmacy.pos_sessions ps
      ON ps.id = s.session_id
     AND ps.company_id = s.company_id
    JOIN warehouse_scope ws
      ON ws.company_id = s.company_id
     AND ws.warehouse_id = ps.warehouse_id
    WHERE s.created_at >= NOW() - INTERVAL '30 days'
    GROUP BY s.company_id, ps.warehouse_id, si.product_id
  ),
  product_scope AS (
    SELECT
      COALESCE(st.company_id, sa.company_id) AS company_id,
      COALESCE(st.warehouse_id, sa.warehouse_id) AS warehouse_id,
      COALESCE(st.product_id, sa.product_id) AS product_id,
      COALESCE(st.stock_actual_sales, 0) AS stock_actual_sales,
      COALESCE(st.stock_quarantine, 0) AS stock_quarantine,
      COALESCE(st.stock_expired, 0) AS stock_expired,
      COALESCE(st.min_stock, 0) AS min_stock,
      COALESCE(sa.sales_30d, 0) AS sales_30d,
      sa.last_sale_at,
      ROUND(COALESCE(sa.sales_30d, 0) / 30.0, 2) AS average_daily_sales,
      ROUND(
        CASE
          WHEN COALESCE(sa.sales_30d, 0) > 0
            THEN COALESCE(st.stock_actual_sales, 0) / NULLIF(COALESCE(sa.sales_30d, 0) / 30.0, 0)
          ELSE NULL
        END,
        2
      ) AS coverage_days
    FROM stock_scope st
    FULL OUTER JOIN sales_30d sa
      ON sa.company_id = st.company_id
     AND sa.warehouse_id = st.warehouse_id
     AND sa.product_id = st.product_id
  ),
  eligible_products AS (
    SELECT
      ps.company_id,
      ps.warehouse_id,
      ps.product_id,
      p.name AS product_name,
      p.dci,
      p.sale_condition,
      COALESCE(p.is_controlled, false) AS is_controlled,
      COALESCE(NULLIF(p.purchase_uom, ''), 'CAJA') AS purchase_uom,
      COALESCE(NULLIF(p.sale_uom, ''), 'UNIDAD') AS sale_uom,
      GREATEST(COALESCE(p.conversion_factor, 1), 1) AS conversion_factor,
      pharmacy.get_last_purchase_unit_cost(ps.company_id, ps.warehouse_id, ps.product_id) AS last_purchase_unit_cost,
      ps.min_stock,
      ps.stock_actual_sales,
      ps.sales_30d,
      ps.average_daily_sales,
      ps.coverage_days,
      ps.last_sale_at,
      CASE
        WHEN ps.stock_actual_sales <= ps.min_stock OR ps.coverage_days <= 7 THEN 'CRITICO'
        WHEN ps.coverage_days <= 15 THEN 'BAJO'
        WHEN ps.coverage_days <= 30 THEN 'NORMAL'
        ELSE 'SOBRE_STOCK'
      END AS risk_state,
      CASE
        WHEN ps.stock_actual_sales <= ps.min_stock OR ps.coverage_days <= 30 THEN
          GREATEST(
            0,
            GREATEST(ps.min_stock, ps.average_daily_sales * 30) - ps.stock_actual_sales
          )
        ELSE 0
      END AS suggested_purchase_qty
    FROM product_scope ps
    JOIN pharmacy.products p
      ON p.id = ps.product_id
     AND p.company_id = ps.company_id
    WHERE ps.sales_30d > 0
      AND COALESCE(ps.stock_quarantine, 0) = 0
      AND COALESCE(ps.stock_expired, 0) = 0
  )
  SELECT
    ep.company_id,
    ep.warehouse_id,
    ep.product_id,
    ep.product_name,
    ep.dci,
    ep.sale_condition,
    ep.is_controlled,
    ep.purchase_uom,
    ep.sale_uom,
    ep.conversion_factor,
    ep.last_purchase_unit_cost,
    NULL::timestamptz AS last_purchase_at,
    ep.min_stock,
    ep.stock_actual_sales,
    ep.sales_30d,
    ep.average_daily_sales,
    ep.coverage_days,
    ep.risk_state,
    CASE
      WHEN ep.suggested_purchase_qty <= 0 THEN 0
      ELSE CEIL(ep.suggested_purchase_qty / NULLIF(ep.conversion_factor, 0))
    END AS suggested_purchase_qty,
    CASE ep.risk_state
      WHEN 'CRITICO' THEN 0
      WHEN 'BAJO' THEN 1
      WHEN 'NORMAL' THEN 2
      ELSE 3
    END AS priority_rank,
    ep.last_sale_at,
    NOW() AS generated_at
  FROM eligible_products ep
  ORDER BY
    CASE ep.risk_state
      WHEN 'CRITICO' THEN 0
      WHEN 'BAJO' THEN 1
      WHEN 'NORMAL' THEN 2
      ELSE 3
    END,
    CASE WHEN ep.is_controlled THEN 0 ELSE 1 END,
    ep.sales_30d DESC,
    ep.stock_actual_sales ASC,
    ep.coverage_days ASC NULLS LAST,
    ep.product_name ASC;
$$;

COMMENT ON FUNCTION pharmacy.get_purchase_recommendations(uuid) IS
  'Reposición Inteligente v1. Usa stock sellable en SALES, ventas de 30 días y cobertura estimada. Excluye vencidos, cuarentena y productos sin ventas recientes.';

GRANT EXECUTE ON FUNCTION pharmacy.get_purchase_recommendations(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION pharmacy.create_reposition_purchase_draft(
  p_warehouse_id uuid,
  p_items jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
DECLARE
  v_company_id uuid := pharmacy.get_my_company_id();
  v_user_id uuid := auth.uid();
  v_po_id uuid;
  v_po_number integer;
  v_items_count integer := 0;
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'No se pudo resolver la compañía.';
  END IF;

  IF p_warehouse_id IS NULL THEN
    RAISE EXCEPTION 'Debe seleccionar una sucursal.';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Debe seleccionar al menos un producto.';
  END IF;

  WITH requested_items AS (
    SELECT
      (item->>'product_id')::uuid AS product_id,
      SUM(GREATEST(0, COALESCE(NULLIF(item->>'quantity', ''), '0')::numeric)) AS quantity
    FROM jsonb_array_elements(p_items) AS item
    WHERE item ? 'product_id'
      AND item ? 'quantity'
    GROUP BY (item->>'product_id')::uuid
  ),
  valid_items AS (
    SELECT
      ri.product_id,
      CASE WHEN ri.quantity > 0 THEN CEIL(ri.quantity) ELSE 0 END AS quantity,
      GREATEST(COALESCE(p.conversion_factor, 1), 1) AS conversion_factor,
      COALESCE(NULLIF(p.purchase_uom, ''), 'CAJA') AS purchase_uom,
      COALESCE(NULLIF(p.sale_uom, ''), 'UNIDAD') AS sale_uom,
      pharmacy.get_last_purchase_unit_cost(v_company_id, p_warehouse_id, ri.product_id) AS last_purchase_unit_cost
    FROM requested_items ri
    JOIN pharmacy.products p
      ON p.id = ri.product_id
     AND p.company_id = v_company_id
    WHERE ri.quantity > 0
  )
  SELECT COUNT(*) INTO v_items_count
  FROM valid_items;

  IF v_items_count = 0 THEN
    RAISE EXCEPTION 'No hay productos válidos para generar la pre-orden.';
  END IF;

  INSERT INTO pharmacy.purchase_orders (
    company_id,
    supplier_id,
    status,
    warehouse_id,
    created_by,
    origin_source,
    issue_date,
    observation_notes
  )
  VALUES (
    v_company_id,
    NULL,
    'DRAFT',
    p_warehouse_id,
    v_user_id,
    'REPOSICION_INTELIGENTE',
    NOW(),
    'Pre-orden generada desde Reposición Inteligente v1.1'
  )
  RETURNING id, po_number INTO v_po_id, v_po_number;

  INSERT INTO pharmacy.purchase_order_items (
    po_id,
    product_id,
    quantity,
    unit_cost,
    total_cost,
    conversion_factor
  )
  WITH requested_items AS (
    SELECT
      (item->>'product_id')::uuid AS product_id,
      SUM(GREATEST(0, COALESCE(NULLIF(item->>'quantity', ''), '0')::numeric)) AS quantity
    FROM jsonb_array_elements(p_items) AS item
    WHERE item ? 'product_id'
      AND item ? 'quantity'
    GROUP BY (item->>'product_id')::uuid
  ),
  valid_items AS (
    SELECT
      ri.product_id,
      ri.quantity,
      COALESCE(p.conversion_factor, 1) AS conversion_factor,
      pharmacy.get_last_purchase_unit_cost(v_company_id, p_warehouse_id, ri.product_id) AS last_purchase_unit_cost
    FROM requested_items ri
    JOIN pharmacy.products p
      ON p.id = ri.product_id
     AND p.company_id = v_company_id
    WHERE ri.quantity > 0
  )
  SELECT
    v_po_id,
    vi.product_id,
    vi.quantity,
    COALESCE(NULLIF(vi.last_purchase_unit_cost, 0), 0),
    vi.quantity * COALESCE(NULLIF(vi.last_purchase_unit_cost, 0), 0),
    vi.conversion_factor
  FROM valid_items vi;

  GET DIAGNOSTICS v_items_count = ROW_COUNT;

  RETURN jsonb_build_object(
    'po_id', v_po_id,
    'po_number', v_po_number,
    'status', 'DRAFT',
    'origin_source', 'REPOSICION_INTELIGENTE',
    'items_count', v_items_count,
    'generated_at', NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION pharmacy.create_reposition_purchase_draft(uuid, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION pharmacy.update_purchase_order_draft(
  p_purchase_order_id uuid,
  p_supplier_id uuid DEFAULT NULL,
  p_expected_delivery_date date DEFAULT NULL,
  p_observation_notes text DEFAULT NULL,
  p_payment_terms_days integer DEFAULT NULL,
  p_items jsonb DEFAULT '[]'::jsonb,
  p_emit boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
DECLARE
  v_company_id uuid := pharmacy.get_my_company_id();
  v_user_id uuid := auth.uid();
  v_current_status text;
  v_warehouse_id uuid;
  v_po_number integer;
  v_net numeric := 0;
  v_tax numeric := 0;
  v_total numeric := 0;
  v_items_count integer := 0;
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'No se pudo resolver la compañía.';
  END IF;

  IF p_purchase_order_id IS NULL THEN
    RAISE EXCEPTION 'Debe indicar la orden a editar.';
  END IF;

  SELECT po.status, po.po_number, po.warehouse_id
    INTO v_current_status, v_po_number, v_warehouse_id
  FROM pharmacy.purchase_orders po
  WHERE po.id = p_purchase_order_id
    AND po.company_id = v_company_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La orden no existe en la compañía actual.';
  END IF;

  IF v_current_status <> 'DRAFT' THEN
    RAISE EXCEPTION 'Solo se pueden editar órdenes en estado DRAFT.';
  END IF;

  IF p_emit AND p_supplier_id IS NULL THEN
    RAISE EXCEPTION 'Debe seleccionar un proveedor para emitir la orden.';
  END IF;

  WITH requested_items AS (
    SELECT
      (item->>'product_id')::uuid AS product_id,
      GREATEST(0, COALESCE(NULLIF(item->>'quantity', ''), '0')::numeric) AS quantity,
      GREATEST(0, COALESCE(NULLIF(item->>'unit_cost', ''), '0')::numeric) AS unit_cost,
      GREATEST(COALESCE(NULLIF(item->>'conversion_factor', ''), '1')::numeric, 1) AS conversion_factor
    FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb)) AS item
    WHERE item ? 'product_id'
      AND item ? 'quantity'
  ),
  normalized_items AS (
    SELECT
      ri.product_id,
      SUM(ri.quantity) AS quantity,
      COALESCE(MAX(NULLIF(ri.unit_cost, 0)), pharmacy.get_last_purchase_unit_cost(v_company_id, v_warehouse_id, ri.product_id)) AS unit_cost,
      MAX(ri.conversion_factor) AS conversion_factor
    FROM requested_items ri
    JOIN pharmacy.products p
      ON p.id = ri.product_id
     AND p.company_id = v_company_id
    GROUP BY ri.product_id
    HAVING SUM(ri.quantity) > 0
  )
  SELECT COUNT(*), COALESCE(SUM(quantity * unit_cost), 0)
    INTO v_items_count, v_net
  FROM normalized_items;

  IF v_items_count = 0 THEN
    RAISE EXCEPTION 'La orden debe contener al menos una línea válida.';
  END IF;

  v_tax := ROUND(v_net * 0.19, 2);
  v_total := v_net + v_tax;

  UPDATE pharmacy.purchase_orders
     SET supplier_id = p_supplier_id,
         expected_delivery_date = p_expected_delivery_date,
         observation_notes = p_observation_notes,
         payment_terms_days = p_payment_terms_days,
         total_neto = v_net,
         total_net = v_net,
         tax_amount = v_tax,
         total_amount = v_total,
         status = CASE WHEN p_emit THEN 'PENDING' ELSE 'DRAFT' END,
         updated_by = v_user_id
   WHERE id = p_purchase_order_id
     AND company_id = v_company_id;

  DELETE FROM pharmacy.purchase_order_items
   WHERE po_id = p_purchase_order_id;

  WITH requested_items AS (
    SELECT
      (item->>'product_id')::uuid AS product_id,
      GREATEST(0, COALESCE(NULLIF(item->>'quantity', ''), '0')::numeric) AS quantity,
      GREATEST(0, COALESCE(NULLIF(item->>'unit_cost', ''), '0')::numeric) AS unit_cost,
      GREATEST(COALESCE(NULLIF(item->>'conversion_factor', ''), '1')::numeric, 1) AS conversion_factor
    FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb)) AS item
    WHERE item ? 'product_id'
      AND item ? 'quantity'
  ),
  normalized_items AS (
    SELECT
      ri.product_id,
      SUM(ri.quantity) AS quantity,
      COALESCE(MAX(NULLIF(ri.unit_cost, 0)), pharmacy.get_last_purchase_unit_cost(v_company_id, v_warehouse_id, ri.product_id)) AS unit_cost,
      MAX(ri.conversion_factor) AS conversion_factor
    FROM requested_items ri
    JOIN pharmacy.products p
      ON p.id = ri.product_id
     AND p.company_id = v_company_id
    GROUP BY ri.product_id
    HAVING SUM(ri.quantity) > 0
  )
  INSERT INTO pharmacy.purchase_order_items (
    po_id,
    product_id,
    quantity,
    unit_cost,
    total_cost,
    conversion_factor,
    updated_by
  )
  SELECT
    p_purchase_order_id,
    ni.product_id,
    ni.quantity,
    ni.unit_cost,
    ni.quantity * ni.unit_cost,
    ni.conversion_factor,
    v_user_id
  FROM normalized_items ni;

  RETURN jsonb_build_object(
    'po_id', p_purchase_order_id,
    'po_number', v_po_number,
    'status', CASE WHEN p_emit THEN 'PENDING' ELSE 'DRAFT' END,
    'supplier_id', p_supplier_id,
    'total_net', v_net,
    'tax_amount', v_tax,
    'total_amount', v_total,
    'items_count', v_items_count,
    'generated_at', NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION pharmacy.update_purchase_order_draft(uuid, uuid, date, text, integer, jsonb, boolean) TO authenticated;
