-- Harden Permissions for Returns RPC
GRANT USAGE ON SCHEMA pharmacy TO authenticated;
GRANT EXECUTE ON FUNCTION pharmacy.process_sale_return(uuid, text, jsonb) TO authenticated;

-- Ensure RLS is correct for returns tables (already done in main migration but confirming)
ALTER TABLE pharmacy.sales_returns OWNER TO postgres;
ALTER TABLE pharmacy.sales_return_items OWNER TO postgres;
ALTER TABLE pharmacy.internal_credit_notes OWNER TO postgres;
