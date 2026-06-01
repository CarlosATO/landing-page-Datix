-- Bioequivalent product suggestion engine for POS.
-- Finds pharmaceutical alternatives by same DCI, concentration and form.

CREATE OR REPLACE VIEW pharmacy.view_bioequivalent_products AS
SELECT
  p.id AS product_id,
  p.name AS product_name,
  p.dci,
  p.concentration AS concentracion,
  p.presentation AS forma_farmaceutica,
  p.laboratory_name AS laboratory,
  p.sale_condition,
  p.is_controlled,
  COALESCE(SUM(
    CASE
      WHEN UPPER(l.location_type) = 'SALES' THEN b.current_quantity
      ELSE 0
    END
  ), 0) AS stock_available,
  COALESCE(MIN(
    CASE
      WHEN UPPER(l.location_type) = 'SALES' AND b.current_quantity > 0 THEN b.expiry_date
      ELSE NULL
    END
  ), NULL) AS next_expiry,
  COALESCE(pp.price_sale, p.price_sale, p.unit_price, 0) AS sale_price,
  l.warehouse_id,
  p.company_id
FROM pharmacy.products p
LEFT JOIN pharmacy.inventory_batches b ON b.product_id = p.id
LEFT JOIN pharmacy.locations l ON l.id = b.location_id AND l.company_id = p.company_id
LEFT JOIN pharmacy.product_prices pp ON pp.product_id = p.id AND pp.warehouse_id = l.warehouse_id
GROUP BY p.id, p.name, p.dci, p.concentration, p.presentation, p.laboratory_name,
         p.sale_condition, p.is_controlled, p.price_sale, p.unit_price,
         l.warehouse_id, p.company_id, pp.price_sale;

GRANT SELECT ON pharmacy.view_bioequivalent_products TO authenticated;

CREATE OR REPLACE FUNCTION pharmacy.get_bioequivalent_suggestions(
  p_product_id uuid,
  p_warehouse_id uuid
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
  WITH ref AS (
    SELECT dci, concentration, presentation, sale_condition, is_controlled
    FROM pharmacy.products
    WHERE id = p_product_id
  )
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'product_id', v.product_id,
      'product_name', v.product_name,
      'dci', v.dci,
      'laboratory', v.laboratory,
      'stock_available', v.stock_available,
      'next_expiry', v.next_expiry,
      'sale_price', v.sale_price,
      'sale_condition', v.sale_condition,
      'is_controlled', v.is_controlled
    )
    ORDER BY
      v.stock_available DESC,
      v.next_expiry ASC NULLS LAST,
      v.sale_price ASC
  ), '[]'::jsonb)
  FROM pharmacy.view_bioequivalent_products v, ref
  WHERE v.company_id = pharmacy.get_my_company_id()
    AND v.warehouse_id = p_warehouse_id
    AND v.product_id <> p_product_id
    AND v.dci = ref.dci
    AND UPPER(COALESCE(v.concentracion, '')) = UPPER(COALESCE(ref.concentration, ''))
    AND UPPER(COALESCE(v.forma_farmaceutica, '')) = UPPER(COALESCE(ref.presentation, ''))
    AND v.sale_condition = ref.sale_condition
    AND v.is_controlled = ref.is_controlled
    AND v.stock_available > 0;
$$;

GRANT EXECUTE ON FUNCTION pharmacy.get_bioequivalent_suggestions(uuid, uuid) TO authenticated;
