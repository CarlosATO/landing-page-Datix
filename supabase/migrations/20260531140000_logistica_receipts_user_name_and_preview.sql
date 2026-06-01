-- 20260531140000_logistica_receipts_user_name_and_preview.sql
-- Redefine get_receipt_detail to include resolved user names (created_by_name) for professional SaaS aesthetics.

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
      coalesce(cu.full_name, cu.email, rh.created_by::text) as created_by_name,
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
    left join public.company_users cu on cu.user_id = rh.created_by and cu.company_id = rh.company_id
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

grant execute on function logistica.get_receipt_detail(jsonb) to authenticated;
