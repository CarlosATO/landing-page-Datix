# Pharmacy

Scope:
- pharmacy schema
- POS
- recetas
- DTE
- returns
- catalog
- pricing
- bioequivalencia
- dashboard farmacia
- compras farmacia

| Timestamp | File | Purpose | Status |
| --- | --- | --- | --- |
| 20260507165212 | `20260507165212_remote_schema.sql` | Base remote schema snapshot | applied in remote |
| 20260507173000 | `20260507173000_add_prescription_validity_to_sale.sql` | Prescription validity support | applied in remote |
| 20260507175000 | `20260507175000_seed_prescription_validity_rules.sql` | Seed prescription validity rules | applied in remote |
| 20260507190000 | `20260507190000_harden_pos_concurrency.sql` | POS concurrency hardening | applied in remote |
| 20260507200000 | `20260507200000_advanced_isp_audit.sql` | Advanced audit controls | applied in remote |
| 20260507210000 | `20260507210000_create_internal_dte_architecture.sql` | Internal DTE architecture | applied in remote |
| 20260507213000 | `20260507213000_fix_dte_integration.sql` | DTE integration fixes | applied in remote |
| 20260507215000 | `20260507215000_harden_dte_permissions.sql` | DTE permissions hardening | applied in remote |
| 20260508100000 | `20260508100000_pharmacy_returns_architecture.sql` | Returns architecture | applied in remote |
| 20260508101000 | `20260508101000_harden_returns_permissions.sql` | Returns permissions hardening | applied in remote |
| 20260508102000 | `20260508102000_fix_returns_audit_logic.sql` | Returns audit logic fix | applied in remote |
| 20260508103000 | `20260508103000_fix_lot_traceability_and_uniqueness.sql` | Lot traceability and uniqueness | applied in remote |
| 20260508130000 | `20260508130000_performance_indexes_core.sql` | Core performance indexes | applied in remote |
| 20260508140000 | `20260508140000_inventory_alerts_engine.sql` | Inventory alerts engine | applied in remote |
| 20260508150000 | `20260508150000_fix_returns_location_type_model.sql` | Returns location type model fix | applied in remote |
| 20260508160000 | `20260508160000_catalog_bulk_import_support.sql` | Catalog bulk import support | applied in remote |
| 20260508170000 | `20260508170000_catalog_bulk_import_hardening.sql` | Catalog bulk import hardening | applied in remote |
| 20260508180000 | `20260508180000_fix_bulk_import_composite_key.sql` | Bulk import composite key fix | applied in remote |
| 20260508190000 | `20260508190000_fix_bulk_import_composite_key_v2.sql` | Bulk import composite key fix v2 | applied in remote |
| 20260508200000 | `20260508200000_fix_bulk_import_error_message.sql` | Bulk import error message fix | applied in remote |
| 20260508210000 | `20260508210000_fix_bulk_import_composite_key_v3.sql` | Bulk import composite key fix v3 | applied in remote |
| 20260508220000 | `20260508220000_pos_bioequivalent_engine.sql` | POS bioequivalent engine | applied in remote |
| 20260508223000 | `20260508223000_fix_bioequivalent_suggestion_types.sql` | Bioequivalent suggestion types fix | applied in remote |
| 20260513123000 | `20260513123000_dashboard_gerencial_v1.sql` | Pharmacy dashboard v1 | applied in remote |
| 20260513143000 | `20260513143000_dashboard_gerencial_v2.sql` | Pharmacy dashboard v2 | applied in remote |
| 20260513160000 | `20260513160000_dashboard_gerencial_v2_1.sql` | Pharmacy dashboard v2.1 | applied in remote |
| 20260513190000 | `20260513190000_purchase_recommendations_v1.sql` | Purchase recommendations | applied in remote |
| 20260513220000 | `20260513220000_cancel_purchase_order_v1.sql` | Cancel purchase order | applied in remote |
| 20260513233000 | `20260513233000_receive_purchase_order_transactional.sql` | Receive purchase order transactionally | applied in remote |
| 20260513235000 | `20260513235000_internal_transfer_transactional_v1.sql` | Internal transfer transactionally | applied in remote |
| 20260514120000 | `20260514120000_normalize_inventory_movement_types.sql` | Normalize inventory movement types | applied in remote |
| 20260514150000 | `20260514150000_normalize_purchase_order_approval_flow.sql` | Normalize purchase order approval flow | applied in remote |
| 20260515103000 | `20260515103000_emit_purchase_order_v1.sql` | Emit purchase order v1 | applied in remote |
| 20260515180000 | `20260515180000_hybrid_branch_pricing_v1.sql` | Hybrid branch pricing v1 | applied in remote |
| 20260515220000 | `20260515220000_pricing_matrix_centralized_v1.sql` | Centralized pricing matrix v1 | applied in remote |
| 20260515231000 | `20260515231000_fix_upsert_corporate_price_no_active.sql` | Fix inactive corporate price upsert | applied in remote |
| 20260516090000 | `20260516090000_bulk_upsert_branch_prices.sql` | Bulk upsert branch prices | applied in remote |
| 20260516093000 | `20260516093000_harden_bulk_upsert_branch_prices_warehouse_scope.sql` | Warehouse scope hardening for branch prices | applied in remote |
| 20260516100000 | `20260516100000_create_warehouse_with_default_locations.sql` | Create warehouse with default locations | applied in remote |
| 20260516103000 | `20260516103000_harden_warehouse_update_deactivate.sql` | Warehouse update/deactivate hardening | applied in remote |
| 20260516110000 | `20260516110000_harden_pos_operators.sql` | POS operators hardening | applied in remote |
| 20260516113000 | `20260516113000_fix_pos_operator_pin_hashing.sql` | POS operator PIN hashing fix | applied in remote |
| 20260516114000 | `20260516114000_fix_pos_operator_crypto_schema.sql` | POS operator crypto schema fix | applied in remote |
| 20260516120000 | `20260516120000_harden_audit_module.sql` | Audit module hardening | applied in remote |
| 20260516123000 | `20260516123000_audit_backend_owned_events.sql` | Backend-owned event audit | applied in remote |
| 20260516130000 | `20260516130000_harden_pos_cash_sessions.sql` | POS cash sessions hardening | applied in remote |
