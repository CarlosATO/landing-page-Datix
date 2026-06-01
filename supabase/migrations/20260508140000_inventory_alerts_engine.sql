-- Inventory alerts engine
-- Generates preventive alerts from real stock, locations and expiries.

CREATE OR REPLACE VIEW pharmacy.view_inventory_alerts AS
WITH warehouse_products AS (
  SELECT
    w.company_id,
    w.id AS warehouse_id,
    p.id AS product_id,
    p.name AS product_name,
    p.min_stock,
    COALESCE(p.is_controlled, false) AS is_controlled
  FROM pharmacy.warehouses w
  JOIN pharmacy.products p ON p.company_id = w.company_id
  WHERE COALESCE(w.is_active, true) = true
),
stock_by_product AS (
  SELECT
    b.company_id,
    l.warehouse_id,
    b.product_id,
    SUM(COALESCE(b.current_quantity, 0)) AS stock_total,
    SUM(CASE WHEN l.location_type = 'SALES' THEN COALESCE(b.current_quantity, 0) ELSE 0 END) AS stock_sales,
    SUM(CASE WHEN l.location_type = 'STORAGE' THEN COALESCE(b.current_quantity, 0) ELSE 0 END) AS stock_storage,
    SUM(CASE WHEN l.location_type = 'QUARANTINE' THEN COALESCE(b.current_quantity, 0) ELSE 0 END) AS stock_quarantine
  FROM pharmacy.inventory_batches b
  JOIN pharmacy.locations l ON l.id = b.location_id
  GROUP BY b.company_id, l.warehouse_id, b.product_id
),
product_totals AS (
  SELECT
    wp.company_id,
    wp.warehouse_id,
    wp.product_id,
    wp.product_name,
    wp.min_stock,
    wp.is_controlled,
    COALESCE(sb.stock_total, 0) AS stock_total,
    COALESCE(sb.stock_sales, 0) AS stock_sales,
    COALESCE(sb.stock_storage, 0) AS stock_storage,
    COALESCE(sb.stock_quarantine, 0) AS stock_quarantine
  FROM warehouse_products wp
  LEFT JOIN stock_by_product sb
    ON sb.company_id = wp.company_id
   AND sb.warehouse_id = wp.warehouse_id
   AND sb.product_id = wp.product_id
),
batch_rows AS (
  SELECT
    b.company_id,
    l.warehouse_id,
    b.product_id,
    p.name AS product_name,
    b.batch_number,
    l.name AS location_name,
    l.location_type,
    COALESCE(b.current_quantity, 0) AS current_quantity,
    b.expiry_date,
    CASE
      WHEN b.expiry_date IS NULL THEN NULL
      ELSE (b.expiry_date - CURRENT_DATE)
    END AS days_to_expire,
    COALESCE(p.is_controlled, false) AS is_controlled,
    COALESCE(p.min_stock, 0) AS min_stock
  FROM pharmacy.inventory_batches b
  JOIN pharmacy.locations l ON l.id = b.location_id
  JOIN pharmacy.products p ON p.id = b.product_id
),
alerts AS (
  SELECT
    pt.company_id,
    pt.warehouse_id,
    pt.product_id,
    pt.product_name,
    NULL::text AS batch_number,
    NULL::text AS location_name,
    NULL::text AS location_type,
    pt.stock_total AS current_quantity,
    NULL::date AS expiry_date,
    'SIN_STOCK'::text AS alert_type,
    'CRITICAL'::text AS severity,
    NULL::integer AS days_to_expire
  FROM product_totals pt
  WHERE pt.stock_total = 0

  UNION ALL

  SELECT
    pt.company_id,
    pt.warehouse_id,
    pt.product_id,
    pt.product_name,
    NULL::text AS batch_number,
    NULL::text AS location_name,
    NULL::text AS location_type,
    pt.stock_total AS current_quantity,
    NULL::date AS expiry_date,
    'STOCK_CRITICO'::text AS alert_type,
    'HIGH'::text AS severity,
    NULL::integer AS days_to_expire
  FROM product_totals pt
  WHERE pt.min_stock IS NOT NULL
    AND pt.min_stock > 0
    AND pt.stock_total > 0
    AND pt.stock_total <= pt.min_stock

  UNION ALL

  SELECT
    pt.company_id,
    pt.warehouse_id,
    pt.product_id,
    pt.product_name,
    NULL::text AS batch_number,
    NULL::text AS location_name,
    NULL::text AS location_type,
    pt.stock_total AS current_quantity,
    NULL::date AS expiry_date,
    'CONTROLADO_BAJO_STOCK'::text AS alert_type,
    'CRITICAL'::text AS severity,
    NULL::integer AS days_to_expire
  FROM product_totals pt
  WHERE pt.is_controlled = true
    AND pt.min_stock IS NOT NULL
    AND pt.min_stock > 0
    AND pt.stock_total <= pt.min_stock

  UNION ALL

  SELECT
    br.company_id,
    br.warehouse_id,
    br.product_id,
    br.product_name,
    br.batch_number,
    br.location_name,
    br.location_type,
    br.current_quantity,
    br.expiry_date,
    'VENCIDO'::text AS alert_type,
    'CRITICAL'::text AS severity,
    br.days_to_expire::integer AS days_to_expire
  FROM batch_rows br
  WHERE br.expiry_date IS NOT NULL
    AND br.current_quantity > 0
    AND br.expiry_date < CURRENT_DATE

  UNION ALL

  SELECT
    br.company_id,
    br.warehouse_id,
    br.product_id,
    br.product_name,
    br.batch_number,
    br.location_name,
    br.location_type,
    br.current_quantity,
    br.expiry_date,
    'VENCE_30'::text AS alert_type,
    'HIGH'::text AS severity,
    br.days_to_expire::integer AS days_to_expire
  FROM batch_rows br
  WHERE br.expiry_date IS NOT NULL
    AND br.current_quantity > 0
    AND br.expiry_date >= CURRENT_DATE
    AND br.expiry_date <= CURRENT_DATE + INTERVAL '30 days'

  UNION ALL

  SELECT
    br.company_id,
    br.warehouse_id,
    br.product_id,
    br.product_name,
    br.batch_number,
    br.location_name,
    br.location_type,
    br.current_quantity,
    br.expiry_date,
    'VENCE_60'::text AS alert_type,
    'MEDIUM'::text AS severity,
    br.days_to_expire::integer AS days_to_expire
  FROM batch_rows br
  WHERE br.expiry_date IS NOT NULL
    AND br.current_quantity > 0
    AND br.expiry_date > CURRENT_DATE + INTERVAL '30 days'
    AND br.expiry_date <= CURRENT_DATE + INTERVAL '60 days'

  UNION ALL

  SELECT
    br.company_id,
    br.warehouse_id,
    br.product_id,
    br.product_name,
    br.batch_number,
    br.location_name,
    br.location_type,
    br.current_quantity,
    br.expiry_date,
    'CUARENTENA'::text AS alert_type,
    'LOW'::text AS severity,
    br.days_to_expire::integer AS days_to_expire
  FROM batch_rows br
  WHERE br.location_type = 'QUARANTINE'
    AND br.current_quantity > 0
)
SELECT
  company_id,
  warehouse_id,
  product_id,
  product_name,
  batch_number,
  location_name,
  location_type,
  current_quantity,
  expiry_date,
  alert_type,
  severity,
  days_to_expire
FROM alerts;

GRANT SELECT ON pharmacy.view_inventory_alerts TO authenticated;
