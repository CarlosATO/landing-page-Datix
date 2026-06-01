create or replace function public.list_warehouses(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, logistica
as $$
begin
  return logistica.list_warehouses(p_payload);
end;
$$;

create or replace function public.create_warehouse(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, logistica
as $$
begin
  return logistica.create_warehouse(p_payload);
end;
$$;

create or replace function public.update_warehouse(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, logistica
as $$
begin
  return logistica.update_warehouse(p_payload);
end;
$$;

create or replace function public.deactivate_warehouse(p_warehouse_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, logistica
as $$
begin
  return logistica.deactivate_warehouse(p_warehouse_id);
end;
$$;

grant execute on function public.list_warehouses(jsonb) to authenticated;
grant execute on function public.create_warehouse(jsonb) to authenticated;
grant execute on function public.update_warehouse(jsonb) to authenticated;
grant execute on function public.deactivate_warehouse(uuid) to authenticated;
