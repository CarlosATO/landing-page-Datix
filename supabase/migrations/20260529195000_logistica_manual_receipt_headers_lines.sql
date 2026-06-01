-- 20260529195000_logistica_manual_receipt_headers_lines.sql
-- C2 real: create_manual_receipt crea header + lines y mantiene compatibilidad de retorno.

create or replace function logistica.create_manual_receipt(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_supplier_id uuid;
  v_warehouse_id uuid;
  v_location_id uuid;
  v_cost_center_id uuid;
  v_reference_number text;
  v_notes text;
  v_payload_item jsonb;
  v_item_id uuid;
  v_quantity numeric(14,3);
  v_unit_cost numeric(14,4);
  v_total_cost numeric(14,4);
  v_lot_code text;
  v_expiration_date date;
  v_serial_number text;
  v_item logistica.items%rowtype;
  v_supplier public.suppliers%rowtype;
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
  v_receipt_id uuid;
  v_receipt_line_id uuid;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_supplier_id := nullif(btrim(coalesce(p_payload->>'supplier_id', '')), '')::uuid;
  v_warehouse_id := nullif(btrim(coalesce(p_payload->>'warehouse_id', '')), '')::uuid;
  v_location_id := nullif(btrim(coalesce(p_payload->>'location_id', '')), '')::uuid;
  v_cost_center_id := nullif(btrim(coalesce(p_payload->>'cost_center_id', '')), '')::uuid;
  v_reference_number := btrim(coalesce(p_payload->>'reference_number', ''));
  v_notes := nullif(btrim(coalesce(p_payload->>'notes', '')), '');

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if v_supplier_id is null then
    raise exception 'supplier_id es obligatorio';
  end if;

  if v_warehouse_id is null then
    raise exception 'warehouse_id es obligatorio';
  end if;

  if v_location_id is null then
    raise exception 'location_id es obligatorio';
  end if;

  if v_cost_center_id is null then
    raise exception 'cost_center_id es obligatorio';
  end if;

  if v_reference_number = '' then
    raise exception 'reference_number es obligatorio';
  end if;

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

  select *
    into v_supplier
  from public.suppliers s
  where s.id = v_supplier_id
    and s.company_id = v_company_id
    and coalesce(s.is_active, true) = true;

  if not found then
    raise exception 'supplier invalid';
  end if;

  perform 1
  from logistica.warehouses w
  where w.id = v_warehouse_id
    and w.company_id = v_company_id
    and coalesce(w.is_active, true) = true;

  if not found then
    raise exception 'warehouse invalid';
  end if;

  perform 1
  from logistica.locations l
  where l.id = v_location_id
    and l.company_id = v_company_id
    and l.warehouse_id = v_warehouse_id
    and coalesce(l.is_active, true) = true;

  if not found then
    raise exception 'location invalid';
  end if;

  perform 1
  from public.cost_centers cc
  where cc.id = v_cost_center_id
    and cc.company_id = v_company_id
    and coalesce(cc.is_active, true) = true;

  if not found then
    raise exception 'cost center invalid';
  end if;

  -- First pass: validate items and compute subtotal before creating the header.
  for v_payload_item in
    select value
    from jsonb_array_elements(coalesce(p_payload->'items', '[]'::jsonb)) as value
  loop
    v_item_id := nullif(btrim(coalesce(v_payload_item->>'item_id', '')), '')::uuid;
    v_quantity := coalesce((v_payload_item->>'quantity')::numeric, 0);
    v_unit_cost := coalesce((v_payload_item->>'unit_cost')::numeric, -1);
    v_lot_code := nullif(btrim(coalesce(v_payload_item->>'lot_code', '')), '');
    v_expiration_date := nullif(btrim(coalesce(v_payload_item->>'expiration_date', '')), '')::date;
    v_serial_number := nullif(btrim(coalesce(v_payload_item->>'serial_number', '')), '');

    if v_item_id is null then
      raise exception 'item_id es obligatorio';
    end if;

    if v_quantity <= 0 then
      raise exception 'quantity debe ser mayor a cero';
    end if;

    if v_unit_cost < 0 then
      raise exception 'unit_cost no puede ser negativo';
    end if;

    select *
      into v_item
    from logistica.items i
    where i.id = v_item_id
      and i.company_id = v_company_id
      and coalesce(i.is_active, true) = true;

    if not found then
      raise exception 'item invalid';
    end if;

    if (coalesce(v_item.tracks_lot, false) or coalesce(v_item.tracks_expiration, false)) and v_lot_code is null then
      raise exception 'lot_code es obligatorio para este ítem';
    end if;

    if coalesce(v_item.tracks_serial, false) and v_serial_number is null then
      raise exception 'serial_number es obligatorio para este ítem';
    end if;

    if coalesce(v_item.tracks_serial, false) and v_quantity <> 1 then
      raise exception 'Los ítems serializados deben recibirse con quantity = 1';
    end if;

    v_subtotal_cost := round(v_subtotal_cost + (v_quantity * v_unit_cost), 4);
  end loop;

  insert into logistica.receipt_headers (
    company_id,
    origin_type,
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
    idempotency_key,
    created_by,
    updated_by,
    posted_by,
    posted_at
  ) values (
    v_company_id,
    'manual',
    v_supplier_id,
    null,
    v_reference_number,
    null,
    now(),
    v_cost_center_id,
    v_warehouse_id,
    v_location_id,
    'posted',
    v_notes,
    v_subtotal_cost,
    v_subtotal_cost,
    v_reference_number,
    null,
    v_user_id,
    v_user_id,
    v_user_id,
    now()
  )
  returning id into v_receipt_id;

  -- Second pass: create lines and stock movements atomically.
  for v_payload_item in
    select value
    from jsonb_array_elements(coalesce(p_payload->'items', '[]'::jsonb)) as value
  loop
    v_line_number := v_line_number + 1;
    v_items_processed := v_items_processed + 1;

    v_item_id := nullif(btrim(coalesce(v_payload_item->>'item_id', '')), '')::uuid;
    v_quantity := coalesce((v_payload_item->>'quantity')::numeric, 0);
    v_unit_cost := coalesce((v_payload_item->>'unit_cost')::numeric, -1);
    v_lot_code := nullif(btrim(coalesce(v_payload_item->>'lot_code', '')), '');
    v_expiration_date := nullif(btrim(coalesce(v_payload_item->>'expiration_date', '')), '')::date;
    v_serial_number := nullif(btrim(coalesce(v_payload_item->>'serial_number', '')), '');

    select *
      into v_item
    from logistica.items i
    where i.id = v_item_id
      and i.company_id = v_company_id
      and coalesce(i.is_active, true) = true;

    v_total_cost := round(v_quantity * v_unit_cost, 4);

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
      v_item.id,
      null,
      null,
      null,
      v_quantity,
      v_unit_cost,
      v_total_cost,
      v_lot_code,
      v_serial_number,
      v_expiration_date,
      nullif(btrim(coalesce(v_payload_item->>'notes', '')), '')
    )
    returning id into v_receipt_line_id;

    v_lot_id := null;
    if v_lot_code is not null then
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
      )
      values (
        v_company_id,
        v_item.id,
        v_lot_code,
        null,
        v_expiration_date,
        null,
        'logistica',
        'MANUAL_RECEIPT',
        v_receipt_id,
        v_unit_cost,
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

    v_serial_id := null;
    if v_serial_number is not null then
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
      )
      values (
        v_company_id,
        v_item.id,
        v_serial_number,
        'available',
        v_warehouse_id,
        v_location_id,
        null,
        null,
        null,
        'logistica',
        'MANUAL_RECEIPT',
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
        current_custodian_type = excluded.current_custodian_type,
        current_custodian_id = excluded.current_custodian_id,
        current_project_id = excluded.current_project_id,
        source_module = excluded.source_module,
        source_document_type = excluded.source_document_type,
        source_document_id = excluded.source_document_id,
        is_active = excluded.is_active,
        updated_at = now(),
        updated_by = excluded.updated_by
      returning id into v_serial_id;
    end if;

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
      v_item.id,
      v_lot_id,
      v_serial_id,
      v_cost_center_id,
      'RECEIPT',
      'MANUAL_RECEIPT',
      v_quantity,
      v_unit_cost,
      v_total_cost,
      null,
      null,
      v_warehouse_id,
      v_location_id,
      'logistica',
      'MANUAL_RECEIPT',
      v_receipt_id,
      null,
      null,
      null,
      v_reference_number,
      coalesce(v_notes, v_payload_item->>'notes'),
      jsonb_build_object('manual_receipt', true, 'cost_center_id', v_cost_center_id, 'receipt_id', v_receipt_id, 'receipt_line_id', v_receipt_line_id),
      v_user_id,
      v_receipt_id,
      v_receipt_line_id
    );

    v_movements_created := v_movements_created + 1;

    select *
      into v_balance
    from logistica.stock_balances b
    where b.company_id = v_company_id
      and b.item_id = v_item.id
      and b.lot_id is not distinct from v_lot_id
      and b.warehouse_id = v_warehouse_id
      and b.location_id is not distinct from v_location_id
      and b.cost_center_id is not distinct from v_cost_center_id
    for update;

    if found then
      v_current_qty := coalesce(v_balance.quantity_on_hand, 0);
      v_current_total := coalesce(v_balance.total_cost, v_current_qty * coalesce(v_balance.average_unit_cost, 0));
      v_new_qty := v_current_qty + v_quantity;
      v_new_total := v_current_total + v_total_cost;
      v_new_avg := case when v_new_qty <> 0 then round(v_new_total / v_new_qty, 4) else v_unit_cost end;

      update logistica.stock_balances
         set quantity_on_hand = v_new_qty,
             average_unit_cost = v_new_avg,
             total_cost = v_new_total,
             cost_center_id = v_cost_center_id,
             last_movement_at = now(),
             updated_at = now()
       where id = v_balance.id;
    else
      v_new_qty := v_quantity;
      v_new_total := v_total_cost;
      v_new_avg := case when v_new_qty <> 0 then round(v_new_total / v_new_qty, 4) else v_unit_cost end;

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
        v_item.id,
        v_lot_id,
        v_warehouse_id,
        v_location_id,
        v_cost_center_id,
        v_new_qty,
        0,
        v_new_avg,
        v_new_total,
        now()
      );
    end if;
  end loop;

  return jsonb_build_object(
    'success', true,
    'receipt_reference', v_reference_number,
    'movements_created', v_movements_created,
    'items_processed', v_items_processed
  );
end;
$$;

grant execute on function logistica.create_manual_receipt(jsonb) to authenticated;
