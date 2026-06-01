-- Dashboard gerencial farmacéutico v2.1.
-- Mejora UX de alertas y deduplicación por producto sin cambiar la base arquitectónica.

CREATE OR REPLACE VIEW pharmacy.view_dashboard_stock_critical AS
WITH ranked AS (
  SELECT
    ia.*,
    CASE
      WHEN ia.severity = 'CRITICAL' THEN 0
      WHEN ia.severity = 'HIGH' THEN 1
      WHEN ia.severity = 'MEDIUM' THEN 2
      ELSE 3
    END AS severity_rank,
    CASE COALESCE(ia.severity, '')
      WHEN 'CRITICAL' THEN 'Crítico'
      WHEN 'HIGH' THEN 'Alto'
      WHEN 'MEDIUM' THEN 'Medio'
      ELSE 'Bajo'
    END AS severity_label,
    CASE ia.alert_type
      WHEN 'SIN_STOCK' THEN 'Sin stock'
      WHEN 'STOCK_CRITICO' THEN 'Stock crítico'
      ELSE 'Alerta de inventario'
    END AS alert_label,
    CASE ia.alert_type
      WHEN 'SIN_STOCK' THEN 'El producto no tiene stock disponible en la sucursal.'
      WHEN 'STOCK_CRITICO' THEN 'El producto está bajo su mínimo operativo.'
      ELSE 'Revisar disponibilidad del producto.'
    END AS alert_description,
    CASE ia.alert_type
      WHEN 'SIN_STOCK' THEN 'Revisar inventario y reabastecer.'
      WHEN 'STOCK_CRITICO' THEN 'Priorizar reposición o traspaso.'
      ELSE 'Revisar disponibilidad y FEFO.'
    END AS action_hint,
    CASE
      WHEN NULLIF(TRIM(COALESCE(ia.location_name, '')), '') IS NOT NULL THEN ia.location_name
      WHEN ia.location_type = 'QUARANTINE' THEN 'Inventario general'
      ELSE 'Ubicación no asignada'
    END AS location_label,
    row_number() OVER (
      PARTITION BY ia.company_id, ia.warehouse_id, ia.product_id, ia.alert_type
      ORDER BY
        CASE
          WHEN ia.severity = 'CRITICAL' THEN 0
          WHEN ia.severity = 'HIGH' THEN 1
          WHEN ia.severity = 'MEDIUM' THEN 2
          ELSE 3
        END,
        ia.current_quantity ASC NULLS LAST,
        ia.product_name
    ) AS rn
  FROM pharmacy.view_inventory_alerts ia
  WHERE ia.company_id = pharmacy.get_my_company_id()
    AND ia.alert_type IN ('SIN_STOCK', 'STOCK_CRITICO')
)
SELECT *
FROM ranked
WHERE rn = 1;

CREATE OR REPLACE VIEW pharmacy.view_dashboard_operational_alerts AS
WITH ranked AS (
  SELECT
    ia.*,
    CASE
      WHEN ia.severity = 'CRITICAL' THEN 0
      WHEN ia.severity = 'HIGH' THEN 1
      WHEN ia.severity = 'MEDIUM' THEN 2
      ELSE 3
    END AS severity_rank,
    CASE COALESCE(ia.severity, '')
      WHEN 'CRITICAL' THEN 'Crítico'
      WHEN 'HIGH' THEN 'Alto'
      WHEN 'MEDIUM' THEN 'Medio'
      ELSE 'Bajo'
    END AS severity_label,
    CASE ia.alert_type
      WHEN 'SIN_STOCK' THEN 'Sin stock'
      WHEN 'STOCK_CRITICO' THEN 'Stock crítico'
      WHEN 'VENCIDO' THEN 'Lote vencido'
      WHEN 'VENCE_30' THEN 'Vence en 30 días'
      WHEN 'CUARENTENA' THEN 'En cuarentena'
      ELSE 'Alerta operativa'
    END AS alert_label,
    CASE ia.alert_type
      WHEN 'SIN_STOCK' THEN 'El producto no tiene stock disponible en la sucursal.'
      WHEN 'STOCK_CRITICO' THEN 'El producto está bajo su mínimo operativo.'
      WHEN 'VENCIDO' THEN 'Existe al menos un lote vencido con stock.'
      WHEN 'VENCE_30' THEN 'Existe al menos un lote próximo a vencer.'
      WHEN 'CUARENTENA' THEN 'El producto tiene stock retenido en cuarentena.'
      ELSE 'Revisar la condición operativa del producto.'
    END AS alert_description,
    CASE ia.alert_type
      WHEN 'SIN_STOCK' THEN 'Revisar inventario y reabastecer.'
      WHEN 'STOCK_CRITICO' THEN 'Priorizar reposición o traspaso.'
      WHEN 'VENCIDO' THEN 'Retirar o bloquear el lote.'
      WHEN 'VENCE_30' THEN 'Revisar FEFO y rotación.'
      WHEN 'CUARENTENA' THEN 'Revisar causa y posible liberación.'
      ELSE 'Revisar producto y ubicación.'
    END AS action_hint,
    CASE
      WHEN NULLIF(TRIM(COALESCE(ia.location_name, '')), '') IS NOT NULL THEN ia.location_name
      WHEN ia.location_type = 'QUARANTINE' THEN 'Inventario general'
      ELSE 'Ubicación no asignada'
    END AS location_label,
    row_number() OVER (
      PARTITION BY ia.company_id, ia.warehouse_id, ia.product_id, ia.alert_type
      ORDER BY
        CASE
          WHEN ia.severity = 'CRITICAL' THEN 0
          WHEN ia.severity = 'HIGH' THEN 1
          WHEN ia.severity = 'MEDIUM' THEN 2
          ELSE 3
        END,
        ia.days_to_expire ASC NULLS LAST,
        ia.current_quantity ASC NULLS LAST,
        ia.product_name
    ) AS rn
  FROM pharmacy.view_inventory_alerts ia
  WHERE ia.company_id = pharmacy.get_my_company_id()
    AND ia.alert_type IN ('SIN_STOCK', 'STOCK_CRITICO', 'VENCIDO', 'VENCE_30', 'CUARENTENA')
)
SELECT *
FROM ranked
WHERE rn = 1;

CREATE OR REPLACE VIEW pharmacy.view_dashboard_expirations AS
SELECT
  ia.*,
  CASE
    WHEN ia.severity = 'CRITICAL' THEN 0
    WHEN ia.severity = 'HIGH' THEN 1
    WHEN ia.severity = 'MEDIUM' THEN 2
    ELSE 3
  END AS severity_rank,
  CASE COALESCE(ia.severity, '')
    WHEN 'CRITICAL' THEN 'Crítico'
    WHEN 'HIGH' THEN 'Alto'
    WHEN 'MEDIUM' THEN 'Medio'
    ELSE 'Bajo'
  END AS severity_label,
  CASE ia.alert_type
    WHEN 'VENCIDO' THEN 'Lote vencido'
    WHEN 'VENCE_30' THEN 'Vence en 30 días'
    ELSE 'Vencimiento'
  END AS alert_label,
  CASE ia.alert_type
    WHEN 'VENCIDO' THEN 'Existe un lote vencido con stock activo.'
    WHEN 'VENCE_30' THEN 'Existe un lote próximo a vencer.'
    ELSE 'Revisar fecha de vencimiento.'
  END AS alert_description,
  CASE ia.alert_type
    WHEN 'VENCIDO' THEN 'Retirar o bloquear el lote.'
    WHEN 'VENCE_30' THEN 'Revisar FEFO y rotación.'
    ELSE 'Revisar lote y ubicación.'
  END AS action_hint,
  CASE
    WHEN NULLIF(TRIM(COALESCE(ia.location_name, '')), '') IS NOT NULL THEN ia.location_name
    WHEN ia.location_type = 'QUARANTINE' THEN 'Inventario general'
    ELSE 'Ubicación no asignada'
  END AS location_label
FROM pharmacy.view_inventory_alerts ia
WHERE ia.company_id = pharmacy.get_my_company_id()
  AND ia.alert_type IN ('VENCIDO', 'VENCE_30');

CREATE OR REPLACE VIEW pharmacy.view_dashboard_quarantine AS
SELECT
  ia.*,
  3 AS severity_rank,
  'Bajo'::text AS severity_label,
  'En cuarentena'::text AS alert_label,
  'Stock retenido fuera de venta.'::text AS alert_description,
  'Revisar causa y posible liberación.'::text AS action_hint,
  COALESCE(NULLIF(TRIM(COALESCE(ia.location_name, '')), ''), 'Inventario general') AS location_label
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
          'alert_label', x.alert_label,
          'alert_description', x.alert_description,
          'severity', x.severity,
          'severity_label', x.severity_label,
          'severity_rank', x.severity_rank,
          'action_hint', x.action_hint,
          'product_id', x.product_id,
          'product_name', x.product_name,
          'batch_number', x.batch_number,
          'location_name', x.location_name,
          'location_label', x.location_label,
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
          'alert_label', x.alert_label,
          'alert_description', x.alert_description,
          'severity', x.severity,
          'severity_label', x.severity_label,
          'severity_rank', x.severity_rank,
          'action_hint', x.action_hint,
          'product_id', x.product_id,
          'product_name', x.product_name,
          'batch_number', x.batch_number,
          'location_name', x.location_name,
          'location_label', x.location_label,
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
          'alert_label', x.alert_label,
          'alert_description', x.alert_description,
          'severity', x.severity,
          'severity_label', x.severity_label,
          'severity_rank', x.severity_rank,
          'action_hint', x.action_hint,
          'product_id', x.product_id,
          'product_name', x.product_name,
          'location_label', x.location_label,
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

GRANT SELECT ON pharmacy.view_dashboard_operational_alerts TO authenticated;
GRANT SELECT ON pharmacy.view_dashboard_stock_critical TO authenticated;
GRANT SELECT ON pharmacy.view_dashboard_expirations TO authenticated;
GRANT SELECT ON pharmacy.view_dashboard_quarantine TO authenticated;
GRANT SELECT ON pharmacy.view_management_dashboard TO authenticated;
