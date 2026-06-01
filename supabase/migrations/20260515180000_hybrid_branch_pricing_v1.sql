-- Hybrid branch pricing: corporate base + optional local override.

ALTER TABLE pharmacy.product_prices
  ADD COLUMN IF NOT EXISTS override_sale_price numeric,
  ADD COLUMN IF NOT EXISTS override_margin_percent numeric,
  ADD COLUMN IF NOT EXISTS use_local_price boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS active boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS created_at timestamp with time zone NOT NULL DEFAULT now();

UPDATE pharmacy.product_prices
SET
  override_sale_price = COALESCE(override_sale_price, NULLIF(price_sale, 0)),
  use_local_price = COALESCE(use_local_price, price_sale > 0),
  active = COALESCE(active, true),
  created_at = COALESCE(created_at, updated_at, now())
WHERE override_sale_price IS NULL
   OR use_local_price IS NULL
   OR active IS NULL
   OR created_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_product_prices_company_warehouse_product_unique
  ON pharmacy.product_prices (company_id, warehouse_id, product_id);

CREATE OR REPLACE FUNCTION pharmacy.upsert_branch_price_config(
  p_company_id uuid,
  p_product_id uuid,
  p_warehouse_id uuid,
  p_use_local_price boolean,
  p_override_sale_price numeric DEFAULT NULL,
  p_override_margin_percent numeric DEFAULT NULL,
  p_active boolean DEFAULT true
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
DECLARE
  v_row pharmacy.product_prices%ROWTYPE;
BEGIN
  IF p_company_id IS NULL OR p_product_id IS NULL OR p_warehouse_id IS NULL THEN
    RAISE EXCEPTION 'Parámetros inválidos para la configuración de precios';
  END IF;

  INSERT INTO pharmacy.product_prices (
    company_id,
    product_id,
    warehouse_id,
    price_sale,
    override_sale_price,
    override_margin_percent,
    use_local_price,
    active,
    updated_at,
    created_at
  )
  VALUES (
    p_company_id,
    p_product_id,
    p_warehouse_id,
    COALESCE(p_override_sale_price, 0),
    p_override_sale_price,
    p_override_margin_percent,
    COALESCE(p_use_local_price, false),
    COALESCE(p_active, true),
    now(),
    now()
  )
  ON CONFLICT (company_id, warehouse_id, product_id)
  DO UPDATE SET
    override_sale_price = EXCLUDED.override_sale_price,
    override_margin_percent = EXCLUDED.override_margin_percent,
    use_local_price = EXCLUDED.use_local_price,
    active = EXCLUDED.active,
    price_sale = EXCLUDED.price_sale,
    updated_at = now()
  RETURNING * INTO v_row;

  RETURN jsonb_build_object(
    'id', v_row.id,
    'company_id', v_row.company_id,
    'product_id', v_row.product_id,
    'warehouse_id', v_row.warehouse_id,
    'price_sale', v_row.price_sale,
    'override_sale_price', v_row.override_sale_price,
    'override_margin_percent', v_row.override_margin_percent,
    'use_local_price', v_row.use_local_price,
    'active', v_row.active,
    'created_at', v_row.created_at,
    'updated_at', v_row.updated_at
  );
END;
$$;

DROP FUNCTION IF EXISTS pharmacy.get_pos_products(uuid, text, integer);

CREATE OR REPLACE FUNCTION pharmacy.get_pos_products(
  p_warehouse_id uuid,
  p_search text DEFAULT NULL,
  p_limit integer DEFAULT 100
) RETURNS TABLE(
  product_id uuid,
  barcode text,
  name text,
  brand text,
  dci text,
  laboratory_name text,
  sale_condition text,
  prescription_type text,
  requires_prescription boolean,
  is_controlled boolean,
  price_sale numeric,
  corporate_price_sale numeric,
  local_override_sale_price numeric,
  use_local_price boolean,
  active boolean,
  pricing_source text,
  stock_available numeric,
  stock_quarantine numeric
)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
  with my_company as (
    select company_id
    from public.company_users
    where user_id = auth.uid()
    limit 1
  ),
  stock as (
    select
      b.product_id,
      sum(case when upper(l.location_type) <> 'QUARANTINE' then b.current_quantity else 0 end) as stock_available,
      sum(case when upper(l.location_type) = 'QUARANTINE' then b.current_quantity else 0 end) as stock_quarantine
    from pharmacy.inventory_batches b
    join pharmacy.locations l on l.id = b.location_id
    join my_company mc on mc.company_id = b.company_id
    where l.warehouse_id = p_warehouse_id
      and l.company_id = mc.company_id
      and b.current_quantity > 0
    group by b.product_id
  )
  select
    p.id as product_id,
    p.barcode,
    p.name,
    p.brand,
    p.dci,
    p.laboratory_name,
    p.sale_condition,
    p.prescription_type,
    case
      when p.prescription_type in ('RECETA_SIMPLE', 'RECETA_RETENIDA', 'RECETA_CHEQUE')
        or p.sale_condition in ('R', 'RR', 'RCH')
      then true
      else false
    end as requires_prescription,
    coalesce(p.is_controlled, false) as is_controlled,
    coalesce(
      case
        when coalesce(pp.active, true) and coalesce(pp.use_local_price, false)
          then coalesce(pp.override_sale_price, pp.price_sale)
      end,
      p.price_sale,
      p.unit_price,
      0
    ) as price_sale,
    coalesce(p.price_sale, p.unit_price, 0) as corporate_price_sale,
    pp.override_sale_price as local_override_sale_price,
    coalesce(pp.use_local_price, false) as use_local_price,
    coalesce(pp.active, true) as active,
    case when coalesce(pp.active, true) and coalesce(pp.use_local_price, false) then 'LOCAL' else 'CORPORATE' end as pricing_source,
    coalesce(s.stock_available, 0) as stock_available,
    coalesce(s.stock_quarantine, 0) as stock_quarantine
  from pharmacy.products p
  join my_company mc on mc.company_id = p.company_id
  left join stock s on s.product_id = p.id
  left join pharmacy.product_prices pp
    on pp.product_id = p.id
   and pp.company_id = p.company_id
   and pp.warehouse_id = p_warehouse_id
  where p.company_id = mc.company_id
    and (
      p_search is null
      or trim(p_search) = ''
      or p.name ilike '%' || p_search || '%'
      or p.barcode ilike '%' || p_search || '%'
      or p.dci ilike '%' || p_search || '%'
      or p.brand ilike '%' || p_search || '%'
      or p.laboratory_name ilike '%' || p_search || '%'
      or p.registro_sanitario ilike '%' || p_search || '%'
      or p.isp_registry_number ilike '%' || p_search || '%'
    )
  order by p.name asc
  limit least(coalesce(p_limit, 100), 300);
$$;

GRANT EXECUTE ON FUNCTION pharmacy.get_pos_products(uuid, text, integer) TO authenticated;

DROP VIEW IF EXISTS pharmacy.view_bioequivalent_products CASCADE;

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
  COALESCE(
    CASE
      WHEN COALESCE(pp.active, true) AND COALESCE(pp.use_local_price, false)
        THEN COALESCE(pp.override_sale_price, pp.price_sale)
    END,
    p.price_sale,
    p.unit_price,
    0
  ) AS sale_price,
  l.warehouse_id,
  p.company_id
FROM pharmacy.products p
LEFT JOIN pharmacy.inventory_batches b ON b.product_id = p.id
LEFT JOIN pharmacy.locations l ON l.id = b.location_id AND l.company_id = p.company_id
LEFT JOIN pharmacy.product_prices pp ON pp.product_id = p.id AND pp.warehouse_id = l.warehouse_id
GROUP BY p.id, p.name, p.dci, p.concentration, p.presentation, p.laboratory_name,
          p.sale_condition, p.is_controlled, p.price_sale, p.unit_price,
          l.warehouse_id, p.company_id, pp.price_sale, pp.override_sale_price, pp.use_local_price, pp.active;

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
