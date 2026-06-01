-- 20260531145000_purchase_order_reception.sql
-- Phase 3: Recepción física contra Orden de Compra.
-- Creates logistica.create_receipt_from_purchase_order(p_payload jsonb) to atomically record physical receptions against PO.

create or replace function logistica.create_receipt_from_purchase_order(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_purchase_order_id uuid;
  v_warehouse_id uuid;
  v_location_id uuid;
  v_document_type text;
  v_document_number text;
  v_notes text;
  
  v_po logistica.purchase_orders%rowtype;
  v_pol logistica.purchase_order_lines%rowtype;
  v_item logistica.items%rowtype;
  
  v_receipt_id uuid;
  v_receipt_line_id uuid;
  
  v_payload_line jsonb;
  v_line_purchase_order_line_id uuid;
  v_line_received_quantity numeric(14,3);
  v_line_lot_code text;
  v_line_expiration_date date;
  v_line_serial_number text;
  v_line_notes text;
  
  v_pending_qty numeric(14,3);
  v_lot_id uuid;
  v_serial_id uuid;
  
  v_balance logistica.stock_balances%rowtype;
  v_current_qty numeric(14,3);
  v_current_total numeric(14,4);
  v_new_qty numeric(14,3);
  v_new_total numeric(14,4);
  v_new_avg numeric(14,4);
  
  v_items_processed integer := 0;
  v_movements_created integer := 0;
  v_line_number integer := 0;
  v_subtotal_cost numeric(14,4) := 0;
  
  v_total_ordered numeric(14,3) := 0;
  v_total_received numeric(14,3) := 0;
  v_new_po_status text;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_purchase_order_id := nullif(btrim(coalesce(p_payload->>'purchase_order_id', '')), '')::uuid;
  v_warehouse_id := nullif(btrim(coalesce(p_payload->>'warehouse_id', '')), '')::uuid;
  v_location_id := nullif(btrim(coalesce(p_payload->>'location_id', '')), '')::uuid;
  v_document_type := nullif(btrim(coalesce(p_payload->>'document_type', '')), '');
  v_document_number := nullif(btrim(coalesce(p_payload->>'document_number', '')), '');
  v_notes := nullif(btrim(coalesce(p_payload->>'notes', '')), '');

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;
  if v_purchase_order_id is null then
    raise exception 'purchase_order_id es obligatorio';
  end if;
  if v_warehouse_id is null then
    raise exception 'warehouse_id es obligatorio';
  end if;
  if v_location_id is null then
    raise exception 'location_id es obligatorio';
  end if;
  if v_document_number is null or v_document_number = '' then
    raise exception 'document_number es obligatorio';
  end if;

  -- Accesos
  if not public.has_company_access(v_company_id) then
    raise exception 'forbidden';
  end if;
  if not public.has_module_access(v_company_id, 'logistica') then
    raise exception 'module access required';
  end if;
  if not (
    public.is_owner(v_company_id)
    or public.has_role(v_company_id, 'ADMIN_LOGISTICA', 'logistica')
    or public.has_role(v_company_id, 'OPERARIO_LOGISTICA', 'logistica')
  ) then
    raise exception 'insufficient role';
  end if;

  -- Obtener la OC
  select * into v_po
  from logistica.purchase_orders po
  where po.id = v_purchase_order_id
    and po.company_id = v_company_id;

  if not found then
    raise exception 'Orden de compra no encontrada';
  end if;

  if v_po.status = 'ANULADA' then
    raise exception 'La orden de compra está ANULADA';
  end if;
  if v_po.status = 'INGRESADA' then
    raise exception 'La orden de compra ya está completamente INGRESADA';
  end if;

  -- Validar Bodega
  perform 1
  from logistica.warehouses w
  where w.id = v_warehouse_id
    and w.company_id = v_company_id
    and coalesce(w.is_active, true) = true;

  if not found then
    raise exception 'warehouse invalid';
  end if;

  -- Validar Ubicación
  perform 1
  from logistica.locations l
  where l.id = v_location_id
    and l.company_id = v_company_id
    and l.warehouse_id = v_warehouse_id
    and coalesce(l.is_active, true) = true;

  if not found then
    raise exception 'location invalid';
  end if;

  -- Primer paso: validar todas las cantidades, lotes, series y acumular costo
  for v_payload_line in
    select value
    from jsonb_array_elements(coalesce(p_payload->'lines', '[]'::jsonb)) as value
  loop
    v_line_purchase_order_line_id := nullif(btrim(coalesce(v_payload_line->>'purchase_order_line_id', '')), '')::uuid;
    v_line_received_quantity := coalesce((v_payload_line->>'received_quantity')::numeric, 0);
    v_line_lot_code := nullif(btrim(coalesce(v_payload_line->>'lot_code', '')), '');
    v_line_expiration_date := nullif(btrim(coalesce(v_payload_line->>'expiration_date', '')), '')::date;
    v_line_serial_number := nullif(btrim(coalesce(v_payload_line->>'serial_number', '')), '');

    if v_line_purchase_order_line_id is null then
      raise exception 'purchase_order_line_id es obligatorio';
    end if;

    if v_line_received_quantity < 0 then
      raise exception 'La cantidad a recibir no puede ser negativa';
    end if;

    -- Si recibimos en esta línea, validamos
    if v_line_received_quantity > 0 then
      -- Bloquear línea para evitar sobrerecepción concurrente
      select * into v_pol
      from logistica.purchase_order_lines pol
      where pol.id = v_line_purchase_order_line_id
        and pol.purchase_order_id = v_po.id
      for update;

      if not found then
        raise exception 'Línea de orden de compra no encontrada';
      end if;

      v_pending_qty := v_pol.ordered_quantity - v_pol.received_quantity;
      if v_line_received_quantity > v_pending_qty then
        raise exception 'La cantidad a recibir (%) supera la cantidad pendiente (%) en la línea %', v_line_received_quantity, v_pending_qty, v_pol.line_number;
      end if;

      -- Validar Material
      select * into v_item
      from logistica.items i
      where i.id = v_pol.item_id
        and i.company_id = v_company_id
        and coalesce(i.is_active, true) = true;

      if not found then
        raise exception 'Item no encontrado o inactivo';
      end if;

      if (coalesce(v_item.tracks_lot, false) or coalesce(v_item.tracks_expiration, false)) and v_line_lot_code is null then
        raise exception 'El lote es obligatorio para el material %', v_item.name;
      end if;

      if coalesce(v_item.tracks_serial, false) and v_line_serial_number is null then
        raise exception 'El número de serie es obligatorio para el material %', v_item.name;
      end if;

      if coalesce(v_item.tracks_serial, false) and v_line_received_quantity <> 1 then
        raise exception 'Los ítems serializados deben recibirse con cantidad = 1';
      end if;

      v_subtotal_cost := round(v_subtotal_cost + (v_line_received_quantity * v_pol.unit_cost), 4);
      v_items_processed := v_items_processed + 1;
    end if;
  end loop;

  if v_items_processed = 0 then
    raise exception 'Debe recepcionar al menos un ítem con cantidad mayor a cero';
  end if;

  -- Crear Cabecera de Recepción
  insert into logistica.receipt_headers (
    company_id,
    origin_type,
    origin_document_id,
    supplier_id,
    document_type,
    document_number,
    document_date,
    receipt_date,
    cost_center_id,
    warehouse_id,
    location_id,
    status,
    notes,
    subtotal_cost,
    total_cost,
    receipt_reference,
    created_by,
    updated_by,
    posted_by,
    posted_at
  ) values (
    v_company_id,
    'purchase_order',
    v_po.id,
    v_po.supplier_id,
    v_document_type,
    v_document_number,
    current_date,
    now(),
    v_po.cost_center_id,
    v_warehouse_id,
    v_location_id,
    'posted',
    v_notes,
    v_subtotal_cost,
    v_subtotal_cost,
    v_document_number,
    v_user_id,
    v_user_id,
    v_user_id,
    now()
  ) returning id into v_receipt_id;

  -- Segundo paso: insertar líneas de recepción, lote, serial, movimientos de stock, balances y actualizar PO lines
  for v_payload_line in
    select value
    from jsonb_array_elements(coalesce(p_payload->'lines', '[]'::jsonb)) as value
  loop
    v_line_purchase_order_line_id := nullif(btrim(coalesce(v_payload_line->>'purchase_order_line_id', '')), '')::uuid;
    v_line_received_quantity := coalesce((v_payload_line->>'received_quantity')::numeric, 0);
    v_line_lot_code := nullif(btrim(coalesce(v_payload_line->>'lot_code', '')), '');
    v_line_expiration_date := nullif(btrim(coalesce(v_payload_line->>'expiration_date', '')), '')::date;
    v_line_serial_number := nullif(btrim(coalesce(v_payload_line->>'serial_number', '')), '');
    v_line_notes := nullif(btrim(coalesce(v_payload_line->>'notes', '')), '');

    if v_line_received_quantity > 0 then
      v_line_number := v_line_number + 1;

      -- Cargar línea PO (con lock)
      select * into v_pol
      from logistica.purchase_order_lines pol
      where pol.id = v_line_purchase_order_line_id
      for update;

      v_pending_qty := v_pol.ordered_quantity - v_pol.received_quantity;

      -- Insertar Receipt Line
      insert into logistica.receipt_lines (
        company_id,
        receipt_id,
        line_number,
        item_id,
        origin_document_line_id,
        ordered_quantity_snapshot,
        pending_quantity_snapshot,
        received_quantity,
        unit_cost,
        total_cost,
        lot_code,
        serial_number,
        expiration_date,
        notes
      ) values (
        v_company_id,
        v_receipt_id,
        v_line_number,
        v_pol.item_id,
        v_pol.id,
        v_pol.ordered_quantity,
        v_pending_qty,
        v_line_received_quantity,
        v_pol.unit_cost,
        round(v_line_received_quantity * v_pol.unit_cost, 4),
        v_line_lot_code,
        v_line_serial_number,
        v_line_expiration_date,
        v_line_notes
      ) returning id into v_receipt_line_id;

      -- Crear/actualizar lote si aplica
      v_lot_id := null;
      if v_line_lot_code is not null then
        insert into logistica.item_lots (
          company_id,
          item_id,
          lot_code,
          manufacture_date,
          expiration_date,
          supplier_name,
          source_module,
          source_document_type,
          source_document_id,
          unit_cost,
          is_active,
          created_by,
          updated_by
        ) values (
          v_company_id,
          v_pol.item_id,
          v_line_lot_code,
          null,
          v_line_expiration_date,
          null,
          'logistica',
          'PURCHASE_RECEIPT',
          v_receipt_id,
          v_pol.unit_cost,
          true,
          v_user_id,
          v_user_id
        )
        on conflict (company_id, item_id, lot_code)
        do update set
          expiration_date = coalesce(excluded.expiration_date, logistica.item_lots.expiration_date),
          source_module = excluded.source_module,
          source_document_type = excluded.source_document_type,
          source_document_id = excluded.source_document_id,
          unit_cost = coalesce(excluded.unit_cost, logistica.item_lots.unit_cost),
          updated_at = now(),
          updated_by = excluded.updated_by
        returning id into v_lot_id;
      end if;

      -- Crear/actualizar serial si aplica
      v_serial_id := null;
      if v_line_serial_number is not null then
        insert into logistica.item_serials (
          company_id,
          item_id,
          serial_number,
          status,
          current_warehouse_id,
          current_location_id,
          current_custodian_type,
          current_custodian_id,
          current_project_id,
          source_module,
          source_document_type,
          source_document_id,
          is_active,
          created_by,
          updated_by
        ) values (
          v_company_id,
          v_pol.item_id,
          v_line_serial_number,
          'available',
          v_warehouse_id,
          v_location_id,
          null,
          null,
          null,
          'logistica',
          'PURCHASE_RECEIPT',
          v_receipt_id,
          true,
          v_user_id,
          v_user_id
        )
        on conflict (company_id, item_id, serial_number)
        do update set
          status = excluded.status,
          current_warehouse_id = excluded.current_warehouse_id,
          current_location_id = excluded.current_location_id,
          source_module = excluded.source_module,
          source_document_type = excluded.source_document_type,
          source_document_id = excluded.source_document_id,
          is_active = excluded.is_active,
          updated_at = now(),
          updated_by = excluded.updated_by
        returning id into v_serial_id;
      end if;

      -- Crear Movimiento de Stock
      insert into logistica.stock_movements (
        company_id,
        item_id,
        lot_id,
        serial_id,
        cost_center_id,
        movement_type,
        movement_reason,
        quantity,
        unit_cost,
        total_cost,
        from_warehouse_id,
        from_location_id,
        to_warehouse_id,
        to_location_id,
        source_module,
        source_document_type,
        source_document_id,
        target_module,
        target_document_type,
        target_document_id,
        reference_number,
        notes,
        metadata,
        created_by,
        receipt_id,
        receipt_line_id
      ) values (
        v_company_id,
        v_pol.item_id,
        v_lot_id,
        v_serial_id,
        v_po.cost_center_id,
        'RECEIPT',
        'PURCHASE_RECEIPT',
        v_line_received_quantity,
        v_pol.unit_cost,
        round(v_line_received_quantity * v_pol.unit_cost, 4),
        null,
        null,
        v_warehouse_id,
        v_location_id,
        'logistica',
        'purchase_order',
        v_po.id,
        null,
        null,
        null,
        v_document_number,
        v_line_notes,
        jsonb_build_object('purchase_order_id', v_po.id, 'purchase_order_line_id', v_pol.id, 'receipt_id', v_receipt_id, 'receipt_line_id', v_receipt_line_id),
        v_user_id,
        v_receipt_id,
        v_receipt_line_id
      );

      v_movements_created := v_movements_created + 1;

      -- Actualizar Stock Balance
      select * into v_balance
      from logistica.stock_balances b
      where b.company_id = v_company_id
        and b.item_id = v_pol.item_id
        and b.lot_id is not distinct from v_lot_id
        and b.warehouse_id = v_warehouse_id
        and b.location_id is not distinct from v_location_id
        and b.cost_center_id is not distinct from v_po.cost_center_id
      for update;

      if found then
        v_current_qty := coalesce(v_balance.quantity_on_hand, 0);
        v_current_total := coalesce(v_balance.total_cost, v_current_qty * coalesce(v_balance.average_unit_cost, 0));
        v_new_qty := v_current_qty + v_line_received_quantity;
        v_new_total := v_current_total + round(v_line_received_quantity * v_pol.unit_cost, 4);
        v_new_avg := case when v_new_qty <> 0 then round(v_new_total / v_new_qty, 4) else v_pol.unit_cost end;

        update logistica.stock_balances
        set quantity_on_hand = v_new_qty,
            average_unit_cost = v_new_avg,
            total_cost = v_new_total,
            last_movement_at = now(),
            updated_at = now()
        where id = v_balance.id;
      else
        v_new_qty := v_line_received_quantity;
        v_new_total := round(v_line_received_quantity * v_pol.unit_cost, 4);
        v_new_avg := v_pol.unit_cost;

        insert into logistica.stock_balances (
          company_id,
          item_id,
          lot_id,
          warehouse_id,
          location_id,
          cost_center_id,
          quantity_on_hand,
          quantity_reserved,
          average_unit_cost,
          total_cost,
          last_movement_at
        ) values (
          v_company_id,
          v_pol.item_id,
          v_lot_id,
          v_warehouse_id,
          v_location_id,
          v_po.cost_center_id,
          v_new_qty,
          0,
          v_new_avg,
          v_new_total,
          now()
        );
      end if;

      -- Actualizar cantidad recibida en la línea de la OC
      update logistica.purchase_order_lines
      set received_quantity = received_quantity + v_line_received_quantity,
          updated_at = now()
      where id = v_pol.id;
    end if;
  end loop;

  -- Re-calcular estado global de la OC
  select
    coalesce(sum(ordered_quantity), 0),
    coalesce(sum(received_quantity), 0)
  into v_total_ordered, v_total_received
  from logistica.purchase_order_lines
  where purchase_order_id = v_po.id;

  v_new_po_status := case
    when v_total_received = 0 then 'PENDING'
    when v_total_received < v_total_ordered then 'PARCIAL'
    else 'INGRESADA'
  end;

  update logistica.purchase_orders
  set status = v_new_po_status,
      updated_at = now()
  where id = v_po.id;

  return jsonb_build_object(
    'success', true,
    'receipt_id', v_receipt_id,
    'receipt_reference', v_document_number,
    'purchase_order_id', v_po.id,
    'purchase_order_status', v_new_po_status,
    'movements_created', v_movements_created,
    'items_processed', v_items_processed
  );
end;
$$;

grant execute on function logistica.create_receipt_from_purchase_order(jsonb) to authenticated;
