create or replace function logistica.create_stock_issue(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_warehouse_id uuid;
  v_location_id uuid;
  v_issue_type text;
  v_target_module text;
  v_target_entity_type text;
  v_target_entity_id uuid;
  v_reference_number text;
  v_notes text;
  v_payload_item jsonb;
  v_item_id uuid;
  v_quantity numeric(14,3);
  v_lot_id uuid;
  v_serial_id uuid;
  v_item_notes text;
  v_item logistica.items%rowtype;
  v_balance logistica.stock_balances%rowtype;
  v_serial logistica.item_serials%rowtype;
  v_origin_qty numeric(14,3);
  v_origin_total numeric(14,4);
  v_origin_avg numeric(14,4);
  v_origin_new_qty numeric(14,3);
  v_origin_new_total numeric(14,4);
  v_target_worker public.workers%rowtype;
  v_target_contractor public.contractors%rowtype;
  v_target_project public.projects%rowtype;
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
  v_warehouse_id := nullif(btrim(coalesce(p_payload->>'warehouse_id', '')), '')::uuid;
  v_location_id := nullif(btrim(coalesce(p_payload->>'location_id', '')), '')::uuid;
  v_issue_type := upper(btrim(coalesce(p_payload->>'issue_type', '')));
  v_target_module := nullif(lower(btrim(coalesce(p_payload->>'target_module', ''))), '');
  v_target_entity_type := nullif(lower(btrim(coalesce(p_payload->>'target_entity_type', ''))), '');
  v_target_entity_id := nullif(btrim(coalesce(p_payload->>'target_entity_id', '')), '')::uuid;
  v_reference_number := btrim(coalesce(p_payload->>'reference_number', ''));
  v_notes := nullif(btrim(coalesce(p_payload->>'notes', '')), '');

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if v_warehouse_id is null then
    raise exception 'warehouse_id es obligatorio';
  end if;

  if v_issue_type not in ('ISSUE', 'ASSIGNMENT', 'CONSUMPTION') then
    raise exception 'issue_type inválido';
  end if;

  if v_target_entity_type is null then
    raise exception 'target_entity_type es obligatorio';
  end if;

  if v_reference_number = '' then
    raise exception 'reference_number es obligatorio';
  end if;

  if p_payload->'items' is null or jsonb_typeof(p_payload->'items') <> 'array' then
    raise exception 'items es obligatorio';
  end if;

  if v_target_module is not null and v_target_module not in ('public', 'construccion', 'logistica') then
    raise exception 'target_module inválido';
  end if;

  if v_target_entity_type not in ('worker', 'contractor', 'project', 'consumption', 'other') then
    raise exception 'target_entity_type inválido';
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

  perform 1
  from logistica.warehouses w
  where w.id = v_warehouse_id
    and w.company_id = v_company_id
    and coalesce(w.is_active, true) = true;

  if not found then
    raise exception 'warehouse invalid';
  end if;

  if v_location_id is not null then
    perform 1
    from logistica.locations l
    where l.id = v_location_id
      and l.company_id = v_company_id
      and l.warehouse_id = v_warehouse_id
      and coalesce(l.is_active, true) = true;

    if not found then
      raise exception 'location invalid';
    end if;
  end if;

  if v_issue_type = 'ASSIGNMENT' and v_target_entity_type not in ('worker', 'contractor', 'project') then
    raise exception 'ASSIGNMENT requiere worker, contractor o project';
  end if;

  if v_issue_type = 'CONSUMPTION' and v_target_entity_type not in ('project', 'consumption', 'other') then
    raise exception 'CONSUMPTION requiere project, consumption u other';
  end if;

  if v_target_entity_type = 'worker' then
    if v_target_entity_id is null then
      raise exception 'target_entity_id es obligatorio para worker';
    end if;

    select *
      into v_target_worker
    from public.workers w
    where w.id = v_target_entity_id
      and w.company_id = v_company_id
      and coalesce(w.is_active, true) = true;

    if not found then
      raise exception 'worker invalid';
    end if;
  elsif v_target_entity_type = 'contractor' then
    if v_target_entity_id is null then
      raise exception 'target_entity_id es obligatorio para contractor';
    end if;

    select *
      into v_target_contractor
    from public.contractors c
    where c.id = v_target_entity_id
      and c.company_id = v_company_id
      and coalesce(c.is_active, true) = true;

    if not found then
      raise exception 'contractor invalid';
    end if;
  elsif v_target_entity_type = 'project' then
    if v_target_entity_id is null then
      raise exception 'target_entity_id es obligatorio para project';
    end if;

    select *
      into v_target_project
    from public.projects p
    where p.id = v_target_entity_id
      and p.company_id = v_company_id
      and coalesce(p.is_active, true) = true;

    if not found then
      raise exception 'project invalid';
    end if;
  elsif v_target_entity_type = 'consumption' and v_target_entity_id is not null then
    raise exception 'target_entity_id debe ser null para consumption';
  end if;

  if v_target_module is null and v_target_entity_type in ('worker', 'contractor', 'project', 'consumption') then
    v_target_module := 'public';
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

      if v_serial.current_warehouse_id is distinct from v_warehouse_id
         or v_serial.current_location_id is distinct from v_location_id then
        raise exception 'serial not in origin';
      end if;
    end if;

    select *
      into v_balance
    from logistica.stock_balances b
    where b.company_id = v_company_id
      and b.item_id = v_item.id
      and b.lot_id is not distinct from v_lot_id
      and b.warehouse_id = v_warehouse_id
      and b.location_id is not distinct from v_location_id
    for update;

    if not found then
      raise exception 'origin stock not found';
    end if;

    v_origin_qty := coalesce(v_balance.quantity_on_hand, 0);
    v_origin_total := coalesce(v_balance.total_cost, v_origin_qty * coalesce(v_balance.average_unit_cost, 0));
    v_origin_avg := coalesce(v_balance.average_unit_cost, case when v_origin_qty <> 0 then round(v_origin_total / v_origin_qty, 4) else 0 end);

    if (v_origin_qty - coalesce(v_balance.quantity_reserved, 0)) < v_quantity then
      raise exception 'insufficient stock';
    end if;

    v_total_cost := round(v_quantity * v_origin_avg, 4);

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
      v_issue_type,
      'STOCK_ISSUE',
      v_quantity,
      v_origin_avg,
      v_total_cost,
      v_warehouse_id,
      v_location_id,
      null,
      null,
      'logistica',
      'STOCK_ISSUE',
      null,
      v_target_module,
      upper(v_target_entity_type),
      v_target_entity_id,
      v_reference_number,
      coalesce(v_item_notes, v_notes),
      jsonb_build_object(
        'stock_issue', true,
        'issue_type', v_issue_type,
        'target_module', v_target_module,
        'target_entity_type', v_target_entity_type,
        'target_entity_id', v_target_entity_id,
        'warehouse_id', v_warehouse_id,
        'location_id', v_location_id
      ),
      v_user_id
    );

    v_origin_new_qty := round(v_origin_qty - v_quantity, 3);
    v_origin_new_total := round(v_origin_total - v_total_cost, 4);

    if v_origin_new_qty < 0 then
      raise exception 'negative stock not allowed';
    end if;

    update logistica.stock_balances
       set quantity_on_hand = v_origin_new_qty,
           average_unit_cost = v_origin_avg,
           total_cost = case when v_origin_new_qty = 0 then 0 else v_origin_new_total end,
           last_movement_at = now(),
           updated_at = now()
     where id = v_balance.id;

    if v_serial_id is not null then
      update logistica.item_serials
         set status = case when v_issue_type = 'ASSIGNMENT' then 'assigned' else 'in_use' end,
             current_custodian_type = case when v_target_entity_type in ('worker', 'contractor') then v_target_entity_type else null end,
             current_custodian_id = case when v_target_entity_type in ('worker', 'contractor') then v_target_entity_id else null end,
             current_project_id = case when v_target_entity_type = 'project' then v_target_entity_id else null end,
             current_warehouse_id = null,
             current_location_id = null,
             updated_at = now(),
             updated_by = v_user_id
       where id = v_serial.id;
    end if;

    v_movements_created := v_movements_created + 1;
  end loop;

  return jsonb_build_object(
    'success', true,
    'issue_reference', v_reference_number,
    'movements_created', v_movements_created,
    'items_processed', v_items_processed
  );
end;
$$;

grant execute on function logistica.create_stock_issue(jsonb) to authenticated;
