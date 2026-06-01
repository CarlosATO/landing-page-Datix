-- Dashboard gerencial farmacéutico v2.
-- Separa KPIs livianos de listas operativas para mejorar rendimiento y mantenimiento.

CREATE OR REPLACE FUNCTION pharmacy.get_dashboard_kpis(
  p_warehouse_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
  WITH my_company AS (
    SELECT pharmacy.get_my_company_id() AS company_id
  ),
  warehouse AS (
    SELECT
      w.company_id,
      w.id AS warehouse_id,
      w.name AS warehouse_name
    FROM pharmacy.warehouses w
    JOIN my_company mc ON mc.company_id = w.company_id
    WHERE w.id = p_warehouse_id
      AND COALESCE(w.is_active, true) = true
  ),
  sales_scope AS (
    SELECT
      s.company_id,
      ps.warehouse_id,
      s.id AS sale_id,
      s.total_amount,
      s.created_at
    FROM pharmacy.sales s
    JOIN pharmacy.pos_sessions ps
      ON ps.id = s.session_id
     AND ps.company_id = s.company_id
    JOIN my_company mc ON mc.company_id = s.company_id
    WHERE ps.warehouse_id = p_warehouse_id
  ),
  sales_metrics AS (
    SELECT
      company_id,
      warehouse_id,
      COALESCE(SUM(CASE WHEN created_at::date = CURRENT_DATE THEN total_amount ELSE 0 END), 0) AS sales_today_amount,
      COALESCE(SUM(CASE WHEN created_at >= date_trunc('month', NOW()) THEN total_amount ELSE 0 END), 0) AS sales_month_amount,
      COUNT(*) FILTER (WHERE created_at::date = CURRENT_DATE) AS sales_today_count,
      COALESCE(
        ROUND(
          SUM(CASE WHEN created_at::date = CURRENT_DATE THEN total_amount ELSE 0 END)
          / NULLIF(COUNT(*) FILTER (WHERE created_at::date = CURRENT_DATE), 0),
          2
        ),
        0
      ) AS ticket_average_day
    FROM sales_scope
    GROUP BY company_id, warehouse_id
  ),
  product_stock AS (
    SELECT
      b.company_id,
      l.warehouse_id,
      b.product_id,
      SUM(COALESCE(b.current_quantity, 0)) AS stock_total,
      SUM(CASE WHEN UPPER(l.location_type) = 'QUARANTINE' THEN COALESCE(b.current_quantity, 0) ELSE 0 END) AS quarantine_stock,
      MAX(COALESCE(p.min_stock, 0)) AS min_stock
    FROM pharmacy.inventory_batches b
    JOIN pharmacy.locations l ON l.id = b.location_id AND l.company_id = b.company_id
    JOIN pharmacy.products p ON p.id = b.product_id AND p.company_id = b.company_id
    JOIN my_company mc ON mc.company_id = b.company_id
    WHERE l.warehouse_id = p_warehouse_id
    GROUP BY b.company_id, l.warehouse_id, b.product_id
  ),
  inventory_metrics AS (
    SELECT
      company_id,
      warehouse_id,
      COUNT(*) FILTER (WHERE stock_total = 0) AS products_without_stock_count,
      COUNT(*) FILTER (WHERE stock_total > 0 AND min_stock > 0 AND stock_total <= min_stock) AS products_critical_count,
      COUNT(*) FILTER (WHERE quarantine_stock > 0) AS products_in_quarantine_count
    FROM product_stock
    GROUP BY company_id, warehouse_id
  ),
  batch_metrics AS (
    SELECT
      b.company_id,
      l.warehouse_id,
      COUNT(*) FILTER (WHERE b.current_quantity > 0 AND b.expiry_date < CURRENT_DATE) AS expired_batches_count,
      COUNT(*) FILTER (
        WHERE b.current_quantity > 0
          AND b.expiry_date >= CURRENT_DATE
          AND b.expiry_date <= CURRENT_DATE + INTERVAL '30 days'
      ) AS expiring_batches_30d_count
    FROM pharmacy.inventory_batches b
    JOIN pharmacy.locations l ON l.id = b.location_id AND l.company_id = b.company_id
    JOIN my_company mc ON mc.company_id = b.company_id
    WHERE l.warehouse_id = p_warehouse_id
    GROUP BY b.company_id, l.warehouse_id
  ),
  prescription_metrics AS (
    SELECT
      p.company_id,
      COUNT(*) FILTER (WHERE p.status IN ('PENDING', 'PARTIAL')) AS prescriptions_pending_count,
      COUNT(*) FILTER (WHERE p.status IN ('PENDING', 'PARTIAL') AND p.valid_until >= NOW()) AS prescriptions_active_count
    FROM pharmacy.prescriptions p
    JOIN my_company mc ON mc.company_id = p.company_id
    GROUP BY p.company_id
  ),
  controlled_sales AS (
    SELECT
      s.company_id,
      ps.warehouse_id,
      COUNT(DISTINCT s.id) AS controlled_sales_count
    FROM pharmacy.sales s
    JOIN pharmacy.pos_sessions ps
      ON ps.id = s.session_id
     AND ps.company_id = s.company_id
    JOIN pharmacy.sale_items si
      ON si.sale_id = s.id
     AND si.company_id = s.company_id
    JOIN pharmacy.products p
      ON p.id = si.product_id
     AND p.company_id = s.company_id
    JOIN my_company mc ON mc.company_id = s.company_id
    WHERE ps.warehouse_id = p_warehouse_id
      AND COALESCE(p.is_controlled, false) = true
    GROUP BY s.company_id, ps.warehouse_id
  )
  SELECT
    jsonb_build_object(
      'company_id', w.company_id,
      'warehouse_id', w.warehouse_id,
      'warehouse_name', w.warehouse_name,
      'sales_today_amount', COALESCE(sm.sales_today_amount, 0),
      'sales_month_amount', COALESCE(sm.sales_month_amount, 0),
      'sales_today_count', COALESCE(sm.sales_today_count, 0),
      'ticket_average_day', COALESCE(sm.ticket_average_day, 0),
      'products_critical_count', COALESCE(im.products_critical_count, 0),
      'products_without_stock_count', COALESCE(im.products_without_stock_count, 0),
      'expired_batches_count', COALESCE(bm.expired_batches_count, 0),
      'expiring_batches_30d_count', COALESCE(bm.expiring_batches_30d_count, 0),
      'products_in_quarantine_count', COALESCE(im.products_in_quarantine_count, 0),
      'prescriptions_pending_count', COALESCE(pm.prescriptions_pending_count, 0),
      'prescriptions_active_count', COALESCE(pm.prescriptions_active_count, 0),
      'controlled_sales_count', COALESCE(cs.controlled_sales_count, 0),
      'generated_at', NOW()
    )
  FROM warehouse w
  LEFT JOIN sales_metrics sm
    ON sm.company_id = w.company_id
   AND sm.warehouse_id = w.warehouse_id
  LEFT JOIN inventory_metrics im
    ON im.company_id = w.company_id
   AND im.warehouse_id = w.warehouse_id
  LEFT JOIN batch_metrics bm
    ON bm.company_id = w.company_id
   AND bm.warehouse_id = w.warehouse_id
  LEFT JOIN prescription_metrics pm
    ON pm.company_id = w.company_id
  LEFT JOIN controlled_sales cs
    ON cs.company_id = w.company_id
   AND cs.warehouse_id = w.warehouse_id;
$$;

CREATE OR REPLACE VIEW pharmacy.view_dashboard_operational_alerts AS
SELECT
  ia.*,
  CASE
    WHEN ia.severity = 'CRITICAL' THEN 0
    WHEN ia.severity = 'HIGH' THEN 1
    WHEN ia.severity = 'MEDIUM' THEN 2
    ELSE 3
  END AS severity_rank
FROM pharmacy.view_inventory_alerts ia
WHERE ia.company_id = pharmacy.get_my_company_id()
  AND ia.alert_type IN ('SIN_STOCK', 'STOCK_CRITICO', 'VENCIDO', 'VENCE_30', 'CUARENTENA');

CREATE OR REPLACE VIEW pharmacy.view_dashboard_stock_critical AS
SELECT
  ia.*,
  CASE
    WHEN ia.severity = 'CRITICAL' THEN 0
    WHEN ia.severity = 'HIGH' THEN 1
    WHEN ia.severity = 'MEDIUM' THEN 2
    ELSE 3
  END AS severity_rank
FROM pharmacy.view_inventory_alerts ia
WHERE ia.company_id = pharmacy.get_my_company_id()
  AND ia.alert_type IN ('SIN_STOCK', 'STOCK_CRITICO');

CREATE OR REPLACE VIEW pharmacy.view_dashboard_expirations AS
SELECT
  ia.*,
  CASE
    WHEN ia.severity = 'CRITICAL' THEN 0
    WHEN ia.severity = 'HIGH' THEN 1
    WHEN ia.severity = 'MEDIUM' THEN 2
    ELSE 3
  END AS severity_rank
FROM pharmacy.view_inventory_alerts ia
WHERE ia.company_id = pharmacy.get_my_company_id()
  AND ia.alert_type IN ('VENCIDO', 'VENCE_30');

CREATE OR REPLACE VIEW pharmacy.view_dashboard_quarantine AS
SELECT
  ia.*,
  3 AS severity_rank
FROM pharmacy.view_inventory_alerts ia
WHERE ia.company_id = pharmacy.get_my_company_id()
  AND ia.alert_type = 'CUARENTENA';

CREATE OR REPLACE VIEW pharmacy.view_management_dashboard AS
WITH active_warehouses AS (
  SELECT
    w.company_id,
    w.id AS warehouse_id,
    w.name AS warehouse_name
  FROM pharmacy.warehouses w
  WHERE w.company_id = pharmacy.get_my_company_id()
    AND COALESCE(w.is_active, true) = true
)
SELECT
  aw.company_id,
  aw.warehouse_id,
  aw.warehouse_name,
  COALESCE((k_json->>'sales_today_amount')::numeric, 0) AS sales_today_amount,
  COALESCE((k_json->>'sales_month_amount')::numeric, 0) AS sales_month_amount,
  COALESCE((k_json->>'sales_today_count')::bigint, 0) AS sales_today_count,
  COALESCE((k_json->>'ticket_average_day')::numeric, 0) AS ticket_average_day,
  COALESCE((k_json->>'products_critical_count')::bigint, 0) AS products_critical_count,
  COALESCE((k_json->>'products_without_stock_count')::bigint, 0) AS products_without_stock_count,
  COALESCE((k_json->>'expired_batches_count')::bigint, 0) AS expired_batches_count,
  COALESCE((k_json->>'expiring_batches_30d_count')::bigint, 0) AS expiring_batches_30d_count,
  COALESCE((k_json->>'products_in_quarantine_count')::bigint, 0) AS products_in_quarantine_count,
  COALESCE((k_json->>'prescriptions_pending_count')::bigint, 0) AS prescriptions_pending_count,
  COALESCE((k_json->>'prescriptions_active_count')::bigint, 0) AS prescriptions_active_count,
  COALESCE((k_json->>'controlled_sales_count')::bigint, 0) AS controlled_sales_count,
  COALESCE(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'alert_type', x.alert_type,
          'severity', x.severity,
          'severity_rank', x.severity_rank,
          'product_id', x.product_id,
          'product_name', x.product_name,
          'batch_number', x.batch_number,
          'location_name', x.location_name,
          'location_type', x.location_type,
          'current_quantity', x.current_quantity,
          'expiry_date', x.expiry_date,
          'days_to_expire', x.days_to_expire
        )
      )
      FROM (
        SELECT *
        FROM pharmacy.view_dashboard_operational_alerts ia
        WHERE ia.company_id = aw.company_id
          AND ia.warehouse_id = aw.warehouse_id
        ORDER BY ia.severity_rank, ia.alert_type, ia.days_to_expire NULLS LAST, ia.product_name
        LIMIT 8
      ) x
    ),
    '[]'::jsonb
  ) AS operational_alerts,
  COALESCE(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'alert_type', x.alert_type,
          'severity', x.severity,
          'severity_rank', x.severity_rank,
          'product_id', x.product_id,
          'product_name', x.product_name,
          'batch_number', x.batch_number,
          'location_name', x.location_name,
          'current_quantity', x.current_quantity,
          'expiry_date', x.expiry_date,
          'days_to_expire', x.days_to_expire
        )
      )
      FROM (
        SELECT *
        FROM pharmacy.view_dashboard_expirations ia
        WHERE ia.company_id = aw.company_id
          AND ia.warehouse_id = aw.warehouse_id
        ORDER BY ia.days_to_expire ASC NULLS LAST, ia.product_name
        LIMIT 10
      ) x
    ),
    '[]'::jsonb
  ) AS expiration_alerts,
  COALESCE(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'alert_type', x.alert_type,
          'severity', x.severity,
          'severity_rank', x.severity_rank,
          'product_id', x.product_id,
          'product_name', x.product_name,
          'current_quantity', x.current_quantity
        )
      )
      FROM (
        SELECT *
        FROM pharmacy.view_dashboard_stock_critical ia
        WHERE ia.company_id = aw.company_id
          AND ia.warehouse_id = aw.warehouse_id
        ORDER BY ia.severity_rank, ia.current_quantity ASC NULLS LAST, ia.product_name
        LIMIT 10
      ) x
    ),
    '[]'::jsonb
  ) AS stock_critical_alerts,
  NOW() AS generated_at
FROM active_warehouses aw
JOIN LATERAL pharmacy.get_dashboard_kpis(aw.warehouse_id) k_json ON true;

GRANT EXECUTE ON FUNCTION pharmacy.get_dashboard_kpis(uuid) TO authenticated;
GRANT SELECT ON pharmacy.view_dashboard_operational_alerts TO authenticated;
GRANT SELECT ON pharmacy.view_dashboard_stock_critical TO authenticated;
GRANT SELECT ON pharmacy.view_dashboard_expirations TO authenticated;
GRANT SELECT ON pharmacy.view_dashboard_quarantine TO authenticated;
GRANT SELECT ON pharmacy.view_management_dashboard TO authenticated;
