-- Performance indexes for critical pharmacy core tables.
-- Low-risk migration: indexes only, no functional logic changes.

-- 1. sales
CREATE INDEX IF NOT EXISTS idx_sales_company_document_number
ON pharmacy.sales USING btree (company_id, document_number);

CREATE INDEX IF NOT EXISTS idx_sales_company_created_at_desc
ON pharmacy.sales USING btree (company_id, created_at DESC);

-- 2. sales_returns
CREATE INDEX IF NOT EXISTS idx_sales_returns_company_sale_created_at_desc
ON pharmacy.sales_returns USING btree (company_id, sale_id, created_at DESC);

-- 3. sales_return_items
CREATE INDEX IF NOT EXISTS idx_sales_return_items_company_sale_item_id
ON pharmacy.sales_return_items USING btree (company_id, sale_item_id);

CREATE INDEX IF NOT EXISTS idx_sales_return_items_company_return_id
ON pharmacy.sales_return_items USING btree (company_id, return_id);

-- 4. dte_documents
CREATE INDEX IF NOT EXISTS idx_dte_documents_company_created_at_desc
ON pharmacy.dte_documents USING btree (company_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_dte_documents_company_type_status_created_at_desc
ON pharmacy.dte_documents USING btree (company_id, dte_type, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_dte_documents_company_folio
ON pharmacy.dte_documents USING btree (company_id, folio);

-- 5. audit_logs
CREATE INDEX IF NOT EXISTS idx_audit_logs_company_created_at_desc
ON pharmacy.audit_logs USING btree (company_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_logs_company_user_created_at_desc
ON pharmacy.audit_logs USING btree (company_id, user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_logs_company_event_type_created_at_desc
ON pharmacy.audit_logs USING btree (company_id, event_type, created_at DESC);

-- 6. inventory_movements
CREATE INDEX IF NOT EXISTS idx_inventory_movements_batch_id_movement_type_created_at
ON pharmacy.inventory_movements USING btree (batch_id, movement_type, created_at);

CREATE INDEX IF NOT EXISTS idx_inventory_movements_company_batch_created_at_desc
ON pharmacy.inventory_movements USING btree (company_id, batch_id, created_at DESC);

-- Already present in base schema on many environments; kept idempotent here.
CREATE INDEX IF NOT EXISTS idx_inventory_movements_company_product_created
ON pharmacy.inventory_movements USING btree (company_id, product_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_inventory_movements_company_from_location_created_at_desc
ON pharmacy.inventory_movements USING btree (company_id, from_location_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_inventory_movements_company_to_location_created_at_desc
ON pharmacy.inventory_movements USING btree (company_id, to_location_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_inventory_movements_company_source_location_created_at_desc
ON pharmacy.inventory_movements USING btree (company_id, source_location_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_inventory_movements_company_destination_location_created_at_desc
ON pharmacy.inventory_movements USING btree (company_id, destination_location_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_inventory_movements_company_reference_folio
ON pharmacy.inventory_movements USING btree (company_id, reference_folio);

-- 7. inventory_batches
CREATE INDEX IF NOT EXISTS idx_inventory_batches_company_batch_number
ON pharmacy.inventory_batches USING btree (company_id, batch_number);

CREATE INDEX IF NOT EXISTS idx_inventory_batches_company_product_expiry_date
ON pharmacy.inventory_batches USING btree (company_id, product_id, expiry_date);

CREATE INDEX IF NOT EXISTS idx_inventory_batches_company_location_id
ON pharmacy.inventory_batches USING btree (company_id, location_id);

CREATE INDEX IF NOT EXISTS idx_inventory_batches_company_product_location_expiry_date
ON pharmacy.inventory_batches USING btree (company_id, product_id, location_id, expiry_date);

-- 8. Partial index for FEFO stock candidates.
CREATE INDEX IF NOT EXISTS idx_inventory_batches_fefo_sellable_partial
ON pharmacy.inventory_batches USING btree (company_id, product_id, expiry_date, location_id)
WHERE current_quantity > 0;
