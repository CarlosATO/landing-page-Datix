create or replace function logistica.create_stock_transfer(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_from_warehouse_id uuid;
  v_from_location_id uuid;
  v_to_warehouse_id uuid;
  v_to_location_id uuid;
  v_reference_number text;
  v_notes text;
  v_payload_item jsonb;
  v_item_id uuid;
  v_quantity numeric(14,3);
  v_item_notes text;
  v_lot_id uuid;
  v_serial_id uuid;
  v_item logistica.items%rowtype;
  v_from_warehouse logistica.warehouses%rowtype;
  v_to_warehouse logistica.warehouses%rowtype;
  v_from_location logistica.locations%rowtype;
  v_to_location logistica.locations%rowtype;
  v_origin_balance logistica.stock_balances%rowtype;
  v_dest_balance logistica.stock_balances%rowtype;
  v_serial logistica.item_serials%rowtype;
  v_origin_qty numeric(14,3);
  v_origin_total numeric(14,4);
  v_origin_avg numeric(14,4);
  v_origin_new_qty numeric(14,3);
  v_origin_new_total numeric(14,4);
  v_origin_new_avg numeric(14,4);
  v_dest_qty numeric(14,3);
  v_dest_total numeric(14,4);
  v_dest_avg numeric(14,4);
  v_dest_new_qty numeric(14,3);
  v_dest_new_total numeric(14,4);
  v_dest_new_avg numeric(14,4);
  v_unit_cost numeric(14,4);
  v_total_cost numeric(14,4);
  v_items_processed integer := 0;
  v_movements_created integer := 0;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_from_warehouse_id := nullif(btrim(coalesce(p_payload->>'from_warehouse_id', '')), '')::uuid;
  v_from_location_id := nullif(btrim(coalesce(p_payload->>'from_location_id', '')), '')::uuid;
  v_to_warehouse_id := nullif(btrim(coalesce(p_payload->>'to_warehouse_id', '')), '')::uuid;
  v_to_location_id := nullif(btrim(coalesce(p_payload->>'to_location_id', '')), '')::uuid;
  v_reference_number := btrim(coalesce(p_payload->>'reference_number', ''));
  v_notes := nullif(btrim(coalesce(p_payload->>'notes', '')), '');

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if v_from_warehouse_id is null then
    raise exception 'from_warehouse_id es obligatorio';
  end if;

  if v_to_warehouse_id is null then
    raise exception 'to_warehouse_id es obligatorio';
  end if;

  if v_reference_number = '' then
    raise exception 'reference_number es obligatorio';
  end if;

  if p_payload->'items' is null or jsonb_typeof(p_payload->'items') <> 'array' then
    raise exception 'items es obligatorio';
  end if;

  if v_from_warehouse_id = v_to_warehouse_id
     and coalesce(v_from_location_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(v_to_location_id, '00000000-0000-0000-0000-000000000000'::uuid) then
    raise exception 'origin and destination must differ';
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
    into v_from_warehouse
  from logistica.warehouses w
  where w.id = v_from_warehouse_id
    and w.company_id = v_company_id
    and coalesce(w.is_active, true) = true;

  if not found then
    raise exception 'from_warehouse invalid';
  end if;

  select *
    into v_to_warehouse
  from logistica.warehouses w
  where w.id = v_to_warehouse_id
    and w.company_id = v_company_id
    and coalesce(w.is_active, true) = true;

  if not found then
    raise exception 'to_warehouse invalid';
  end if;

  if v_from_location_id is not null then
    select *
      into v_from_location
    from logistica.locations l
    where l.id = v_from_location_id
      and l.company_id = v_company_id
      and l.warehouse_id = v_from_warehouse_id
      and coalesce(l.is_active, true) = true;

    if not found then
      raise exception 'from_location invalid';
    end if;
  end if;

  if v_to_location_id is not null then
    select *
      into v_to_location
    from logistica.locations l
    where l.id = v_to_location_id
      and l.company_id = v_company_id
      and l.warehouse_id = v_to_warehouse_id
      and coalesce(l.is_active, true) = true;

    if not found then
      raise exception 'to_location invalid';
    end if;
  end if;

  for v_payload_item in
    select value
    from jsonb_array_elements(p_payload->'items') as value
  loop
    v_items_processed := v_items_processed + 1;

    v_item_id := nullif(btrim(coalesce(v_payload_item->>'item_id', '')), '')::uuid;
    v_quantity := coalesce((v_payload_item->>'quantity')::numeric, 0);
    v_lot_id := nullif(btrim(coalesce(v_payload_item->>'lot_id', '')), '')::uuid;
    v_serial_id := nullif(btrim(coalesce(v_payload_item->>'serial_id', '')), '')::uuid;
    v_item_notes := nullif(btrim(coalesce(v_payload_item->>'notes', '')), '');

    if v_item_id is null then
      raise exception 'item_id es obligatorio';
    end if;

    if v_quantity <= 0 then
      raise exception 'quantity debe ser mayor a cero';
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

    if coalesce(v_item.tracks_serial, false) then
      if v_serial_id is null then
        raise exception 'serial_id es obligatorio para este ítem';
      end if;

      if v_quantity <> 1 then
        raise exception 'Los ítems serializados deben transferirse con quantity = 1';
      end if;
    elsif v_serial_id is not null then
      raise exception 'serial_id no permitido para este ítem';
    end if;

    if coalesce(v_item.tracks_lot, false) then
      if v_lot_id is null then
        raise exception 'lot_id es obligatorio para este ítem';
      end if;
    elsif v_lot_id is not null then
      raise exception 'lot_id no permitido para este ítem';
    end if;

    if v_lot_id is not null then
      perform 1
      from logistica.item_lots l
      where l.id = v_lot_id
        and l.company_id = v_company_id
        and l.item_id = v_item.id
        and coalesce(l.is_active, true) = true;

      if not found then
        raise exception 'lot invalid';
      end if;
    end if;

    if v_serial_id is not null then
      select *
        into v_serial
      from logistica.item_serials s
      where s.id = v_serial_id
        and s.company_id = v_company_id
        and s.item_id = v_item.id
        and coalesce(s.is_active, true) = true
      for update;

      if not found then
        raise exception 'serial invalid';
      end if;

      if v_serial.status <> 'available' then
        raise exception 'serial not available';
      end if;

      if v_serial.current_warehouse_id is distinct from v_from_warehouse_id
         or v_serial.current_location_id is distinct from v_from_location_id then
        raise exception 'serial not in origin';
      end if;
    end if;

    select *
      into v_origin_balance
    from logistica.stock_balances b
    where b.company_id = v_company_id
      and b.item_id = v_item.id
      and b.lot_id is not distinct from v_lot_id
      and b.warehouse_id = v_from_warehouse_id
      and b.location_id is not distinct from v_from_location_id
    for update;

    if not found then
      raise exception 'origin stock not found';
    end if;

    v_origin_qty := coalesce(v_origin_balance.quantity_on_hand, 0);
    v_origin_total := coalesce(v_origin_balance.total_cost, v_origin_qty * coalesce(v_origin_balance.average_unit_cost, 0));
    v_origin_avg := coalesce(v_origin_balance.average_unit_cost, case when v_origin_qty <> 0 then round(v_origin_total / v_origin_qty, 4) else 0 end);

    if (v_origin_qty - coalesce(v_origin_balance.quantity_reserved, 0)) < v_quantity then
      raise exception 'insufficient stock';
    end if;

    v_unit_cost := coalesce(v_origin_balance.average_unit_cost, case when v_origin_qty <> 0 then round(v_origin_total / v_origin_qty, 4) else 0 end);
    v_total_cost := round(v_quantity * v_unit_cost, 4);

    insert into logistica.stock_movements (
      company_id,
      item_id,
      lot_id,
      serial_id,
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
      created_by
    ) values (
      v_company_id,
      v_item.id,
      v_lot_id,
      v_serial_id,
      'TRANSFER_OUT',
      'STOCK_TRANSFER',
      v_quantity,
      v_unit_cost,
      v_total_cost,
      v_from_warehouse_id,
      v_from_location_id,
      v_to_warehouse_id,
      v_to_location_id,
      'logistica',
      'STOCK_TRANSFER',
      null,
      'logistica',
      'STOCK_TRANSFER',
      null,
      v_reference_number,
      coalesce(v_item_notes, v_notes),
      jsonb_build_object(
        'stock_transfer', true,
        'direction', 'out',
        'origin_warehouse_id', v_from_warehouse_id,
        'origin_location_id', v_from_location_id,
        'destination_warehouse_id', v_to_warehouse_id,
        'destination_location_id', v_to_location_id
      ),
      v_user_id
    );

    insert into logistica.stock_movements (
      company_id,
      item_id,
      lot_id,
      serial_id,
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
      created_by
    ) values (
      v_company_id,
      v_item.id,
      v_lot_id,
      v_serial_id,
      'TRANSFER_IN',
      'STOCK_TRANSFER',
      v_quantity,
      v_unit_cost,
      v_total_cost,
      v_from_warehouse_id,
      v_from_location_id,
      v_to_warehouse_id,
      v_to_location_id,
      'logistica',
      'STOCK_TRANSFER',
      null,
      'logistica',
      'STOCK_TRANSFER',
      null,
      v_reference_number,
      coalesce(v_item_notes, v_notes),
      jsonb_build_object(
        'stock_transfer', true,
        'direction', 'in',
        'origin_warehouse_id', v_from_warehouse_id,
        'origin_location_id', v_from_location_id,
        'destination_warehouse_id', v_to_warehouse_id,
        'destination_location_id', v_to_location_id
      ),
      v_user_id
    );

    v_movements_created := v_movements_created + 2;

    v_origin_new_qty := round(v_origin_qty - v_quantity, 3);
    v_origin_new_total := round(v_origin_total - v_total_cost, 4);

    if v_origin_new_total < 0 then
      v_origin_new_total := 0;
    end if;

    v_origin_new_avg := case
      when v_origin_new_qty <> 0 then round(v_origin_new_total / v_origin_new_qty, 4)
      else v_origin_avg
    end;

    update logistica.stock_balances
       set quantity_on_hand = v_origin_new_qty,
           average_unit_cost = v_origin_new_avg,
           total_cost = v_origin_new_total,
           last_movement_at = now(),
           updated_at = now()
     where id = v_origin_balance.id;

    select *
      into v_dest_balance
    from logistica.stock_balances b
    where b.company_id = v_company_id
      and b.item_id = v_item.id
      and b.lot_id is not distinct from v_lot_id
      and b.warehouse_id = v_to_warehouse_id
      and b.location_id is not distinct from v_to_location_id
    for update;

    if found then
      v_dest_qty := coalesce(v_dest_balance.quantity_on_hand, 0);
      v_dest_total := coalesce(v_dest_balance.total_cost, v_dest_qty * coalesce(v_dest_balance.average_unit_cost, 0));
      v_dest_new_qty := round(v_dest_qty + v_quantity, 3);
      v_dest_new_total := round(v_dest_total + v_total_cost, 4);
      v_dest_new_avg := case
        when v_dest_new_qty <> 0 then round(v_dest_new_total / v_dest_new_qty, 4)
        else v_unit_cost
      end;

      update logistica.stock_balances
         set quantity_on_hand = v_dest_new_qty,
             average_unit_cost = v_dest_new_avg,
             total_cost = v_dest_new_total,
             last_movement_at = now(),
             updated_at = now()
       where id = v_dest_balance.id;
    else
      insert into logistica.stock_balances (
        company_id,
        item_id,
        lot_id,
        warehouse_id,
        location_id,
        quantity_on_hand,
        quantity_reserved,
        average_unit_cost,
        total_cost,
        last_movement_at
      ) values (
        v_company_id,
        v_item.id,
        v_lot_id,
        v_to_warehouse_id,
        v_to_location_id,
        round(v_quantity, 3),
        0,
        v_unit_cost,
        v_total_cost,
        now()
      );
    end if;

    if v_serial_id is not null then
      update logistica.item_serials
         set current_warehouse_id = v_to_warehouse_id,
             current_location_id = v_to_location_id,
             updated_at = now(),
             updated_by = v_user_id
       where id = v_serial_id;
    end if;
  end loop;

  return jsonb_build_object(
    'success', true,
    'transfer_reference', v_reference_number,
    'movements_created', v_movements_created,
    'items_processed', v_items_processed
  );
end;
$$;

grant execute on function logistica.create_stock_transfer(jsonb) to authenticated;
