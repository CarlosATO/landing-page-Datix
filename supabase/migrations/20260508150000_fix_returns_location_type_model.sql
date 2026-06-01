-- Align returns and traceability with the official WMS model:
-- inventory_batches.current_quantity + locations.location_type.
-- No FEFO/POS changes in this migration.

CREATE OR REPLACE FUNCTION pharmacy.process_sale_return(
    p_sale_id uuid,
    p_reason text,
    p_items jsonb
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
    v_quarantine_batch_id uuid;
    v_total_return_amount numeric := 0;
    v_folio bigint;
    v_cn_id uuid;
    v_warehouse_id uuid;
    v_already_returned numeric;
    v_requested_qty numeric;
    v_balance_after numeric;
begin
    v_user_id := auth.uid();
    if v_user_id is null then raise exception 'No autenticado'; end if;

    v_company_id := pharmacy.get_my_company_id();
    if v_company_id is null then raise exception 'Empresa no encontrada'; end if;

    if p_items is null or jsonb_array_length(p_items) = 0 then
        raise exception 'La devolución no contiene productos';
    end if;

    select *
    into v_sale
    from pharmacy.sales
    where id = p_sale_id
      and company_id = v_company_id
    for update;

    if not found then
        raise exception 'Venta no encontrada';
    end if;

    select warehouse_id
    into v_warehouse_id
    from pharmacy.pos_sessions
    where id = v_sale.session_id;

    select id
    into v_quarantine_location_id
    from pharmacy.locations
    where company_id = v_company_id
      and warehouse_id = v_warehouse_id
      and location_type = 'QUARANTINE'
      and is_active = true
    limit 1;

    if v_quarantine_location_id is null then
        raise exception 'No se encontró una ubicación de tipo CUARENTENA en el almacén de la venta.';
    end if;

    insert into pharmacy.sales_returns (company_id, sale_id, reason, created_by, total_amount)
    values (v_company_id, p_sale_id, p_reason, v_user_id, 0)
    returning id into v_return_id;

    for v_item in select * from jsonb_array_elements(p_items)
    loop
        v_requested_qty := coalesce(nullif(v_item->>'quantity', '')::numeric, 0);

        if v_requested_qty <= 0 then
            raise exception 'Cantidad inválida para devolución: %', v_requested_qty;
        end if;

        select
            si.*,
            p.is_controlled,
            b.batch_number,
            b.expiry_date,
            b.po_id
        into v_sale_item
        from pharmacy.sale_items si
        join pharmacy.products p on p.id = si.product_id
        join pharmacy.inventory_batches b on b.id = si.batch_id
        where si.id = (v_item->>'sale_item_id')::uuid
          and si.sale_id = p_sale_id
          and si.company_id = v_company_id
        for update of si, b;

        if not found then
            raise exception 'Item de venta % no encontrado', (v_item->>'sale_item_id');
        end if;

        select coalesce(sum(quantity), 0)
        into v_already_returned
        from pharmacy.sales_return_items
        where company_id = v_company_id
          and sale_item_id = v_sale_item.id;

        if (v_requested_qty + v_already_returned) > v_sale_item.quantity then
            raise exception 'La devolución excede el saldo disponible. Vendido: %, Ya devuelto: %, Solicitado: %',
                v_sale_item.quantity, v_already_returned, v_requested_qty;
        end if;

        insert into pharmacy.sales_return_items (
            company_id, return_id, sale_item_id, product_id, batch_id, quantity, unit_price, subtotal
        ) values (
            v_company_id, v_return_id, v_sale_item.id, v_sale_item.product_id, v_sale_item.batch_id,
            v_requested_qty, v_sale_item.unit_price, v_requested_qty * v_sale_item.unit_price
        );

        v_total_return_amount := v_total_return_amount + (v_requested_qty * v_sale_item.unit_price);

        select id
        into v_quarantine_batch_id
        from pharmacy.inventory_batches
        where company_id = v_company_id
          and product_id = v_sale_item.product_id
          and location_id = v_quarantine_location_id
          and batch_number = v_sale_item.batch_number
          and expiry_date = v_sale_item.expiry_date
        for update;

        if found then
            update pharmacy.inventory_batches
            set current_quantity = current_quantity + v_requested_qty
            where id = v_quarantine_batch_id;
        else
            insert into pharmacy.inventory_batches (
                company_id,
                product_id,
                po_id,
                location_id,
                batch_number,
                expiry_date,
                initial_quantity,
                current_quantity
            ) values (
                v_company_id,
                v_sale_item.product_id,
                v_sale_item.po_id,
                v_quarantine_location_id,
                v_sale_item.batch_number,
                v_sale_item.expiry_date,
                v_requested_qty,
                v_requested_qty
            )
            returning id into v_quarantine_batch_id;
        end if;

        select coalesce(sum(b.current_quantity), 0)
        into v_balance_after
        from pharmacy.inventory_batches b
        join pharmacy.locations l on l.id = b.location_id
        where b.company_id = v_company_id
          and b.product_id = v_sale_item.product_id
          and l.warehouse_id = v_warehouse_id
          and l.location_type = 'QUARANTINE';

        insert into pharmacy.inventory_movements (
            company_id,
            product_id,
            batch_id,
            batch_number,
            to_location_id,
            movement_type,
            quantity,
            reference_folio,
            created_by,
            balance_after,
            notes
        ) values (
            v_company_id,
            v_sale_item.product_id,
            v_sale_item.batch_id,
            v_sale_item.batch_number,
            v_quarantine_location_id,
            'RETURN',
            v_requested_qty,
            'RET-' || v_return_id::text,
            v_user_id,
            v_balance_after,
            'Stock devuelto a cuarentena física. Batch origen: ' || v_sale_item.batch_id::text || ', batch cuarentena: ' || v_quarantine_batch_id::text
        );
    end loop;

    update pharmacy.sales_returns
    set total_amount = v_total_return_amount
    where id = v_return_id;

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

GRANT EXECUTE ON FUNCTION pharmacy.process_sale_return(uuid, text, jsonb) TO authenticated;

CREATE OR REPLACE VIEW pharmacy.view_batch_registry AS
SELECT
    b.id,
    b.company_id,
    b.product_id,
    p.name as product_name,
    p.dci as product_dci,
    b.batch_number,
    b.expiry_date,
    b.current_quantity,
    case
      when upper(l.location_type) = 'QUARANTINE' then 0
      else coalesce(b.current_quantity, 0)
    end as active_quantity,
    case
      when upper(l.location_type) = 'QUARANTINE' then coalesce(b.current_quantity, 0)
      else 0
    end as quarantine_stock,
    b.created_at,
    b.po_id,
    l.id as location_id,
    l.name as location_name,
    l.location_type,
    w.id as warehouse_id,
    w.name as warehouse_name,
    po.po_number,
    po.issue_date as purchase_order_date,
    s.id as supplier_id,
    coalesce(s.commercial_name, s.legal_name) as supplier_name,
    origin.receipt_id,
    origin.document_type as receipt_document_type,
    origin.document_number as receipt_document_number,
    origin.received_date,
    origin.origin_movement_type,
    case
      when po.id is not null or origin.receipt_id is not null or origin.origin_movement_type in ('IN_PURCHASE', 'INBOUND_TRANSFER') then 'RECEPCION_REAL'
      when exists (
        select 1
        from pharmacy.inventory_movements ret
        where ret.batch_number = b.batch_number
          and ret.product_id = b.product_id
          and ret.movement_type = 'RETURN'
      ) then 'DEVOLUCION'
      else 'SIN_ORIGEN'
    end as source_type,
    case
      when upper(l.location_type) = 'QUARANTINE' then 'CUARENTENA'
      else 'ACTIVO'
    end as warehouse_state
FROM pharmacy.inventory_batches b
JOIN pharmacy.products p on p.id = b.product_id
LEFT JOIN pharmacy.locations l on l.id = b.location_id
LEFT JOIN pharmacy.warehouses w on w.id = l.warehouse_id
LEFT JOIN pharmacy.purchase_orders po on po.id = b.po_id
LEFT JOIN LATERAL (
    select
      r.id as receipt_id,
      r.document_type,
      r.document_number,
      r.received_date,
      im_in.movement_type as origin_movement_type,
      r.supplier_id
    from pharmacy.inventory_movements im_in
    left join pharmacy.inventory_receipts r on r.id = im_in.receipt_id
    where im_in.batch_id = b.id
      and im_in.movement_type in ('IN_PURCHASE', 'INBOUND_TRANSFER')
    order by im_in.created_at asc
    limit 1
) origin on true
LEFT JOIN pharmacy.suppliers s on s.id = coalesce(origin.supplier_id, po.supplier_id);

CREATE OR REPLACE VIEW pharmacy.view_batch_audit AS
SELECT
    im.id,
    im.created_at,
    p.name as product_name,
    p.dci as product_dci,
    im.batch_number,
    im.movement_type,
    im.quantity,
    im.balance_after,
    im.reference_folio,
    cu.full_name as operator_name,
    move_l.name as location_name,
    move_w.name as warehouse_name,
    im.company_id,
    im.product_id,
    im.batch_id,
    move_l.location_type as location_type,
    b.expiry_date,
    coalesce(b.current_quantity, 0) as current_quantity,
    case
      when upper(coalesce(batch_l.location_type, '')) = 'QUARANTINE' then 0
      else coalesce(b.current_quantity, 0)
    end as active_quantity,
    case
      when upper(coalesce(batch_l.location_type, '')) = 'QUARANTINE' then coalesce(b.current_quantity, 0)
      else 0
    end as quarantine_stock,
    case
      when im.movement_type = 'RETURN' or upper(coalesce(move_l.location_type, batch_l.location_type, '')) = 'QUARANTINE' then 'CUARENTENA'
      else 'ACTIVO'
    end as warehouse_state,
    po.id as purchase_order_id,
    po.po_number,
    po.issue_date as purchase_order_date,
    coalesce(s.commercial_name, s.legal_name) as supplier_name,
    origin.receipt_id,
    origin.document_type as receipt_document_type,
    origin.document_number as receipt_document_number,
    origin.received_date,
    case
      when po.id is not null or origin.receipt_id is not null or origin.origin_movement_type in ('IN_PURCHASE', 'INBOUND_TRANSFER') then 'RECEPCION_REAL'
      when im.movement_type = 'RETURN' then 'DEVOLUCION'
      else 'SIN_ORIGEN'
    end as source_type
FROM pharmacy.inventory_movements im
JOIN pharmacy.products p ON p.id = im.product_id
LEFT JOIN pharmacy.inventory_batches b ON b.id = im.batch_id
LEFT JOIN pharmacy.locations batch_l ON batch_l.id = b.location_id
LEFT JOIN pharmacy.locations move_l ON move_l.id = COALESCE(im.to_location_id, im.destination_location_id, im.from_location_id, im.source_location_id, b.location_id)
LEFT JOIN pharmacy.warehouses move_w ON move_w.id = move_l.warehouse_id
LEFT JOIN pharmacy.purchase_orders po ON po.id = b.po_id
LEFT JOIN LATERAL (
    select
      r.id as receipt_id,
      r.document_type,
      r.document_number,
      r.received_date,
      im_in.movement_type as origin_movement_type,
      r.supplier_id
    from pharmacy.inventory_movements im_in
    left join pharmacy.inventory_receipts r on r.id = im_in.receipt_id
    where im_in.batch_id = im.batch_id
      and im_in.movement_type in ('IN_PURCHASE', 'INBOUND_TRANSFER')
    order by im_in.created_at asc
    limit 1
) origin on true
LEFT JOIN pharmacy.suppliers s ON s.id = COALESCE(origin.supplier_id, po.supplier_id)
LEFT JOIN public.company_users cu ON cu.user_id = im.created_by AND cu.company_id = im.company_id;

GRANT SELECT ON pharmacy.view_batch_registry TO authenticated;
GRANT SELECT ON pharmacy.view_batch_audit TO authenticated;
