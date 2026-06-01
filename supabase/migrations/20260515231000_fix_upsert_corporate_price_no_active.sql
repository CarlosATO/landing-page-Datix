-- Fix live corporate price RPC to match current products schema.

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
         updated_by = auth.uid()
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
    'updated_at', v_row.updated_at
  );
END;
$$;

GRANT EXECUTE ON FUNCTION pharmacy.upsert_corporate_price(uuid, uuid, numeric, boolean) TO authenticated;
