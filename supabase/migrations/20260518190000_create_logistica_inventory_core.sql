create table if not exists logistica.item_lots (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  item_id uuid not null references logistica.items(id) on delete cascade,
  lot_code text not null,
  manufacture_date date,
  expiration_date date,
  supplier_name text,
  source_module text,
  source_document_type text,
  source_document_id uuid,
  unit_cost numeric(14,4),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint item_lots_company_item_lot_key unique (company_id, item_id, lot_code)
);

comment on table logistica.item_lots is 'Lotes del módulo Logística. company_id mantiene aislamiento multi-tenant.';

create table if not exists logistica.item_serials (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  item_id uuid not null references logistica.items(id) on delete cascade,
  serial_number text not null,
  status text not null default 'available',
  current_warehouse_id uuid references logistica.warehouses(id) on delete set null,
  current_location_id uuid references logistica.locations(id) on delete set null,
  current_custodian_type text,
  current_custodian_id uuid,
  current_project_id uuid,
  source_module text,
  source_document_type text,
  source_document_id uuid,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint item_serials_company_item_serial_key unique (company_id, item_id, serial_number),
  constraint item_serials_status_check check (status in ('available', 'assigned', 'in_use', 'maintenance', 'lost', 'damaged', 'retired'))
);

comment on table logistica.item_serials is 'Seriales del módulo Logística. El estado operacional se resuelve por movimientos y asignaciones.';

create table if not exists logistica.stock_movements (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  item_id uuid not null references logistica.items(id) on delete cascade,
  lot_id uuid references logistica.item_lots(id) on delete set null,
  serial_id uuid references logistica.item_serials(id) on delete set null,
  movement_type text not null,
  movement_reason text,
  quantity numeric(14,3) not null,
  unit_cost numeric(14,4),
  total_cost numeric(14,4),
  from_warehouse_id uuid references logistica.warehouses(id) on delete set null,
  from_location_id uuid references logistica.locations(id) on delete set null,
  to_warehouse_id uuid references logistica.warehouses(id) on delete set null,
  to_location_id uuid references logistica.locations(id) on delete set null,
  source_module text,
  source_document_type text,
  source_document_id uuid,
  target_module text,
  target_document_type text,
  target_document_id uuid,
  reference_number text,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  constraint stock_movements_quantity_check check (quantity <> 0),
  constraint stock_movements_type_check check (
    movement_type in (
      'RECEIPT',
      'TRANSFER_OUT',
      'TRANSFER_IN',
      'ISSUE',
      'RETURN',
      'CONSUMPTION',
      'ADJUSTMENT_POSITIVE',
      'ADJUSTMENT_NEGATIVE',
      'LOSS',
      'SCRAP',
      'ASSIGNMENT',
      'UNASSIGNMENT'
    )
  )
);

comment on table logistica.stock_movements is 'Ledger append-only de inventario. El stock futuro debe derivarse de movimientos, no de edición manual.';

create table if not exists logistica.stock_balances (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  item_id uuid not null references logistica.items(id) on delete cascade,
  lot_id uuid references logistica.item_lots(id) on delete set null,
  warehouse_id uuid not null references logistica.warehouses(id) on delete cascade,
  location_id uuid references logistica.locations(id) on delete set null,
  quantity_on_hand numeric(14,3) not null default 0,
  quantity_reserved numeric(14,3) not null default 0,
  average_unit_cost numeric(14,4),
  total_cost numeric(14,4),
  last_movement_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table logistica.stock_balances is 'Cache operacional de saldos. Debe recalcularse desde el ledger.';

create or replace function logistica.audit_insert_stock_movement()
returns trigger
language plpgsql
security definer
set search_path = logistica, public
as $$
begin
  insert into logistica.audit_log (
    company_id,
    user_id,
    action,
    entity_table,
    entity_id,
    new_data,
    metadata
  ) values (
    new.company_id,
    auth.uid(),
    'insert',
    tg_table_name,
    new.id,
    to_jsonb(new),
    jsonb_build_object('trigger', true, 'append_only', true)
  );

  return new;
end;
$$;

alter table logistica.item_lots enable row level security;
alter table logistica.item_serials enable row level security;
alter table logistica.stock_movements enable row level security;
alter table logistica.stock_balances enable row level security;

drop policy if exists item_lots_select_company on logistica.item_lots;
create policy item_lots_select_company
on logistica.item_lots
for select
using (public.has_company_access(company_id) and public.has_module_access(company_id, 'logistica'));

drop policy if exists item_lots_write_company on logistica.item_lots;
create policy item_lots_write_company
on logistica.item_lots
for insert
with check (
  public.has_company_access(company_id)
  and public.has_module_access(company_id, 'logistica')
  and (public.is_owner(company_id) or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica'))
);

drop policy if exists item_lots_update_company on logistica.item_lots;
create policy item_lots_update_company
on logistica.item_lots
for update
using (
  public.has_company_access(company_id)
  and public.has_module_access(company_id, 'logistica')
  and (public.is_owner(company_id) or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica'))
)
with check (
  public.has_company_access(company_id)
  and public.has_module_access(company_id, 'logistica')
  and (public.is_owner(company_id) or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica'))
);

drop policy if exists item_lots_delete_company on logistica.item_lots;
create policy item_lots_delete_company
on logistica.item_lots
for delete
using (
  public.has_company_access(company_id)
  and public.has_module_access(company_id, 'logistica')
  and (public.is_owner(company_id) or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica'))
);

drop policy if exists item_serials_select_company on logistica.item_serials;
create policy item_serials_select_company
on logistica.item_serials
for select
using (public.has_company_access(company_id) and public.has_module_access(company_id, 'logistica'));

drop policy if exists item_serials_write_company on logistica.item_serials;
create policy item_serials_write_company
on logistica.item_serials
for insert
with check (
  public.has_company_access(company_id)
  and public.has_module_access(company_id, 'logistica')
  and (public.is_owner(company_id) or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica'))
);

drop policy if exists item_serials_update_company on logistica.item_serials;
create policy item_serials_update_company
on logistica.item_serials
for update
using (
  public.has_company_access(company_id)
  and public.has_module_access(company_id, 'logistica')
  and (public.is_owner(company_id) or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica'))
)
with check (
  public.has_company_access(company_id)
  and public.has_module_access(company_id, 'logistica')
  and (public.is_owner(company_id) or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica'))
);

drop policy if exists item_serials_delete_company on logistica.item_serials;
create policy item_serials_delete_company
on logistica.item_serials
for delete
using (
  public.has_company_access(company_id)
  and public.has_module_access(company_id, 'logistica')
  and (public.is_owner(company_id) or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica'))
);

drop policy if exists stock_movements_select_company on logistica.stock_movements;
create policy stock_movements_select_company
on logistica.stock_movements
for select
using (
  public.has_company_access(company_id)
  and public.has_module_access(company_id, 'logistica')
  and (
    public.is_owner(company_id)
    or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica')
    or public.has_role(company_id, 'OPERARIO_LOGISTICA', 'logistica')
  )
);

drop policy if exists stock_movements_insert_company on logistica.stock_movements;
create policy stock_movements_insert_company
on logistica.stock_movements
for insert
with check (
  public.has_company_access(company_id)
  and public.has_module_access(company_id, 'logistica')
  and (
    public.is_owner(company_id)
    or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica')
    or public.has_role(company_id, 'OPERARIO_LOGISTICA', 'logistica')
  )
);

drop policy if exists stock_balances_select_company on logistica.stock_balances;
create policy stock_balances_select_company
on logistica.stock_balances
for select
using (public.has_company_access(company_id) and public.has_module_access(company_id, 'logistica'));

drop policy if exists stock_balances_write_company on logistica.stock_balances;
create policy stock_balances_write_company
on logistica.stock_balances
for insert
with check (
  public.has_company_access(company_id)
  and public.has_module_access(company_id, 'logistica')
  and (public.is_owner(company_id) or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica'))
);

drop policy if exists stock_balances_update_company on logistica.stock_balances;
create policy stock_balances_update_company
on logistica.stock_balances
for update
using (
  public.has_company_access(company_id)
  and public.has_module_access(company_id, 'logistica')
  and (public.is_owner(company_id) or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica'))
)
with check (
  public.has_company_access(company_id)
  and public.has_module_access(company_id, 'logistica')
  and (public.is_owner(company_id) or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica'))
);

drop policy if exists stock_balances_delete_company on logistica.stock_balances;
create policy stock_balances_delete_company
on logistica.stock_balances
for delete
using (
  public.has_company_access(company_id)
  and public.has_module_access(company_id, 'logistica')
  and (public.is_owner(company_id) or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica'))
);

drop policy if exists audit_log_select_company on logistica.audit_log;
create policy audit_log_select_company
on logistica.audit_log
for select
using (
  company_id is not null
  and public.has_company_access(company_id)
  and public.has_module_access(company_id, 'logistica')
  and (public.is_owner(company_id) or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica'))
);

create unique index if not exists item_lots_company_item_lot_key_idx on logistica.item_lots (company_id, item_id, lot_code);
create unique index if not exists item_serials_company_item_serial_key_idx on logistica.item_serials (company_id, item_id, serial_number);
create unique index if not exists stock_balances_company_item_warehouse_location_key_idx
  on logistica.stock_balances (
    company_id,
    item_id,
    coalesce(lot_id, '00000000-0000-0000-0000-000000000000'::uuid),
    warehouse_id,
    coalesce(location_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );

create index if not exists item_lots_company_id_idx on logistica.item_lots (company_id);
create index if not exists item_lots_item_id_idx on logistica.item_lots (item_id);
create index if not exists item_lots_expiration_date_idx on logistica.item_lots (company_id, expiration_date);
create index if not exists item_lots_source_document_idx on logistica.item_lots (source_module, source_document_id);

create index if not exists item_serials_company_id_idx on logistica.item_serials (company_id);
create index if not exists item_serials_item_id_idx on logistica.item_serials (item_id);
create index if not exists item_serials_current_warehouse_location_idx on logistica.item_serials (current_warehouse_id, current_location_id);
create index if not exists item_serials_status_idx on logistica.item_serials (status);
create index if not exists item_serials_source_document_idx on logistica.item_serials (source_module, source_document_id);

create index if not exists stock_movements_company_id_idx on logistica.stock_movements (company_id);
create index if not exists stock_movements_item_id_idx on logistica.stock_movements (item_id);
create index if not exists stock_movements_lot_id_idx on logistica.stock_movements (lot_id);
create index if not exists stock_movements_serial_id_idx on logistica.stock_movements (serial_id);
create index if not exists stock_movements_movement_type_idx on logistica.stock_movements (movement_type);
create index if not exists stock_movements_created_at_idx on logistica.stock_movements (created_at desc);
create index if not exists stock_movements_source_idx on logistica.stock_movements (source_module, source_document_id);
create index if not exists stock_movements_target_idx on logistica.stock_movements (target_module, target_document_id);

create index if not exists stock_balances_company_id_idx on logistica.stock_balances (company_id);
create index if not exists stock_balances_item_id_idx on logistica.stock_balances (item_id);
create index if not exists stock_balances_lot_id_idx on logistica.stock_balances (lot_id);
create index if not exists stock_balances_warehouse_location_idx on logistica.stock_balances (warehouse_id, location_id);

grant usage on schema logistica to authenticated;
grant select, insert, update, delete on logistica.item_lots to authenticated;
grant select, insert, update, delete on logistica.item_serials to authenticated;
grant select, insert on logistica.stock_movements to authenticated;
grant select, insert, update, delete on logistica.stock_balances to authenticated;
grant select on logistica.audit_log to authenticated;

drop trigger if exists trg_logistica_item_lots_updated_at on logistica.item_lots;
create trigger trg_logistica_item_lots_updated_at
before update on logistica.item_lots
for each row execute function logistica.set_updated_at();

drop trigger if exists trg_logistica_item_serials_updated_at on logistica.item_serials;
create trigger trg_logistica_item_serials_updated_at
before update on logistica.item_serials
for each row execute function logistica.set_updated_at();

drop trigger if exists trg_logistica_stock_balances_updated_at on logistica.stock_balances;
create trigger trg_logistica_stock_balances_updated_at
before update on logistica.stock_balances
for each row execute function logistica.set_updated_at();

drop trigger if exists trg_logistica_item_lots_audit on logistica.item_lots;
create trigger trg_logistica_item_lots_audit
after insert or update or delete on logistica.item_lots
for each row execute function logistica.audit_row_change();

drop trigger if exists trg_logistica_item_serials_audit on logistica.item_serials;
create trigger trg_logistica_item_serials_audit
after insert or update or delete on logistica.item_serials
for each row execute function logistica.audit_row_change();

drop trigger if exists trg_logistica_stock_balances_audit on logistica.stock_balances;
create trigger trg_logistica_stock_balances_audit
after insert or update or delete on logistica.stock_balances
for each row execute function logistica.audit_row_change();

drop trigger if exists trg_logistica_stock_movements_audit_insert on logistica.stock_movements;
create trigger trg_logistica_stock_movements_audit_insert
after insert on logistica.stock_movements
for each row execute function logistica.audit_insert_stock_movement();

create or replace view logistica.v_kardex_movements as
select
  sm.id,
  sm.company_id,
  i.name as item_name,
  i.sku,
  fw.name as from_warehouse_name,
  fl.name as from_location_name,
  tw.name as to_warehouse_name,
  tl.name as to_location_name,
  lot.lot_code,
  ser.serial_number,
  sm.movement_type,
  sm.movement_reason,
  sm.quantity,
  sm.unit_cost,
  sm.total_cost,
  sm.created_at,
  sm.created_by,
  sm.source_module,
  sm.source_document_type,
  sm.source_document_id,
  sm.target_module,
  sm.target_document_type,
  sm.target_document_id,
  sm.reference_number,
  sm.notes
from logistica.stock_movements sm
join logistica.items i on i.id = sm.item_id
left join logistica.item_lots lot on lot.id = sm.lot_id
left join logistica.item_serials ser on ser.id = sm.serial_id
left join logistica.warehouses fw on fw.id = sm.from_warehouse_id
left join logistica.locations fl on fl.id = sm.from_location_id
left join logistica.warehouses tw on tw.id = sm.to_warehouse_id
left join logistica.locations tl on tl.id = sm.to_location_id;

grant select on logistica.v_kardex_movements to authenticated;
