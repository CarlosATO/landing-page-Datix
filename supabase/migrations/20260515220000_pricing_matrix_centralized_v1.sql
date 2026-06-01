-- Centralized pricing matrix for gerencia.

CREATE OR REPLACE FUNCTION pharmacy.upsert_corporate_price(
  p_company_id uuid,
  p_product_id uuid,
  p_corporate_price numeric,
  p_active boolean DEFAULT true
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
DECLARE
  v_row pharmacy.products%ROWTYPE;
BEGIN
  IF p_company_id IS NULL OR p_product_id IS NULL THEN
    RAISE EXCEPTION 'Parámetros inválidos para precio corporativo';
  END IF;

  UPDATE pharmacy.products
     SET price_sale = COALESCE(p_corporate_price, 0),
         unit_price = COALESCE(p_corporate_price, 0),
         updated_at = now(),
         updated_by = auth.uid(),
         active = COALESCE(p_active, true)
   WHERE id = p_product_id
     AND company_id = p_company_id
   RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Producto no encontrado o no pertenece a la empresa';
  END IF;

  RETURN jsonb_build_object(
    'id', v_row.id,
    'company_id', v_row.company_id,
    'price_sale', v_row.price_sale,
    'unit_price', v_row.unit_price,
    'active', v_row.active,
    'updated_at', v_row.updated_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION pharmacy.get_pricing_matrix(
  p_search text DEFAULT NULL,
  p_limit integer DEFAULT 250
) RETURNS TABLE(
  product_id uuid,
  product_name text,
  barcode text,
  family text,
  laboratory_name text,
  dci text,
  prescription_type text,
  sale_condition text,
  is_controlled boolean,
  average_cost numeric,
  last_cost numeric,
  corporate_price numeric,
  corporate_margin_percent numeric,
  warehouses jsonb
)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
  WITH my_company AS (
    SELECT company_id
    FROM public.company_users
    WHERE user_id = auth.uid()
    LIMIT 1
  ),
  filtered_products AS (
    SELECT p.*
    FROM pharmacy.products p
    JOIN my_company mc ON mc.company_id = p.company_id
    WHERE p.company_id = mc.company_id
      AND (
        p_search IS NULL
        OR TRIM(p_search) = ''
        OR p.name ILIKE '%' || p_search || '%'
        OR p.barcode ILIKE '%' || p_search || '%'
        OR p.dci ILIKE '%' || p_search || '%'
        OR p.brand ILIKE '%' || p_search || '%'
        OR p.laboratory_name ILIKE '%' || p_search || '%'
        OR p.family ILIKE '%' || p_search || '%'
        OR p.registro_sanitario ILIKE '%' || p_search || '%'
        OR p.isp_registry_number ILIKE '%' || p_search || '%'
      )
    ORDER BY p.name ASC
    LIMIT LEAST(COALESCE(p_limit, 250), 500)
  )
  SELECT
    p.id AS product_id,
    p.name AS product_name,
    p.barcode,
    p.family,
    p.laboratory_name,
    p.dci,
    p.prescription_type,
    p.sale_condition,
    COALESCE(p.is_controlled, false) AS is_controlled,
    COALESCE(p.average_cost, 0) AS average_cost,
    COALESCE(p.last_cost, 0) AS last_cost,
    COALESCE(p.price_sale, p.unit_price, 0) AS corporate_price,
    CASE
      WHEN COALESCE(p.average_cost, 0) > 0 AND COALESCE(p.price_sale, p.unit_price, 0) > 0
      THEN ((COALESCE(p.price_sale, p.unit_price, 0) - COALESCE(p.average_cost, 0)) / NULLIF(COALESCE(p.price_sale, p.unit_price, 0), 0)) * 100
      ELSE NULL
    END AS corporate_margin_percent,
    COALESCE(wp.warehouses, '[]'::jsonb) AS warehouses
  FROM filtered_products p
  LEFT JOIN LATERAL (
    SELECT jsonb_agg(
      jsonb_build_object(
        'warehouse_id', w.id,
        'warehouse_name', w.name,
        'active', COALESCE(pp.active, true),
        'use_local_price', COALESCE(pp.use_local_price, false),
        'override_sale_price', pp.override_sale_price,
        'effective_price', COALESCE(
          CASE
            WHEN COALESCE(pp.active, true) AND COALESCE(pp.use_local_price, false)
              THEN COALESCE(pp.override_sale_price, pp.price_sale)
          END,
          p.price_sale,
          p.unit_price,
          0
        ),
        'pricing_source', CASE
          WHEN COALESCE(pp.active, true) AND COALESCE(pp.use_local_price, false) THEN 'LOCAL'
          ELSE 'CORPORATE'
        END
      )
      ORDER BY w.name
    ) AS warehouses
    FROM pharmacy.warehouses w
    LEFT JOIN pharmacy.product_prices pp
      ON pp.product_id = p.id
     AND pp.company_id = p.company_id
     AND pp.warehouse_id = w.id
    WHERE w.company_id = p.company_id
  ) wp ON true;
$$;
