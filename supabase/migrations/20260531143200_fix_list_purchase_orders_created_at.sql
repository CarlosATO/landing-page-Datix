-- 20260531143200_fix_list_purchase_orders_created_at.sql
-- Fix list_purchase_orders RPC to expose created_at in the subquery so order by o.created_at desc works.

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
      po.created_at, -- Exponer created_at para el ordenamiento externo
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

grant execute on function logistica.list_purchase_orders(jsonb) to authenticated;
