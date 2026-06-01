-- Harden process_pharmacy_sale for high concurrency and prevent race conditions
CREATE OR REPLACE FUNCTION "pharmacy"."process_pharmacy_sale"("p_warehouse_id" "uuid", "p_total_amount" numeric, "p_payment_method" "text", "p_document_number" "text", "p_patient_id" "uuid" DEFAULT NULL::"uuid", "p_prescription_id" "uuid" DEFAULT NULL::"uuid", "p_items" "jsonb" DEFAULT '[]'::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pharmacy', 'public'
    AS $$
declare
  v_user_id uuid;
  v_company_id uuid;
  v_session_id uuid;
  v_sale_id uuid;

  v_item jsonb;
  v_product_id uuid;
  v_quantity numeric;
  v_unit_price numeric;
  v_item_prescription_id uuid;

  v_remaining numeric;
  v_qty_to_deduct numeric;
  v_batch record;
  v_balance_after numeric;

  v_sale_condition text;
  v_product_prescription_type text;
  v_is_controlled boolean;

  v_prescription_status text;
  v_prescription_type text;
  v_prescription_patient_id uuid;
  v_prescription_valid_until timestamptz;
  v_qty_prescribed numeric;
  v_qty_dispensed numeric;
  v_qty_pending numeric;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception 'Usuario no autenticado';
  end if;

  -- 1. Resolver Company ID
  select company_id
  into v_company_id
  from public.company_users
  where user_id = v_user_id
  limit 1;

  if v_company_id is null then
    raise exception 'Usuario sin empresa asociada';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'La venta no contiene productos';
  end if;

  -- 2. Lock de Sesión POS (Fail-fast)
  begin
    select id
    into v_session_id
    from pharmacy.pos_sessions
    where company_id = v_company_id
      and user_id = v_user_id
      and warehouse_id = p_warehouse_id
      and status = 'OPEN'
    order by created_at desc
    limit 1
    for update nowait;
  exception
    when lock_not_available then
      raise exception 'Su sesión de caja está siendo procesada en otra transacción.';
  end;

  if v_session_id is null then
    raise exception 'Debes abrir caja antes de vender';
  end if;

  -- 3. Crear Cabecera de Venta
  insert into pharmacy.sales (
    company_id,
    user_id,
    session_id,
    patient_id,
    total_amount,
    payment_method,
    document_number
  )
  values (
    v_company_id,
    v_user_id,
    v_session_id,
    p_patient_id,
    p_total_amount,
    coalesce(p_payment_method, 'CASH'),
    coalesce(p_document_number, 'TICKET-' || extract(epoch from now())::bigint)
  )
  returning id into v_sale_id;

  -- 4. Procesar Items
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_product_id := coalesce(
      nullif(v_item->>'product_id', '')::uuid,
      nullif(v_item->>'id', '')::uuid
    );

    v_item_prescription_id := coalesce(
      nullif(v_item->>'prescription_id', '')::uuid,
      p_prescription_id
    );

    v_quantity := coalesce((v_item->>'quantity')::numeric, 0);

    v_unit_price := coalesce(
      nullif(v_item->>'unit_price', '')::numeric,
      nullif(v_item->>'price_sale', '')::numeric,
      0
    );

    if v_product_id is null then
      raise exception 'Producto inválido en carrito';
    end if;

    if v_quantity <= 0 then
      raise exception 'Cantidad inválida para producto %', v_product_id;
    end if;

    -- Datos de control del producto
    select
      upper(coalesce(sale_condition, 'VD')),
      upper(coalesce(prescription_type, 'VENTA_LIBRE')),
      coalesce(is_controlled, false)
    into
      v_sale_condition,
      v_product_prescription_type,
      v_is_controlled
    from pharmacy.products
    where id = v_product_id
      and company_id = v_company_id;

    if v_sale_condition is null then
      raise exception 'Producto no encontrado o no pertenece a la empresa';
    end if;

    -- 5. Validación de Receta (Concurrencia)
    if v_is_controlled = true
       or v_sale_condition in ('R', 'RR', 'RCH')
       or v_product_prescription_type in ('RECETA_SIMPLE', 'RECETA_RETENIDA', 'RECETA_CHEQUE')
    then
      if v_item_prescription_id is null then
        raise exception 'El producto requiere receta médica válida';
      end if;

      begin
        select
          status,
          upper(coalesce(prescription_type, 'RECETA_SIMPLE')),
          patient_id,
          valid_until
        into
          v_prescription_status,
          v_prescription_type,
          v_prescription_patient_id,
          v_prescription_valid_until
        from pharmacy.prescriptions
        where id = v_item_prescription_id
          and company_id = v_company_id
        for update nowait;
      exception
        when lock_not_available then
          raise exception 'La receta está siendo procesada en otra caja.';
      end;

      if v_prescription_status is null then
        raise exception 'Receta no encontrada';
      end if;

      -- Validación de vencimiento con tolerancia
      if v_prescription_valid_until is not null and now() > (v_prescription_valid_until + interval '1 day') then
        update pharmacy.prescriptions 
        set status = 'EXPIRED', 
            expired_at = now() 
        where id = v_item_prescription_id;
        
        raise exception 'La receta se encuentra vencida';
      end if;

      if v_prescription_status not in ('PENDING', 'PARTIAL') then
        raise exception 'La receta ya no está disponible para despacho (Estado: %)', v_prescription_status;
      end if;

      if p_patient_id is not null and v_prescription_patient_id <> p_patient_id then
        raise exception 'La receta no pertenece al paciente seleccionado';
      end if;

      -- Validar tipo de receta vs producto
      if (v_sale_condition = 'RR' or v_product_prescription_type = 'RECETA_RETENIDA') and v_prescription_type <> 'RECETA_RETENIDA' then
        raise exception 'Este producto requiere receta retenida';
      end if;

      if (v_sale_condition = 'RCH' or v_product_prescription_type = 'RECETA_CHEQUE') and v_prescription_type <> 'RECETA_CHEQUE' then
        raise exception 'Este producto requiere receta cheque';
      end if;

      -- Lock de items de receta y recálculo de pendientes
      begin
        select
          quantity_prescribed,
          coalesce(quantity_dispensed, 0)
        into
          v_qty_prescribed,
          v_qty_dispensed
        from pharmacy.prescription_items
        where prescription_id = v_item_prescription_id
          and product_id = v_product_id
        for update nowait;
      exception
        when lock_not_available then
          raise exception 'Los items de esta receta están bloqueados por otra operación.';
      end;

      if v_qty_prescribed is null then
        raise exception 'El producto no está incluido en la receta';
      end if;

      v_qty_pending := v_qty_prescribed - v_qty_dispensed;

      if v_qty_pending <= 0 then
        raise exception 'El producto ya fue completamente despachado en esta receta.';
      end if;

      if v_quantity > v_qty_pending then
        raise exception 'La cantidad vendida (%) supera la cantidad pendiente de la receta (%)', v_quantity, v_qty_pending;
      end if;
    end if;

    -- 6. Descuento de Stock y Lotes (Concurrencia)
    v_remaining := v_quantity;

    for v_batch in
      select 
        b.id,
        b.product_id,
        b.batch_number,
        b.current_quantity,
        b.location_id,
        b.expiry_date
      from pharmacy.inventory_batches b
      join pharmacy.locations l on l.id = b.location_id
      where b.company_id = v_company_id
        and b.product_id = v_product_id
        and b.current_quantity > 0
        and l.company_id = v_company_id
        and l.warehouse_id = p_warehouse_id
        and upper(l.location_type) <> 'QUARANTINE'
      order by 
        case when upper(l.location_type) = 'SALES' then 0 else 1 end,
        b.expiry_date asc
      for update of b nowait
    loop
      exit when v_remaining <= 0;

      -- Re-validar stock después del lock
      if v_batch.current_quantity <= 0 then
        continue;
      end if;

      v_qty_to_deduct := least(v_remaining, v_batch.current_quantity);

      update pharmacy.inventory_batches
      set current_quantity = current_quantity - v_qty_to_deduct
      where id = v_batch.id
        and company_id = v_company_id
        and current_quantity >= v_qty_to_deduct; -- Guardrail contra underflow

      if not found then
        raise exception 'Error de concurrencia: El stock del lote % cambió durante la transacción.', v_batch.batch_number;
      end if;

      insert into pharmacy.sale_items (
        company_id,
        sale_id,
        product_id,
        batch_id,
        quantity,
        unit_price,
        subtotal,
        prescription_id
      )
      values (
        v_company_id,
        v_sale_id,
        v_product_id,
        v_batch.id,
        v_qty_to_deduct,
        v_unit_price,
        v_qty_to_deduct * v_unit_price,
        v_item_prescription_id
      );

      -- Kardex
      select coalesce(sum(current_quantity), 0)
      into v_balance_after
      from pharmacy.inventory_batches
      where company_id = v_company_id
        and product_id = v_product_id
        and location_id = v_batch.location_id;

      insert into pharmacy.inventory_movements (
        company_id,
        product_id,
        batch_id,
        batch_number,
        from_location_id,
        movement_type,
        quantity,
        balance_after,
        reference_folio,
        created_by
      )
      values (
        v_company_id,
        v_product_id,
        v_batch.id,
        v_batch.batch_number,
        v_batch.location_id,
        'SALE',
        -abs(v_qty_to_deduct),
        v_balance_after,
        coalesce(p_document_number, 'VENTA_POS'),
        v_user_id
      );

      v_remaining := v_remaining - v_qty_to_deduct;
    end loop;

    if v_remaining > 0 then
      raise exception 'Stock insuficiente para el producto %. Faltan % unidades (posible venta simultánea).', v_product_id, v_remaining;
    end if;

    -- Actualizar quantity_dispensed en la receta
    if v_item_prescription_id is not null then
      update pharmacy.prescription_items
      set quantity_dispensed = coalesce(quantity_dispensed, 0) + v_quantity
      where prescription_id = v_item_prescription_id
        and product_id = v_product_id;
    end if;
  end loop;

  -- 7. Actualizar Estados de Recetas (Batch)
  update pharmacy.prescriptions p
  set status = case
    when totals.total_dispensed <= 0 then 'PENDING'
    when totals.total_dispensed < totals.total_prescribed then 'PARTIAL'
    else 'DISPENSED'
  end
  from (
    select
      pi.prescription_id,
      sum(pi.quantity_prescribed) as total_prescribed,
      sum(coalesce(pi.quantity_dispensed, 0)) as total_dispensed
    from pharmacy.prescription_items pi
    where pi.prescription_id in (
      select distinct coalesce(
        nullif(item->>'prescription_id', '')::uuid,
        p_prescription_id
      )
      from jsonb_array_elements(p_items) item
      where coalesce(
        nullif(item->>'prescription_id', ''),
        p_prescription_id::text
      ) is not null
    )
    group by pi.prescription_id
  ) totals
  where p.id = totals.prescription_id
    and p.company_id = v_company_id;

  return jsonb_build_object(
    'sale_id', v_sale_id,
    'session_id', v_session_id,
    'company_id', v_company_id,
    'success', true
  );

exception
  when lock_not_available then
    raise exception 'Conflicto de concurrencia: Los recursos (stock o receta) están siendo usados por otra caja. Intente nuevamente.';
end;
$$;
