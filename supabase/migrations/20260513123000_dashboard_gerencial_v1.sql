-- Dashboard gerencial farmacéutico v1.
-- Lee métricas operativas desde views/RPC sin tocar reglas del POS.

CREATE OR REPLACE VIEW pharmacy.view_management_dashboard AS
WITH active_warehouses AS (
  SELECT
    w.company_id,
    w.id AS warehouse_id,
    w.name AS warehouse_name
  FROM pharmacy.warehouses w
  WHERE w.company_id = pharmacy.get_my_company_id()
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
  WHERE s.company_id = pharmacy.get_my_company_id()
),
sales_metrics AS (
  SELECT
    company_id,
    warehouse_id,
    COALESCE(SUM(CASE WHEN created_at::date = CURRENT_DATE THEN total_amount ELSE 0 END), 0) AS sales_today_amount,
    COALESCE(SUM(CASE WHEN created_at >= date_trunc('month', NOW()) THEN total_amount ELSE 0 END), 0) AS sales_month_amount,
    COALESCE(COUNT(*) FILTER (WHERE created_at::date = CURRENT_DATE), 0) AS sales_today_count,
    ROUND(
      COALESCE(SUM(CASE WHEN created_at::date = CURRENT_DATE THEN total_amount ELSE 0 END), 0)
      / NULLIF(COUNT(*) FILTER (WHERE created_at::date = CURRENT_DATE), 0),
      2
    ) AS ticket_average_day
  FROM sales_scope
  GROUP BY company_id, warehouse_id
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
  WHERE s.company_id = pharmacy.get_my_company_id()
    AND COALESCE(p.is_controlled, false) = true
  GROUP BY s.company_id, ps.warehouse_id
),
inventory_metrics AS (
  SELECT
    company_id,
    warehouse_id,
    COUNT(DISTINCT product_id) FILTER (WHERE alert_type = 'STOCK_CRITICO') AS products_critical_count,
    COUNT(DISTINCT product_id) FILTER (WHERE alert_type = 'SIN_STOCK') AS products_without_stock_count,
    COUNT(*) FILTER (WHERE alert_type = 'VENCIDO') AS expired_batches_count,
    COUNT(*) FILTER (WHERE alert_type = 'VENCE_30') AS expiring_batches_30d_count,
    COUNT(DISTINCT product_id) FILTER (WHERE alert_type = 'CUARENTENA') AS products_in_quarantine_count
  FROM pharmacy.view_inventory_alerts
  WHERE company_id = pharmacy.get_my_company_id()
  GROUP BY company_id, warehouse_id
),
prescription_metrics AS (
  SELECT
    company_id,
    COUNT(*) FILTER (WHERE status IN ('PENDING', 'PARTIAL')) AS prescriptions_pending_count,
    COUNT(*) FILTER (WHERE status IN ('PENDING', 'PARTIAL') AND valid_until >= NOW()) AS prescriptions_active_count
  FROM pharmacy.prescriptions
  WHERE company_id = pharmacy.get_my_company_id()
  GROUP BY company_id
)
SELECT
  aw.company_id,
  aw.warehouse_id,
  aw.warehouse_name,
  COALESCE(sm.sales_today_amount, 0) AS sales_today_amount,
  COALESCE(sm.sales_month_amount, 0) AS sales_month_amount,
  COALESCE(sm.sales_today_count, 0) AS sales_today_count,
  COALESCE(sm.ticket_average_day, 0) AS ticket_average_day,
  COALESCE(im.products_critical_count, 0) AS products_critical_count,
  COALESCE(im.products_without_stock_count, 0) AS products_without_stock_count,
  COALESCE(im.expired_batches_count, 0) AS expired_batches_count,
  COALESCE(im.expiring_batches_30d_count, 0) AS expiring_batches_30d_count,
  COALESCE(im.products_in_quarantine_count, 0) AS products_in_quarantine_count,
  COALESCE(pm.prescriptions_pending_count, 0) AS prescriptions_pending_count,
  COALESCE(pm.prescriptions_active_count, 0) AS prescriptions_active_count,
  COALESCE(cs.controlled_sales_count, 0) AS controlled_sales_count,
  COALESCE(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'alert_type', x.alert_type,
          'severity', x.severity,
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
        FROM pharmacy.view_inventory_alerts ia
        WHERE ia.company_id = aw.company_id
          AND ia.warehouse_id = aw.warehouse_id
        ORDER BY
          CASE ia.severity WHEN 'CRITICAL' THEN 0 WHEN 'HIGH' THEN 1 WHEN 'MEDIUM' THEN 2 ELSE 3 END,
          ia.alert_type,
          ia.days_to_expire NULLS LAST,
          ia.product_name
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
        FROM pharmacy.view_inventory_alerts ia
        WHERE ia.company_id = aw.company_id
          AND ia.warehouse_id = aw.warehouse_id
          AND ia.alert_type IN ('VENCIDO', 'VENCE_30')
        ORDER BY
          CASE ia.alert_type WHEN 'VENCIDO' THEN 0 ELSE 1 END,
          ia.days_to_expire ASC NULLS LAST,
          ia.product_name
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
          'product_id', x.product_id,
          'product_name', x.product_name,
          'current_quantity', x.current_quantity
        )
      )
      FROM (
        SELECT *
        FROM pharmacy.view_inventory_alerts ia
        WHERE ia.company_id = aw.company_id
          AND ia.warehouse_id = aw.warehouse_id
          AND ia.alert_type IN ('SIN_STOCK', 'STOCK_CRITICO')
        ORDER BY
          CASE ia.alert_type WHEN 'SIN_STOCK' THEN 0 ELSE 1 END,
          ia.product_name
        LIMIT 10
      ) x
    ),
    '[]'::jsonb
  ) AS stock_critical_alerts,
  NOW() AS generated_at
FROM active_warehouses aw
LEFT JOIN sales_metrics sm
  ON sm.company_id = aw.company_id
 AND sm.warehouse_id = aw.warehouse_id
LEFT JOIN controlled_sales cs
  ON cs.company_id = aw.company_id
 AND cs.warehouse_id = aw.warehouse_id
LEFT JOIN inventory_metrics im
  ON im.company_id = aw.company_id
 AND im.warehouse_id = aw.warehouse_id
LEFT JOIN prescription_metrics pm
  ON pm.company_id = aw.company_id;

GRANT SELECT ON pharmacy.view_management_dashboard TO authenticated;
