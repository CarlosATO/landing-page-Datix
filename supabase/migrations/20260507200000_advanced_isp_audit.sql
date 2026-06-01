-- Advanced ISP Audit Views and Indices
-- Aims to provide fiscalizable audit trails for batches, prescriptions, and controlled medications.

-- 1. Indices for Performance
CREATE INDEX IF NOT EXISTS idx_inventory_movements_batch_number ON pharmacy.inventory_movements(batch_number);
CREATE INDEX IF NOT EXISTS idx_sale_items_prescription_id ON pharmacy.sale_items(prescription_id);
CREATE INDEX IF NOT EXISTS idx_products_is_controlled ON pharmacy.products(is_controlled) WHERE is_controlled = true;
CREATE INDEX IF NOT EXISTS idx_products_sale_condition ON pharmacy.products(sale_condition);

-- 2. View for Batch Audit (Traceability Origen-Destino)
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
    im.product_id
FROM pharmacy.inventory_movements im
JOIN pharmacy.products p ON p.id = im.product_id
JOIN pharmacy.locations l ON l.id = im.from_location_id
JOIN pharmacy.warehouses w ON w.id = l.warehouse_id
LEFT JOIN public.company_users cu ON cu.user_id = im.created_by AND cu.company_id = im.company_id;

-- 3. View for Prescription Audit (Dispensation Trail)
CREATE OR REPLACE VIEW "pharmacy"."view_prescription_audit" AS
SELECT 
    si.id,
    s.created_at as sale_date,
    p.folio_electronico,
    p.prescriber_name,
    p.prescriber_rut,
    pat.full_name as patient_name,
    pat.rut as patient_rut,
    prod.name as product_name,
    prod.dci as product_dci,
    si.quantity,
    si.unit_price,
    s.document_number as sale_folio,
    w.name as warehouse_name,
    s.company_id,
    p.id as prescription_id
FROM pharmacy.sale_items si
JOIN pharmacy.sales s ON s.id = si.sale_id
JOIN pharmacy.prescriptions p ON p.id = si.prescription_id
JOIN pharmacy.patients pat ON pat.id = p.patient_id
JOIN pharmacy.products prod ON prod.id = si.product_id
JOIN pharmacy.pos_sessions sess ON sess.id = s.session_id
JOIN pharmacy.warehouses w ON w.id = sess.warehouse_id;

-- 4. View for Controlled Medication Audit (ISP Specific)
CREATE OR REPLACE VIEW "pharmacy"."view_controlled_audit" AS
SELECT 
    si.id,
    s.created_at,
    prod.name as product_name,
    prod.dci as product_dci,
    prod.sale_condition,
    si.quantity,
    si.unit_price,
    p.folio_electronico as prescription_folio,
    pat.full_name as patient_name,
    pat.rut as patient_rut,
    s.document_number as sale_folio,
    w.name as warehouse_name,
    s.company_id,
    prod.id as product_id
FROM pharmacy.sale_items si
JOIN pharmacy.sales s ON s.id = si.sale_id
JOIN pharmacy.products prod ON prod.id = si.product_id
JOIN pharmacy.pos_sessions sess ON sess.id = s.session_id
JOIN pharmacy.warehouses w ON w.id = sess.warehouse_id
LEFT JOIN pharmacy.prescriptions p ON p.id = si.prescription_id
LEFT JOIN pharmacy.patients pat ON pat.id = p.patient_id
WHERE prod.sale_condition IN ('R', 'RR', 'RCH') OR prod.is_controlled = true;

-- 5. Permissions
GRANT SELECT ON "pharmacy"."view_batch_audit" TO authenticated;
GRANT SELECT ON "pharmacy"."view_prescription_audit" TO authenticated;
GRANT SELECT ON "pharmacy"."view_controlled_audit" TO authenticated;
