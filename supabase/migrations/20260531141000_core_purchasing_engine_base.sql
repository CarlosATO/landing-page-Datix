-- 20260531141000_core_purchasing_engine_base.sql
-- Fase 1: Motor Central de Órdenes de Compra (Core Purchasing Engine) en el esquema logistica.

-- 1. TABLA DE SECUENCIAS Y FUNCIÓN DE FOLIOS SEGURA
create table if not exists logistica.sequences (
  company_id uuid not null references public.companies(id) on delete cascade,
  sequence_key text not null,
  current_value integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (company_id, sequence_key)
);

alter table logistica.sequences enable row level security;

create policy sequences_select_policy on logistica.sequences
  for select using (public.has_company_access(company_id));

create or replace function logistica.get_next_sequence_formatted(
  p_company_id uuid,
  p_sequence_key text,
  p_prefix text
)
returns text
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_next_val integer;
begin
  insert into logistica.sequences (company_id, sequence_key, current_value)
  values (p_company_id, p_sequence_key, 1)
  on conflict (company_id, sequence_key)
  do update set 
    current_value = logistica.sequences.current_value + 1,
    updated_at = now()
  returning current_value into v_next_val;
  
  return p_prefix || lpad(v_next_val::text, 6, '0');
end;
$$;

grant execute on function logistica.get_next_sequence_formatted(uuid, text, text) to authenticated;


-- 2. TABLA DE ÓRDENES DE COMPRA (HEADERS)
create table if not exists logistica.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id),
  cost_center_id uuid not null references public.cost_centers(id),
  warehouse_id uuid references logistica.warehouses(id) on delete set null,
  po_number text not null,
  document_date date not null default current_date,
  expected_delivery_date date,
  required_date date not null,
  priority text not null default 'MEDIA',
  status text not null default 'PENDING',
  subtotal_cost numeric(14,4) not null default 0,
  tax_amount numeric(14,4) not null default 0,
  total_cost numeric(14,4) not null default 0,
  notes text,
  origin_module text not null,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  cancelled_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  cancelled_at timestamptz,
  
  constraint po_status_check check (status in ('PENDING', 'PARCIAL', 'INGRESADA', 'ANULADA')),
  constraint po_priority_check check (priority in ('BAJA', 'MEDIA', 'ALTA')),
  constraint po_origin_module_check check (origin_module in ('LOGISTICA', 'ADQUISICIONES')),
  constraint po_number_company_unique unique (company_id, po_number)
);

create index if not exists po_company_supplier_idx on logistica.purchase_orders(company_id, supplier_id);
create index if not exists po_company_status_idx on logistica.purchase_orders(company_id, status);

alter table logistica.purchase_orders enable row level security;

create policy po_select_policy on logistica.purchase_orders
  for select to authenticated
  using (public.has_company_access(company_id) and public.has_module_access(company_id, 'logistica'));

create policy po_insert_policy on logistica.purchase_orders for insert with check (false);
create policy po_update_policy on logistica.purchase_orders for update using (false) with check (false);
create policy po_delete_policy on logistica.purchase_orders for delete using (false);

grant select on logistica.purchase_orders to authenticated;


-- 3. TABLA DE LÍNEAS DE ÓRDENES DE COMPRA
create table if not exists logistica.purchase_order_lines (
  id uuid primary key default gen_random_uuid(),
  purchase_order_id uuid not null references logistica.purchase_orders(id) on delete cascade,
  line_number integer not null,
  item_id uuid not null references logistica.items(id),
  ordered_quantity numeric(14,3) not null,
  received_quantity numeric(14,3) not null default 0,
  unit_cost numeric(14,4) not null default 0,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  
  constraint po_lines_qty_check check (ordered_quantity > 0),
  constraint po_lines_received_check check (received_quantity >= 0 and received_quantity <= ordered_quantity)
);

create index if not exists po_lines_order_idx on logistica.purchase_order_lines(purchase_order_id);

alter table logistica.purchase_order_lines enable row level security;

create policy po_lines_select_policy on logistica.purchase_order_lines
  for select to authenticated
  using (
    exists (
      select 1 from logistica.purchase_orders po
      where po.id = purchase_order_id
        and public.has_company_access(po.company_id)
        and public.has_module_access(po.company_id, 'logistica')
    )
  );

create policy po_lines_insert_policy on logistica.purchase_order_lines for insert with check (false);
create policy po_lines_update_policy on logistica.purchase_order_lines for update using (false) with check (false);
create policy po_lines_delete_policy on logistica.purchase_order_lines for delete using (false);

grant select on logistica.purchase_order_lines to authenticated;


-- 4. RPCS OPERATIVOS CENTRALIZADOS

-- A. CREAR ORDEN DE COMPRA
create or replace function logistica.create_purchase_order(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_supplier_id uuid;
  v_cost_center_id uuid;
  v_warehouse_id uuid;
  v_expected_delivery_date date;
  v_required_date date;
  v_priority text;
  v_notes text;
  v_origin_module text;
  v_items jsonb;
  v_item_element jsonb;
  
  v_adq_active boolean;
  v_po_id uuid;
  v_po_number text;
  
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
  v_supplier_id := nullif(btrim(coalesce(p_payload->>'supplier_id', '')), '')::uuid;
  v_cost_center_id := nullif(btrim(coalesce(p_payload->>'cost_center_id', '')), '')::uuid;
  v_warehouse_id := nullif(btrim(coalesce(p_payload->>'warehouse_id', '')), '')::uuid;
  v_expected_delivery_date := nullif(btrim(coalesce(p_payload->>'expected_delivery_date', '')), '')::date;
  v_required_date := nullif(btrim(coalesce(p_payload->>'required_date', '')), '')::date;
  v_priority := coalesce(nullif(btrim(coalesce(p_payload->>'priority', '')), ''), 'MEDIA');
  v_notes := nullif(btrim(coalesce(p_payload->>'notes', '')), '');
  v_items := coalesce(p_payload->'items', '[]'::jsonb);

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
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

  -- 1. Validar acceso a empresa y módulo
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

  v_origin_module := 'LOGISTICA';

  -- 3. Validar maestros
  perform 1 from public.suppliers where id = v_supplier_id and company_id = v_company_id and coalesce(is_active, true) = true;
  if not found then
    raise exception 'Proveedor no válido o inactivo';
  end if;

  perform 1 from public.cost_centers where id = v_cost_center_id and company_id = v_company_id and coalesce(is_active, true) = true;
  if not found then
    raise exception 'Centro de costo no válido o inactivo';
  end if;

  if v_warehouse_id is not null then
    perform 1 from logistica.warehouses where id = v_warehouse_id and company_id = v_company_id and coalesce(is_active, true) = true;
    if not found then
      raise exception 'Bodega destino sugerida no válida o inactiva';
    end if;
  end if;

  -- 4. Iterar y validar ítems + calcular totales
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

  v_tax := round(v_subtotal * 0.19, 4); -- Cálculo estándar de IVA (19%)
  v_total := v_subtotal + v_tax;

  -- 5. Obtener folio seguro (Thread-Safe)
  v_po_number := logistica.get_next_sequence_formatted(v_company_id, 'purchase_order', 'OC-');

  -- 6. Insertar encabezado de orden de compra
  insert into logistica.purchase_orders (
    company_id, supplier_id, cost_center_id, warehouse_id, po_number,
    document_date, expected_delivery_date, required_date, priority, status,
    subtotal_cost, tax_amount, total_cost, notes, origin_module,
    created_by, updated_by
  ) values (
    v_company_id, v_supplier_id, v_cost_center_id, v_warehouse_id, v_po_number,
    current_date, v_expected_delivery_date, v_required_date, v_priority, 'PENDING',
    v_subtotal, v_tax, v_total, v_notes, v_origin_module,
    v_user_id, v_user_id
  ) returning id into v_po_id;

  -- 7. Insertar líneas
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

  return jsonb_build_object(
    'success', true,
    'purchase_order_id', v_po_id,
    'po_number', v_po_number,
    'total_cost', v_total
  );
end;
$$;


-- B. MODIFICAR ORDEN DE COMPRA
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

  -- 3. Obtener estado actual y bloquear si ya tiene recepciones
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


-- C. ANULAR ORDEN DE COMPRA
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

  if v_current_status = 'INGRESADA' then
    raise exception 'No se puede anular una orden de compra completamente ingresada';
  end if;
  if v_current_status = 'ANULADA' then
    raise exception 'La orden de compra ya se encuentra anulada';
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


-- D. LISTAR ÓRDENES DE COMPRA
create or replace function logistica.list_purchase_orders(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_company_id uuid;
  v_search text;
  v_status text;
  v_orders jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_search := nullif(btrim(coalesce(p_payload->>'search', '')), '');
  v_status := nullif(btrim(coalesce(p_payload->>'status', '')), '');

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if not public.has_company_access(v_company_id) then
    raise exception 'forbidden';
  end if;
  if not public.has_module_access(v_company_id, 'logistica') then
    raise exception 'module access required';
  end if;

  select coalesce(jsonb_agg(to_jsonb(o) order by o.created_at desc), '[]'::jsonb)
    into v_orders
  from (
    select
      po.id as purchase_order_id,
      po.po_number,
      po.document_date,
      po.required_date,
      po.priority,
      po.status,
      po.total_cost,
      po.origin_module,
      coalesce(s.business_name, s.name) as supplier_name,
      coalesce(cc.code || ' - ' || cc.name, cc.name) as cost_center,
      coalesce(w.code || ' - ' || w.name, w.name) as warehouse,
      (
        select count(*)::integer
        from logistica.purchase_order_lines pol
        where pol.purchase_order_id = po.id
      ) as line_count,
      (
        select coalesce(sum(pol.received_quantity) / nullif(sum(pol.ordered_quantity), 0) * 100, 0)::numeric(5,2)
        from logistica.purchase_order_lines pol
        where pol.purchase_order_id = po.id
      ) as reception_progress
    from logistica.purchase_orders po
    left join public.suppliers s on s.id = po.supplier_id
    left join public.cost_centers cc on cc.id = po.cost_center_id
    left join logistica.warehouses w on w.id = po.warehouse_id
    where po.company_id = v_company_id
      and (v_status is null or lower(po.status) = lower(v_status))
      and (
        v_search is null 
        or po.po_number ilike ('%' || v_search || '%') 
        or coalesce(s.business_name, s.name) ilike ('%' || v_search || '%')
      )
  ) o;

  return jsonb_build_object('success', true, 'purchase_orders', v_orders);
end;
$$;


-- E. OBTENER DETALLE DE ORDEN DE COMPRA (CON HISTORIAL)
create or replace function logistica.get_purchase_order_detail(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_company_id uuid;
  v_po_id uuid;
  v_header jsonb := null;
  v_lines jsonb := '[]'::jsonb;
  v_receipts jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
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

  if not public.has_company_access(v_company_id) then
    raise exception 'forbidden';
  end if;
  if not public.has_module_access(v_company_id, 'logistica') then
    raise exception 'module access required';
  end if;

  -- 1. Obtener cabecera
  select to_jsonb(h)
    into v_header
  from (
    select
      po.*,
      coalesce(s.business_name, s.name) as supplier_name,
      s.tax_id as supplier_tax_id,
      coalesce(cc.code || ' - ' || cc.name, cc.name) as cost_center,
      coalesce(w.code || ' - ' || w.name, w.name) as warehouse,
      coalesce(cu.full_name, cu.email, po.created_by::text) as created_by_name
    from logistica.purchase_orders po
    left join public.suppliers s on s.id = po.supplier_id
    left join public.cost_centers cc on cc.id = po.cost_center_id
    left join logistica.warehouses w on w.id = po.warehouse_id
    left join public.company_users cu on cu.user_id = po.created_by and cu.company_id = po.company_id
    where po.id = v_po_id and po.company_id = v_company_id
  ) h;

  if v_header is null then
    raise exception 'Orden de compra no encontrada';
  end if;

  -- 2. Obtener líneas (calculando pending_quantity y total_cost en el vuelo)
  select coalesce(jsonb_agg(to_jsonb(l) order by l.line_number asc), '[]'::jsonb)
    into v_lines
  from (
    select
      pol.id,
      pol.purchase_order_id,
      pol.line_number,
      pol.item_id,
      pol.ordered_quantity,
      pol.received_quantity,
      (pol.ordered_quantity - pol.received_quantity)::numeric(14,3) as pending_quantity,
      pol.unit_cost,
      (pol.ordered_quantity * pol.unit_cost)::numeric(14,4) as total_cost,
      pol.notes,
      i.sku,
      i.name as item_name
    from logistica.purchase_order_lines pol
    join logistica.items i on i.id = pol.item_id
    where pol.purchase_order_id = v_po_id
  ) l;

  -- 3. Obtener Historial de Recepciones Físicas Asociadas
  select coalesce(jsonb_agg(to_jsonb(r) order by r.receipt_date desc), '[]'::jsonb)
    into v_receipts
  from (
    select
      rh.id as receipt_id,
      rh.receipt_reference,
      rh.receipt_date,
      coalesce(cu.full_name, cu.email, rh.created_by::text) as received_by_name,
      (
        select jsonb_agg(jsonb_build_object(
          'item_name', i.name,
          'sku', i.sku,
          'received_quantity', rl.received_quantity,
          'lot_code', rl.lot_code,
          'serial_number', rl.serial_number
        ))
        from logistica.receipt_lines rl
        join logistica.items i on i.id = rl.item_id
        where rl.receipt_id = rh.id
      ) as items_received
    from logistica.receipt_headers rh
    left join public.company_users cu on cu.user_id = rh.created_by and cu.company_id = rh.company_id
    where rh.origin_document_id = v_po_id
      and rh.origin_type = 'purchase_order'
      and rh.company_id = v_company_id
  ) r;

  return jsonb_build_object(
    'success', true,
    'purchase_order', v_header,
    'lines', v_lines,
    'associated_receipts', v_receipts
  );
end;
$$;


-- E. GRANTS DE SEGURIDAD PARA RPCS
grant execute on function logistica.create_purchase_order(jsonb) to authenticated;
grant execute on function logistica.update_purchase_order(jsonb) to authenticated;
grant execute on function logistica.cancel_purchase_order(jsonb) to authenticated;
grant execute on function logistica.list_purchase_orders(jsonb) to authenticated;
grant execute on function logistica.get_purchase_order_detail(jsonb) to authenticated;
