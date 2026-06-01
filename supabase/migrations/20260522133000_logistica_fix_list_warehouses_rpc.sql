create or replace function logistica.list_warehouses(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_include_inactive boolean := true;
  v_search text;
  v_membership_role text;
  v_warehouses jsonb := '[]'::jsonb;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_include_inactive := coalesce((p_payload->>'include_inactive')::boolean, true);
  v_search := nullif(btrim(coalesce(p_payload->>'search', '')), '');

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if not exists (
    select 1
    from public.company_users cu
    where cu.company_id = v_company_id
      and cu.user_id = v_user_id
  ) then
    raise exception 'forbidden';
  end if;

  select cu.role
    into v_membership_role
  from public.company_users cu
  where cu.company_id = v_company_id
    and cu.user_id = v_user_id
  limit 1;

  if not exists (
    select 1
    from public.company_modules cm
    where cm.company_id = v_company_id
      and lower(cm.module_key) = 'logistica'
      and lower(cm.status) in ('active', 'trial')
  ) then
    raise exception 'module access required';
  end if;

  if not (
    upper(coalesce(v_membership_role, '')) = 'OWNER'
    or public.has_role(v_company_id, 'ADMIN_LOGISTICA', 'logistica')
    or public.has_role(v_company_id, 'OPERARIO_LOGISTICA', 'logistica')
  ) then
    raise exception 'insufficient role';
  end if;

  select coalesce(jsonb_agg(to_jsonb(w) order by w.name asc), '[]'::jsonb)
    into v_warehouses
  from (
    select
      w.id,
      w.company_id,
      w.code,
      w.name,
      w.description,
      w.warehouse_type,
      w.is_active,
      w.created_at,
      w.updated_at
    from logistica.warehouses w
    where w.company_id = v_company_id
      and (
        v_include_inactive
        or coalesce(w.is_active, true) = true
      )
      and (
        v_search is null
        or upper(w.code) like '%' || upper(v_search) || '%'
        or upper(w.name) like '%' || upper(v_search) || '%'
      )
    order by w.name asc
  ) w;

  return jsonb_build_object(
    'success', true,
    'warehouses', v_warehouses
  );
end;
$$;

grant execute on function logistica.list_warehouses(jsonb) to authenticated;
