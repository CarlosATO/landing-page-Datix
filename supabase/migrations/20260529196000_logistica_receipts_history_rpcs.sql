-- 20260529196000_logistica_receipts_history_rpcs.sql
-- Bloque 1: historial y detalle de recepciones.

create or replace function logistica.list_receipt_headers(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, logistica, public
as $$
declare
  v_company_id uuid;
  v_search text;
  v_supplier_id uuid;
  v_status text;
  v_from_date date;
  v_to_date date;
  v_receipts jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_search := nullif(btrim(coalesce(p_payload->>'search', '')), '');
  v_supplier_id := nullif(btrim(coalesce(p_payload->>'supplier_id', '')), '')::uuid;
  v_status := nullif(btrim(coalesce(p_payload->>'status', '')), '');
  v_from_date := nullif(btrim(coalesce(p_payload->>'from_date', '')), '')::date;
  v_to_date := nullif(btrim(coalesce(p_payload->>'to_date', '')), '')::date;

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if not public.has_company_access(v_company_id) then
    raise exception 'forbidden';
  end if;

  if not public.has_module_access(v_company_id, 'logistica') then
    raise exception 'module access required';
  end if;

  select coalesce(jsonb_agg(to_jsonb(r) order by r.receipt_date desc, r.receipt_reference desc), '[]'::jsonb)
    into v_receipts
  from (
    select
      rh.id as receipt_id,
      rh.receipt_reference,
      rh.receipt_date,
      coalesce(s.business_name, s.name) as supplier_name,
      rh.document_number,
      coalesce(cc.code || ' - ' || cc.name, cc.name) as cost_center,
      coalesce(w.code || ' - ' || w.name, w.name) as warehouse,
      coalesce(l.code || ' - ' || l.name, l.name) as location,
      rh.status,
      rh.total_cost,
      (
        select count(*)::integer
        from logistica.receipt_lines rl
        where rl.receipt_id = rh.id
      ) as line_count,
      false as has_documents
    from logistica.receipt_headers rh
    left join public.suppliers s on s.id = rh.supplier_id
    left join public.cost_centers cc on cc.id = rh.cost_center_id
    left join logistica.warehouses w on w.id = rh.warehouse_id
    left join logistica.locations l on l.id = rh.location_id
    where rh.company_id = v_company_id
      and (v_search is null or rh.receipt_reference ilike ('%' || v_search || '%') or rh.document_number ilike ('%' || v_search || '%') or coalesce(s.business_name, s.name, '') ilike ('%' || v_search || '%'))
      and (v_supplier_id is null or rh.supplier_id = v_supplier_id)
      and (v_status is null or lower(rh.status) = lower(v_status))
      and (v_from_date is null or rh.receipt_date::date >= v_from_date)
      and (v_to_date is null or rh.receipt_date::date <= v_to_date)
    order by rh.receipt_date desc, rh.created_at desc
  ) r;

  return jsonb_build_object('success', true, 'receipts', v_receipts);
end;
$$;

create or replace function logistica.get_receipt_detail(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, logistica, public
as $$
declare
  v_company_id uuid;
  v_receipt_id uuid;
  v_header jsonb := null;
  v_lines jsonb := '[]'::jsonb;
  v_movements jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_receipt_id := nullif(btrim(coalesce(p_payload->>'receipt_id', '')), '')::uuid;

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if v_receipt_id is null then
    raise exception 'receipt_id es obligatorio';
  end if;

  if not public.has_company_access(v_company_id) then
    raise exception 'forbidden';
  end if;

  if not public.has_module_access(v_company_id, 'logistica') then
    raise exception 'module access required';
  end if;

  select to_jsonb(h)
    into v_header
  from (
    select
      rh.*,
      coalesce(s.business_name, s.name) as supplier_name,
      s.tax_id as supplier_tax_id,
      coalesce(cc.code || ' - ' || cc.name, cc.name) as cost_center,
      coalesce(w.code || ' - ' || w.name, w.name) as warehouse,
      coalesce(l.code || ' - ' || l.name, l.name) as location
    from logistica.receipt_headers rh
    left join public.suppliers s on s.id = rh.supplier_id
    left join public.cost_centers cc on cc.id = rh.cost_center_id
    left join logistica.warehouses w on w.id = rh.warehouse_id
    left join logistica.locations l on l.id = rh.location_id
    where rh.id = v_receipt_id
      and rh.company_id = v_company_id
  ) h;

  if v_header is null then
    raise exception 'receipt not found';
  end if;

  select coalesce(jsonb_agg(to_jsonb(l) order by l.line_number asc), '[]'::jsonb)
    into v_lines
  from (
    select
      rl.*,
      i.sku,
      i.name as item_name
    from logistica.receipt_lines rl
    join logistica.items i on i.id = rl.item_id
    where rl.receipt_id = v_receipt_id
      and rl.company_id = v_company_id
    order by rl.line_number asc
  ) l;

  select coalesce(jsonb_agg(to_jsonb(m) order by m.created_at asc), '[]'::jsonb)
    into v_movements
  from (
    select
      sm.*,
      i.sku,
      i.name as item_name,
      lot.lot_code,
      ser.serial_number,
      fw.code || ' - ' || fw.name as from_warehouse,
      fl.code || ' - ' || fl.name as from_location,
      tw.code || ' - ' || tw.name as to_warehouse,
      tl.code || ' - ' || tl.name as to_location
    from logistica.stock_movements sm
    join logistica.items i on i.id = sm.item_id
    left join logistica.item_lots lot on lot.id = sm.lot_id
    left join logistica.item_serials ser on ser.id = sm.serial_id
    left join logistica.warehouses fw on fw.id = sm.from_warehouse_id
    left join logistica.locations fl on fl.id = sm.from_location_id
    left join logistica.warehouses tw on tw.id = sm.to_warehouse_id
    left join logistica.locations tl on tl.id = sm.to_location_id
    where sm.receipt_id = v_receipt_id
      and sm.company_id = v_company_id
    order by sm.created_at asc
  ) m;

  return jsonb_build_object(
    'success', true,
    'header', v_header,
    'lines', v_lines,
    'movements', v_movements
  );
end;
$$;

grant execute on function logistica.list_receipt_headers(jsonb) to authenticated;
grant execute on function logistica.get_receipt_detail(jsonb) to authenticated;
