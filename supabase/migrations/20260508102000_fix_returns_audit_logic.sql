-- Fix Audit Logging in process_sale_return
CREATE OR REPLACE FUNCTION "pharmacy"."process_sale_return"(
    "p_sale_id" uuid,
    "p_reason" text,
    "p_items" jsonb -- [{sale_item_id, quantity}]
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pharmacy', 'public'
AS $$
declare
    v_user_id uuid;
    v_company_id uuid;
    v_sale record;
    v_return_id uuid;
    v_item jsonb;
    v_sale_item record;
    v_quarantine_location_id uuid;
    v_new_batch_id uuid;
    v_total_return_amount numeric := 0;
    v_folio bigint;
    v_cn_id uuid;
    v_warehouse_id uuid;
begin
    v_user_id := auth.uid();
    if v_user_id is null then raise exception 'No autenticado'; end if;

    select company_id into v_company_id from public.company_users where user_id = v_user_id limit 1;
    if v_company_id is null then raise exception 'Empresa no encontrada'; end if;

    -- 1. Validar y bloquear venta
    select * into v_sale from pharmacy.sales where id = p_sale_id and company_id = v_company_id for update;
    if not found then raise exception 'Venta no encontrada'; end if;

    -- Obtener warehouse desde la sesión de la venta
    select warehouse_id into v_warehouse_id from pharmacy.pos_sessions where id = v_sale.session_id;

    -- 2. Buscar ubicación de cuarentena para este warehouse
    select id into v_quarantine_location_id 
    from pharmacy.locations 
    where warehouse_id = v_warehouse_id 
      and location_type = 'QUARANTINE' 
      and is_active = true 
    limit 1;

    if v_quarantine_location_id is null then 
        raise exception 'No se encontró una ubicación de tipo CUARENTENA en el almacén de la venta.';
    end if;

    -- 3. Crear cabecera de devolución
    insert into pharmacy.sales_returns (company_id, sale_id, reason, created_by, total_amount)
    values (v_company_id, p_sale_id, p_reason, v_user_id, 0)
    returning id into v_return_id;

    -- 4. Procesar items
    for v_item in select * from jsonb_array_elements(p_items)
    loop
        -- Obtener item de venta original
        select si.*, p.is_controlled, b.batch_number, b.expiry_date, b.product_id as b_product_id
        into v_sale_item 
        from pharmacy.sale_items si
        join pharmacy.products p on p.id = si.product_id
        join pharmacy.inventory_batches b on b.id = si.batch_id
        where si.id = (v_item->>'sale_item_id')::uuid 
          and si.sale_id = p_sale_id
        for update;

        if not found then raise exception 'Item de venta % no encontrado', (v_item->>'sale_item_id'); end if;

        -- Validar cantidad
        if (v_item->>'quantity')::numeric > v_sale_item.quantity then
            raise exception 'La cantidad a devolver (%) excede la cantidad vendida (%)', (v_item->>'quantity')::numeric, v_sale_item.quantity;
        end if;

        -- Registrar item de devolución
        insert into pharmacy.sales_return_items (
            company_id, return_id, sale_item_id, product_id, batch_id, quantity, unit_price, subtotal
        ) values (
            v_company_id, v_return_id, v_sale_item.id, v_sale_item.product_id, v_sale_item.batch_id, 
            (v_item->>'quantity')::numeric, v_sale_item.unit_price, (v_item->>'quantity')::numeric * v_sale_item.unit_price
        );

        v_total_return_amount := v_total_return_amount + ((v_item->>'quantity')::numeric * v_sale_item.unit_price);

        -- 5. Gestionar Stock (Mover a Cuarentena)
        select id into v_new_batch_id 
        from pharmacy.inventory_batches 
        where company_id = v_company_id 
          and product_id = v_sale_item.product_id 
          and location_id = v_quarantine_location_id 
          and batch_number = v_sale_item.batch_number
        for update;

        if found then
            update pharmacy.inventory_batches 
            set current_quantity = current_quantity + (v_item->>'quantity')::numeric 
            where id = v_new_batch_id;
        else
            insert into pharmacy.inventory_batches (
                company_id, product_id, location_id, batch_number, expiry_date, initial_quantity, current_quantity
            ) values (
                v_company_id, v_sale_item.product_id, v_quarantine_location_id, v_sale_item.batch_number, 
                v_sale_item.expiry_date, (v_item->>'quantity')::numeric, (v_item->>'quantity')::numeric
            ) returning id into v_new_batch_id;
        end if;

        -- 6. Registrar movimiento de inventario (Kardex Reverso)
        insert into pharmacy.inventory_movements (
            company_id, product_id, batch_id, batch_number, to_location_id, 
            movement_type, quantity, reference_folio, created_by, balance_after
        ) values (
            v_company_id, v_sale_item.product_id, v_new_batch_id, v_sale_item.batch_number, v_quarantine_location_id,
            'RETURN', (v_item->>'quantity')::numeric, 'RET-' || v_return_id::text, v_user_id,
            (select sum(current_quantity) from pharmacy.inventory_batches where product_id = v_sale_item.product_id and company_id = v_company_id)
        );

    end loop;

    -- Actualizar total de la devolución
    update pharmacy.sales_returns set total_amount = v_total_return_amount where id = v_return_id;

    -- 7. Generar Nota de Crédito Interna
    insert into pharmacy.dte_folios (company_id, dte_type, current_folio)
    values (v_company_id, 'NOTA_CREDITO', 1)
    on conflict (company_id, dte_type)
    do update set current_folio = dte_folios.current_folio + 1
    returning current_folio into v_folio;

    insert into pharmacy.internal_credit_notes (
        company_id, return_id, sale_id, folio, total_amount, status
    ) values (
        v_company_id, v_return_id, p_sale_id, v_folio, v_total_return_amount, 'GENERATED'
    ) returning id into v_cn_id;

    -- 8. Auditar evento (CORREGIDO: usando columnas reales de pharmacy.audit_logs)
    insert into pharmacy.audit_logs (
        company_id, 
        user_id, 
        event_type, 
        description, 
        metadata
    ) values (
        v_company_id, 
        v_user_id, 
        'SALE_RETURN', 
        'Devolución de venta procesada. Folio NC: ' || v_folio::text, 
        jsonb_build_object(
            'return_id', v_return_id, 
            'sale_id', p_sale_id,
            'total_amount', v_total_return_amount, 
            'folio_nc', v_folio,
            'reason', p_reason
        )
    );

    return jsonb_build_object(
        'success', true,
        'return_id', v_return_id,
        'folio_nc', v_folio,
        'total_amount', v_total_return_amount
    );

exception when others then
    raise exception 'Error en proceso de devolución: %', sqlerrm;
end;
$$;
