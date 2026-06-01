-- Normaliza el CHECK de pharmacy.inventory_movements.movement_type
-- sin modificar datos existentes y preservando tipos legacy.

ALTER TABLE pharmacy.inventory_movements
  DROP CONSTRAINT IF EXISTS inventory_movements_movement_type_check;

ALTER TABLE pharmacy.inventory_movements
  ADD CONSTRAINT inventory_movements_movement_type_check
  CHECK (
    movement_type = ANY (
      ARRAY[
        'IN'::text,
        'OUT'::text,
        'ADJUSTMENT'::text,
        'INITIAL_LOAD'::text,
        'IN_PURCHASE'::text,
        'PURCHASE_RECEIPT'::text,
        'SALE'::text,
        'RETURN'::text,
        'INTERNAL_TRANSFER'::text,
        'OUTBOUND_TRANSFER'::text,
        'INBOUND_TRANSFER'::text,
        'ADJUSTMENT_IN'::text,
        'ADJUSTMENT_OUT'::text
      ]
    )
  );
