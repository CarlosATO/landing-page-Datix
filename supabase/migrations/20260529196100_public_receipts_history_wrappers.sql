-- 20260529196100_public_receipts_history_wrappers.sql
-- Wrappers publicos para historial/detalle de recepciones.

create or replace function public.list_receipt_headers(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, logistica
as $$
begin
  return logistica.list_receipt_headers(p_payload);
end;
$$;

create or replace function public.get_receipt_detail(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, logistica
as $$
begin
  return logistica.get_receipt_detail(p_payload);
end;
$$;

grant execute on function public.list_receipt_headers(jsonb) to authenticated;
grant execute on function public.get_receipt_detail(jsonb) to authenticated;
