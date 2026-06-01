-- 20260531150000_harden_purchase_orders.sql
-- Incremental hardening of logistica.cancel_purchase_order and logistica.update_purchase_order

-- A. RE-DEFINE CANCEL PURCHASE ORDER
create or replace function logistica.cancel_purchase_order(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_po_id uuid;
  v_adq_active boolean;
  v_current_status text;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_po_id := nullif(btrim(coalesce(p_payload->>'purchase_order_id', '')), '')::uuid;

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;
  if v_po_id is null then
    raise exception 'purchase_order_id es obligatorio';
  end if;

  -- 1. Validar accesos
  if not public.has_company_access(v_company_id) then
    raise exception 'forbidden';
  end if;
  if not public.has_module_access(v_company_id, 'logistica') then
    raise exception 'module access required';
  end if;

  -- 2. Validar si Adquisiciones está contratado comercialmente
  select exists (
    select 1 from public.company_modules
    where company_id = v_company_id
      and module_key = 'adquisiciones'
      and status in ('active', 'trial')
  ) into v_adq_active;

  if v_adq_active then
    raise exception 'Las órdenes de compra están administradas por el módulo de Adquisiciones comercial.';
  end if;

  -- 3. Obtener estado y bloquear fila
  select status into v_current_status
  from logistica.purchase_orders
  where id = v_po_id and company_id = v_company_id
  for update;

  if not found then
    raise exception 'Orden de compra no encontrada';
  end if;

  -- Validaciones estrictas de estado
  if v_current_status = 'INGRESADA' then
    raise exception 'No se puede anular una orden de compra completamente ingresada';
  end if;
  if v_current_status = 'PARCIAL' then
    raise exception 'No se puede anular una orden de compra parcial';
  end if;
  if v_current_status = 'ANULADA' then
    raise exception 'La orden de compra ya se encuentra anulada';
  end if;
  if v_current_status <> 'PENDING' then
    raise exception 'Solo se pueden anular órdenes de compra en estado PENDIENTE';
  end if;

  -- Validar si existen recepciones asociadas (origin_type = 'purchase_order' y origin_document_id = po_id)
  if exists (
    select 1 from logistica.receipt_headers
    where origin_type = 'purchase_order'
      and origin_document_id = v_po_id
  ) then
    raise exception 'No se puede anular una orden de compra con recepciones asociadas';
  end if;

  -- 4. Actualizar estado a ANULADA
  update logistica.purchase_orders
  set status = 'ANULADA',
      cancelled_by = v_user_id,
      cancelled_at = now(),
      updated_by = v_user_id,
      updated_at = now()
  where id = v_po_id;

  return jsonb_build_object('success', true);
end;
$$;

grant execute on function logistica.cancel_purchase_order(jsonb) to authenticated;


-- B. RE-DEFINE UPDATE PURCHASE ORDER
create or replace function logistica.update_purchase_order(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_po_id uuid;
  v_supplier_id uuid;
  v_cost_center_id uuid;
  v_warehouse_id uuid;
  v_expected_delivery_date date;
  v_required_date date;
  v_priority text;
  v_notes text;
  v_items jsonb;
  v_item_element jsonb;
  
  v_adq_active boolean;
  v_current_status text;
  
  v_subtotal numeric(14,4) := 0;
  v_tax numeric(14,4) := 0;
  v_total numeric(14,4) := 0;
  
  v_line_number integer := 0;
  v_line_item_id uuid;
  v_line_qty numeric(14,3);
  v_line_cost numeric(14,4);
  v_line_notes text;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_po_id := nullif(btrim(coalesce(p_payload->>'purchase_order_id', '')), '')::uuid;
  v_supplier_id := nullif(btrim(coalesce(p_payload->>'supplier_id', '')), '')::uuid;
  v_cost_center_id := nullif(btrim(coalesce(p_payload->>'cost_center_id', '')), '')::uuid;
  v_warehouse_id := nullif(btrim(coalesce(p_payload->>'warehouse_id', '')), '')::uuid;
  v_expected_delivery_date := nullif(btrim(coalesce(p_payload->>'expected_delivery_date', '')), '')::date;
  v_required_date := nullif(btrim(coalesce(p_payload->>'required_date', '')), '')::date;
  v_priority := nullif(btrim(coalesce(p_payload->>'priority', '')), '');
  v_notes := nullif(btrim(coalesce(p_payload->>'notes', '')), '');
  v_items := coalesce(p_payload->'items', '[]'::jsonb);

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;
  if v_po_id is null then
    raise exception 'purchase_order_id es obligatorio';
  end if;
  if v_supplier_id is null then
    raise exception 'supplier_id es obligatorio';
  end if;
  if v_cost_center_id is null then
    raise exception 'cost_center_id es obligatorio';
  end if;
  if v_required_date is null then
    raise exception 'required_date es obligatorio';
  end if;
  if jsonb_array_length(v_items) = 0 then
    raise exception 'La orden de compra debe contener al menos un material';
  end if;

  -- 1. Validar accesos
  if not public.has_company_access(v_company_id) then
    raise exception 'forbidden';
  end if;
  if not public.has_module_access(v_company_id, 'logistica') then
    raise exception 'module access required';
  end if;

  -- 2. Validar si Adquisiciones está contratado comercialmente
  select exists (
    select 1 from public.company_modules
    where company_id = v_company_id
      and module_key = 'adquisiciones'
      and status in ('active', 'trial')
  ) into v_adq_active;

  if v_adq_active then
    raise exception 'Las órdenes de compra están administradas por el módulo de Adquisiciones comercial.';
  end if;

  -- 3. Obtener estado actual y bloquear
  select status into v_current_status
  from logistica.purchase_orders
  where id = v_po_id and company_id = v_company_id
  for update;

  if not found then
    raise exception 'Orden de compra no encontrada';
  end if;

  if v_current_status <> 'PENDING' then
    raise exception 'Solo se pueden editar órdenes de compra en estado PENDIENTE';
  end if;

  -- Validar si existen recepciones asociadas (origin_type = 'purchase_order' y origin_document_id = po_id)
  if exists (
    select 1 from logistica.receipt_headers
    where origin_type = 'purchase_order'
      and origin_document_id = v_po_id
  ) then
    raise exception 'No se puede editar una orden de compra con recepciones asociadas';
  end if;

  -- 4. Validar maestros
  perform 1 from public.suppliers where id = v_supplier_id and company_id = v_company_id and coalesce(is_active, true) = true;
  if not found then
    raise exception 'Proveedor no válido';
  end if;

  perform 1 from public.cost_centers where id = v_cost_center_id and company_id = v_company_id and coalesce(is_active, true) = true;
  if not found then
    raise exception 'Centro de costo no válido';
  end if;

  if v_warehouse_id is not null then
    perform 1 from logistica.warehouses where id = v_warehouse_id and company_id = v_company_id and coalesce(is_active, true) = true;
    if not found then
      raise exception 'Bodega destino no válida';
    end if;
  end if;

  -- 5. Validar ítems
  for v_item_element in select * from jsonb_array_elements(v_items)
  loop
    v_line_item_id := nullif(btrim(coalesce(v_item_element->>'item_id', '')), '')::uuid;
    v_line_qty := (v_item_element->>'ordered_quantity')::numeric;
    v_line_cost := (v_item_element->>'unit_cost')::numeric;

    if v_line_item_id is null then
      raise exception 'item_id es obligatorio en todas las líneas';
    end if;
    if v_line_qty is null or v_line_qty <= 0 then
      raise exception 'Cantidad requerida debe ser mayor a cero';
    end if;
    if v_line_cost is null or v_line_cost < 0 then
      raise exception 'Costo unitario no puede ser negativo';
    end if;

    perform 1 from logistica.items where id = v_line_item_id and company_id = v_company_id and coalesce(is_active, true) = true;
    if not found then
      raise exception 'Material no existe en el catálogo o está inactivo';
    end if;

    v_subtotal := round(v_subtotal + (v_line_qty * v_line_cost), 4);
  end loop;

  v_tax := round(v_subtotal * 0.19, 4);
  v_total := v_subtotal + v_tax;

  -- 6. Actualizar cabecera
  update logistica.purchase_orders
  set supplier_id = v_supplier_id,
      cost_center_id = v_cost_center_id,
      warehouse_id = v_warehouse_id,
      expected_delivery_date = v_expected_delivery_date,
      required_date = v_required_date,
      priority = coalesce(v_priority, priority),
      subtotal_cost = v_subtotal,
      tax_amount = v_tax,
      total_cost = v_total,
      notes = v_notes,
      updated_by = v_user_id,
      updated_at = now()
  where id = v_po_id;

  -- 7. Reemplazar líneas
  delete from logistica.purchase_order_lines where purchase_order_id = v_po_id;

  for v_item_element in select * from jsonb_array_elements(v_items)
  loop
    v_line_number := v_line_number + 1;
    v_line_item_id := nullif(btrim(coalesce(v_item_element->>'item_id', '')), '')::uuid;
    v_line_qty := (v_item_element->>'ordered_quantity')::numeric;
    v_line_cost := (v_item_element->>'unit_cost')::numeric;
    v_line_notes := nullif(btrim(coalesce(v_item_element->>'notes', '')), '');

    insert into logistica.purchase_order_lines (
      purchase_order_id, line_number, item_id, ordered_quantity, received_quantity, unit_cost, notes
    ) values (
      v_po_id, v_line_number, v_line_item_id, v_line_qty, 0, v_line_cost, v_line_notes
    );
  end loop;

  return jsonb_build_object('success', true);
end;
$$;

grant execute on function logistica.update_purchase_order(jsonb) to authenticated;
