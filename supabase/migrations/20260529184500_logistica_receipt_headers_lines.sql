-- 20260529184500_logistica_receipt_headers_lines.sql
-- Migracion B: encabezados/detalle de recepcion y trazabilidad en stock.

create table if not exists logistica.receipt_headers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  origin_type text not null default 'manual',
  origin_document_id uuid,
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  document_type text,
  document_number text,
  document_date date,
  receipt_date timestamptz not null default now(),
  cost_center_id uuid not null references public.cost_centers(id) on delete restrict,
  warehouse_id uuid not null references logistica.warehouses(id) on delete restrict,
  location_id uuid not null references logistica.locations(id) on delete restrict,
  status text not null default 'draft',
  notes text,
  subtotal_cost numeric(14,4) not null default 0,
  total_cost numeric(14,4) not null default 0,
  receipt_reference text not null,
  idempotency_key text,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  posted_by uuid references auth.users(id) on delete set null,
  posted_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint receipt_headers_origin_type_check check (origin_type in ('manual', 'purchase_order')),
  constraint receipt_headers_status_check check (status in ('draft', 'posted', 'cancelled'))
);

create table if not exists logistica.receipt_lines (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  receipt_id uuid not null references logistica.receipt_headers(id) on delete cascade,
  line_number integer not null,
  item_id uuid not null references logistica.items(id) on delete restrict,
  origin_document_line_id uuid,
  ordered_quantity_snapshot numeric(14,3),
  pending_quantity_snapshot numeric(14,3),
  received_quantity numeric(14,3) not null,
  unit_cost numeric(14,4) not null,
  total_cost numeric(14,4) not null,
  lot_code text,
  serial_number text,
  expiration_date date,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint receipt_lines_quantity_check check (received_quantity > 0),
  constraint receipt_lines_unit_cost_check check (unit_cost >= 0),
  constraint receipt_lines_total_cost_check check (total_cost >= 0),
  constraint receipt_lines_line_number_check check (line_number > 0),
  constraint receipt_lines_unique_line unique (receipt_id, line_number)
);

alter table logistica.stock_movements
  add column if not exists receipt_id uuid;

alter table logistica.stock_movements
  add column if not exists receipt_line_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'stock_movements_receipt_id_fkey'
  ) then
    alter table logistica.stock_movements
      add constraint stock_movements_receipt_id_fkey
      foreign key (receipt_id) references logistica.receipt_headers(id) on delete set null;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'stock_movements_receipt_line_id_fkey'
  ) then
    alter table logistica.stock_movements
      add constraint stock_movements_receipt_line_id_fkey
      foreign key (receipt_line_id) references logistica.receipt_lines(id) on delete set null;
  end if;
end $$;

create index if not exists receipt_headers_company_status_idx
  on logistica.receipt_headers (company_id, status);

create index if not exists receipt_headers_company_date_idx
  on logistica.receipt_headers (company_id, receipt_date desc);

create index if not exists receipt_headers_company_origin_idx
  on logistica.receipt_headers (company_id, origin_type, origin_document_id);

create unique index if not exists receipt_headers_company_reference_uk
  on logistica.receipt_headers (company_id, receipt_reference);

create index if not exists receipt_lines_receipt_idx
  on logistica.receipt_lines (receipt_id);

create index if not exists receipt_lines_item_idx
  on logistica.receipt_lines (item_id);

create index if not exists receipt_lines_origin_line_idx
  on logistica.receipt_lines (origin_document_line_id);

create index if not exists stock_movements_receipt_idx
  on logistica.stock_movements (receipt_id);

create index if not exists stock_movements_receipt_line_idx
  on logistica.stock_movements (receipt_line_id);

alter table logistica.receipt_headers enable row level security;
alter table logistica.receipt_lines enable row level security;

drop policy if exists receipt_headers_select_company on logistica.receipt_headers;
create policy receipt_headers_select_company
on logistica.receipt_headers
for select
using (public.has_company_access(company_id) and public.has_module_access(company_id, 'logistica'));

drop policy if exists receipt_headers_insert_company on logistica.receipt_headers;
create policy receipt_headers_insert_company
on logistica.receipt_headers
for insert
with check (false);

drop policy if exists receipt_headers_update_company on logistica.receipt_headers;
create policy receipt_headers_update_company
on logistica.receipt_headers
for update
using (false)
with check (false);

drop policy if exists receipt_headers_delete_company on logistica.receipt_headers;
create policy receipt_headers_delete_company
on logistica.receipt_headers
for delete
using (false);

drop policy if exists receipt_lines_select_company on logistica.receipt_lines;
create policy receipt_lines_select_company
on logistica.receipt_lines
for select
using (public.has_company_access(company_id) and public.has_module_access(company_id, 'logistica'));

drop policy if exists receipt_lines_insert_company on logistica.receipt_lines;
create policy receipt_lines_insert_company
on logistica.receipt_lines
for insert
with check (false);

drop policy if exists receipt_lines_update_company on logistica.receipt_lines;
create policy receipt_lines_update_company
on logistica.receipt_lines
for update
using (false)
with check (false);

drop policy if exists receipt_lines_delete_company on logistica.receipt_lines;
create policy receipt_lines_delete_company
on logistica.receipt_lines
for delete
using (false);

comment on column logistica.receipt_headers.origin_type is 'Preparado para flujo manual y purchase_order. La integracion OC no se activa en esta migracion.';
comment on column logistica.receipt_headers.origin_document_id is 'Reservado para la cabecera de OC en el futuro.';
comment on column logistica.receipt_lines.origin_document_line_id is 'Reservado para la linea de OC en el futuro.';

grant select on logistica.receipt_headers to authenticated;
grant select on logistica.receipt_lines to authenticated;
