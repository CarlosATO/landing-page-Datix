-- Seed prescription validity rules
INSERT INTO pharmacy.prescription_validity_rules (prescription_type, validity_days)
VALUES 
  ('RECETA_SIMPLE', 30),
  ('RECETA_RETENIDA', 30),
  ('RECETA_CHEQUE', 30)
ON CONFLICT (prescription_type) 
DO UPDATE SET validity_days = EXCLUDED.validity_days, updated_at = now();
