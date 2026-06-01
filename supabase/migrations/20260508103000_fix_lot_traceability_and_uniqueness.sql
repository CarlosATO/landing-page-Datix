-- Fix Lot Traceability and Batch Uniqueness
-- 1. Update view_batch_audit to include returns and use better location logic
CREATE OR REPLACE VIEW "pharmacy"."view_batch_audit" AS
SELECT 
    im.id,
    im.created_at,
    p.name as product_name,
    p.dci as product_dci,
    im.batch_number,
    im.movement_type,
    im.quantity,
    im.balance_after,
    im.reference_folio,
    cu.full_name as operator_name,
    l.name as location_name,
    w.name as warehouse_name,
    im.company_id,
    im.product_id,
    im.batch_id
FROM pharmacy.inventory_movements im
JOIN pharmacy.products p ON p.id = im.product_id
-- We use LEFT JOIN and COALESCE to capture movements that only have to_location (like returns)
LEFT JOIN pharmacy.locations l ON l.id = COALESCE(im.from_location_id, im.to_location_id, im.destination_location_id, im.source_location_id)
LEFT JOIN pharmacy.warehouses w ON w.id = l.warehouse_id
LEFT JOIN public.company_users cu ON cu.user_id = im.created_by AND cu.company_id = im.company_id;

-- 2. Ensure batch uniqueness is composite and doesn't block legitimate duplicates
-- First, drop any existing overly restrictive unique constraints if they exist
DO $$ 
BEGIN
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'inventory_batches_batch_number_key') THEN
        ALTER TABLE pharmacy.inventory_batches DROP CONSTRAINT inventory_batches_batch_number_key;
    END IF;
END $$;

-- Create a robust composite unique constraint for lots
-- This allows the same batch number for different products or in different locations/companies
-- Using location_id instead of warehouse_id as it's the column available in the table
ALTER TABLE pharmacy.inventory_batches 
ADD CONSTRAINT "inventory_batches_composite_key" 
UNIQUE ("company_id", "product_id", "location_id", "batch_number", "expiry_date");

-- 3. Audit check: Ensure RETURN movements are correctly categorized
-- (No changes needed to RPC if it already uses 'RETURN', but ensuring view captures it)

-- 4. Permissions
GRANT SELECT ON "pharmacy"."view_batch_audit" TO authenticated;
