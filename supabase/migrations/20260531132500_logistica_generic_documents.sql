-- 20260531132500_logistica_generic_documents.sql
-- Migración para soporte de documentos logísticos genéricos con seguridad estricta y multitenant.

-- 1. CREACIÓN DE LA TABLA DE METADATA DE DOCUMENTOS
create table if not exists logistica.documents (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  entity_type text not null,
  entity_id uuid not null,
  storage_bucket text not null default 'logistica.documents',
  file_name text not null,
  file_path text not null,
  mime_type text,
  file_size_bytes bigint,
  document_type text,
  uploaded_by uuid default auth.uid() references auth.users(id) on delete set null,
  uploaded_at timestamptz not null default now(),
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  constraint documents_file_path_unique unique (company_id, file_path),
  constraint documents_entity_type_check check (entity_type in ('RECEIPT', 'TRANSFER', 'TOOL', 'MOVEMENT', 'DELIVERY'))
);

create index if not exists documents_company_entity_idx on logistica.documents(company_id, entity_type, entity_id);
create index if not exists documents_company_active_idx on logistica.documents(company_id, is_active);

-- Habilitar RLS en logistica.documents
alter table logistica.documents enable row level security;

drop policy if exists documents_select_company on logistica.documents;
create policy documents_select_company
on logistica.documents
for select
using (public.has_company_access(company_id) and public.has_module_access(company_id, 'logistica'));

drop policy if exists documents_insert_company on logistica.documents;
create policy documents_insert_company on logistica.documents for insert with check (false);

drop policy if exists documents_update_company on logistica.documents;
create policy documents_update_company on logistica.documents for update using (false) with check (false);

drop policy if exists documents_delete_company on logistica.documents;
create policy documents_delete_company on logistica.documents for delete using (false);

grant select on logistica.documents to authenticated;

-- 2. ASEGURAR QUE EL BUCKET SEA PRIVADO Y EXISTE
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('logistica.documents', 'logistica.documents', false, null, null)
on conflict (id) do update set public = false;

-- Limpiar cualquier política antigua o insegura sobre logistica.documents en storage.objects
drop policy if exists "Select logistica.documents" on storage.objects;
drop policy if exists "Insert logistica.documents" on storage.objects;
drop policy if exists "Update logistica.documents" on storage.objects;
drop policy if exists "Delete logistica.documents" on storage.objects;

drop policy if exists "logistica.documents select" on storage.objects;
drop policy if exists "logistica.documents insert" on storage.objects;
drop policy if exists "logistica.documents update" on storage.objects;
drop policy if exists "logistica.documents delete" on storage.objects;

drop policy if exists "logistica_documents_select_strict" on storage.objects;
drop policy if exists "logistica_documents_insert_strict" on storage.objects;
drop policy if exists "logistica_documents_delete_strict" on storage.objects;

-- Crear políticas estrictas y seguras en storage.objects
create policy "logistica_documents_select_strict"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'logistica.documents'
  and (storage.foldername(name))[1] ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  and (
    select (
      public.has_company_access(((storage.foldername(name))[1])::uuid)
      and public.has_module_access(((storage.foldername(name))[1])::uuid, 'logistica')
    )
  )
);

create policy "logistica_documents_insert_strict"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'logistica.documents'
  and (storage.foldername(name))[1] ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  and (
    select (
      public.has_company_access(((storage.foldername(name))[1])::uuid)
      and public.has_module_access(((storage.foldername(name))[1])::uuid, 'logistica')
    )
  )
);

create policy "logistica_documents_delete_strict"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'logistica.documents'
  and (storage.foldername(name))[1] ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  and (
    select (
      public.has_company_access(((storage.foldername(name))[1])::uuid)
      and public.has_module_access(((storage.foldername(name))[1])::uuid, 'logistica')
    )
  )
);


-- 3. REDEFINICIÓN DE create_manual_receipt PARA RETORNAR receipt_id
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
    'receipt_id', v_receipt_id,
    'receipt_reference', v_reference_number,
    'movements_created', v_movements_created,
    'items_processed', v_items_processed
  );
end;
$$;

grant execute on function logistica.create_manual_receipt(jsonb) to authenticated;


-- 4. NUEVOS RPCS Y SUS WRAPPERS PÚBLICOS

-- A. REGISTRO DE DOCUMENTOS
create or replace function logistica.register_document(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_entity_type text;
  v_entity_id uuid;
  v_file_name text;
  v_file_path text;
  v_mime_type text;
  v_file_size_bytes bigint;
  v_document_type text;
  v_metadata jsonb;
  v_document_id uuid;
  v_expected_path_prefix text;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_entity_type := upper(btrim(coalesce(p_payload->>'entity_type', '')));
  v_entity_id := nullif(btrim(coalesce(p_payload->>'entity_id', '')), '')::uuid;
  v_file_name := nullif(btrim(coalesce(p_payload->>'file_name', '')), '');
  v_file_path := nullif(btrim(coalesce(p_payload->>'file_path', '')), '');
  v_mime_type := nullif(btrim(coalesce(p_payload->>'mime_type', '')), '');
  v_file_size_bytes := (p_payload->>'file_size_bytes')::bigint;
  v_document_type := nullif(btrim(coalesce(p_payload->>'document_type', '')), '');
  v_metadata := coalesce(p_payload->'metadata', '{}'::jsonb);

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if v_entity_type is null or v_entity_type = '' then
    raise exception 'entity_type es obligatorio';
  end if;

  if v_entity_id is null then
    raise exception 'entity_id es obligatorio';
  end if;

  if v_file_name is null then
    raise exception 'file_name es obligatorio';
  end if;

  if v_file_path is null then
    raise exception 'file_path es obligatorio';
  end if;

  if v_entity_type not in ('RECEIPT', 'TRANSFER', 'TOOL', 'MOVEMENT', 'DELIVERY') then
    raise exception 'entity_type inválido';
  end if;

  -- 1. Validar acceso a la empresa y al módulo logistica
  if not public.has_company_access(v_company_id) then
    raise exception 'forbidden';
  end if;

  if not public.has_module_access(v_company_id, 'logistica') then
    raise exception 'module access required';
  end if;

  -- 2. Si entity_type = 'RECEIPT', validar que receipt_headers.id existe y pertenece a company_id
  if v_entity_type = 'RECEIPT' then
    perform 1
    from logistica.receipt_headers rh
    where rh.id = v_entity_id
      and rh.company_id = v_company_id;

    if not found then
      raise exception 'La recepción asociada no existe o no pertenece a la empresa especificada';
    end if;
  end if;

  -- 3. Validar que el file_path empiece con: company_id || '/' || entity_type || '/' || entity_id || '/'
  v_expected_path_prefix := v_company_id::text || '/' || v_entity_type || '/' || v_entity_id::text || '/';
  if not (v_file_path like v_expected_path_prefix || '%') then
    raise exception 'file_path inválido. Debe comenzar con company_id/entity_type/entity_id/';
  end if;

  -- 4. Insertar o actualizar la metadata (si ya existe, reactivarla y actualizar campos)
  insert into logistica.documents (
    company_id,
    entity_type,
    entity_id,
    file_name,
    file_path,
    mime_type,
    file_size_bytes,
    document_type,
    metadata,
    uploaded_by,
    is_active
  ) values (
    v_company_id,
    v_entity_type,
    v_entity_id,
    v_file_name,
    v_file_path,
    v_mime_type,
    v_file_size_bytes,
    v_document_type,
    v_metadata,
    v_user_id,
    true
  )
  on conflict (company_id, file_path)
  do update set
    file_name = excluded.file_name,
    mime_type = excluded.mime_type,
    file_size_bytes = excluded.file_size_bytes,
    document_type = excluded.document_type,
    metadata = excluded.metadata,
    uploaded_by = excluded.uploaded_by,
    is_active = true,
    uploaded_at = now()
  returning id into v_document_id;

  return jsonb_build_object(
    'success', true,
    'document_id', v_document_id
  );
end;
$$;


-- B. LISTADO DE DOCUMENTOS
create or replace function logistica.list_documents(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_entity_type text;
  v_entity_id uuid;
  v_documents jsonb;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_entity_type := upper(btrim(coalesce(p_payload->>'entity_type', '')));
  v_entity_id := nullif(btrim(coalesce(p_payload->>'entity_id', '')), '')::uuid;

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if v_entity_type is null or v_entity_type = '' then
    raise exception 'entity_type es obligatorio';
  end if;

  if v_entity_id is null then
    raise exception 'entity_id es obligatorio';
  end if;

  -- 1. Validar acceso a la empresa y al módulo logistica
  if not public.has_company_access(v_company_id) then
    raise exception 'forbidden';
  end if;

  if not public.has_module_access(v_company_id, 'logistica') then
    raise exception 'module access required';
  end if;

  -- 2. Obtener los documentos activos para la entidad y empresa
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', ld.id,
        'company_id', ld.company_id,
        'entity_type', ld.entity_type,
        'entity_id', ld.entity_id,
        'storage_bucket', ld.storage_bucket,
        'file_name', ld.file_name,
        'file_path', ld.file_path,
        'mime_type', ld.mime_type,
        'file_size_bytes', ld.file_size_bytes,
        'document_type', ld.document_type,
        'uploaded_by', ld.uploaded_by,
        'uploaded_at', ld.uploaded_at,
        'metadata', ld.metadata
      ) order by ld.uploaded_at desc
    ),
    '[]'::jsonb
  ) into v_documents
  from logistica.documents ld
  where ld.company_id = v_company_id
    and ld.entity_type = v_entity_type
    and ld.entity_id = v_entity_id
    and ld.is_active = true;

  return jsonb_build_object(
    'success', true,
    'documents', v_documents
  );
end;
$$;


-- C. DESACTIVACIÓN DE DOCUMENTOS
create or replace function logistica.deactivate_document(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_document_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_document_id := nullif(btrim(coalesce(p_payload->>'document_id', '')), '')::uuid;

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if v_document_id is null then
    raise exception 'document_id es obligatorio';
  end if;

  -- 1. Validar acceso a la empresa y al módulo logistica
  if not public.has_company_access(v_company_id) then
    raise exception 'forbidden';
  end if;

  if not public.has_module_access(v_company_id, 'logistica') then
    raise exception 'module access required';
  end if;

  -- 2. Desactivar documento si pertenece al company_id
  update logistica.documents
     set is_active = false
   where id = v_document_id
     and company_id = v_company_id;

  if not found then
    raise exception 'Documento no encontrado o no pertenece a la empresa especificada';
  end if;

  return jsonb_build_object(
    'success', true
  );
end;
$$;


-- D. WRAPPERS PÚBLICOS EN EL ESQUEMA public
create or replace function public.register_logistica_document(p_payload jsonb)
returns jsonb
language plpgsql
security definer
as $$
begin
  return logistica.register_document(p_payload);
end;
$$;

create or replace function public.list_logistica_documents(p_payload jsonb)
returns jsonb
language plpgsql
security definer
as $$
begin
  return logistica.list_documents(p_payload);
end;
$$;

create or replace function public.deactivate_logistica_document(p_payload jsonb)
returns jsonb
language plpgsql
security definer
as $$
begin
  return logistica.deactivate_document(p_payload);
end;
$$;

-- Otorgar permisos de ejecución para usuarios autenticados
grant execute on function public.register_logistica_document(jsonb) to authenticated;
grant execute on function public.list_logistica_documents(jsonb) to authenticated;
grant execute on function public.deactivate_logistica_document(jsonb) to authenticated;
