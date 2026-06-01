create schema if not exists logistica;

comment on schema logistica is 'Schema funcional del módulo Logística. El aislamiento multi-tenant se mantiene por company_id.';

create or replace function logistica.set_updated_at()
returns trigger
language plpgsql
security definer
set search_path = logistica, public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create table if not exists logistica.warehouses (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  code text not null,
  name text not null,
  description text,
  warehouse_type text not null default 'main',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint warehouses_company_code_key unique (company_id, code),
  constraint warehouses_type_check check (warehouse_type in ('main', 'project', 'mobile', 'temporary', 'external'))
);

comment on table logistica.warehouses is 'Bodegas del módulo Logística. company_id mantiene aislamiento multi-tenant.';

create table if not exists logistica.locations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  warehouse_id uuid not null references logistica.warehouses(id) on delete cascade,
  code text not null,
  name text not null,
  description text,
  location_type text not null default 'rack',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint locations_company_warehouse_code_key unique (company_id, warehouse_id, code),
  constraint locations_type_check check (location_type in ('rack', 'shelf', 'zone', 'floor', 'vehicle', 'container', 'other'))
);

comment on table logistica.locations is 'Ubicaciones del módulo Logística. El stock futuro debe basarse en movimientos, no edición manual.';

create table if not exists logistica.item_categories (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint item_categories_company_name_key unique (company_id, name)
);

comment on table logistica.item_categories is 'Categorías maestras de ítems para Logística.';

create table if not exists logistica.items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  sku text not null,
  name text not null,
  description text,
  item_type text not null,
  category_id uuid references logistica.item_categories(id) on delete set null,
  unit text not null default 'UN',
  tracks_serial boolean not null default false,
  tracks_lot boolean not null default false,
  tracks_expiration boolean not null default false,
  is_returnable boolean not null default false,
  min_stock numeric(14,3) not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint items_company_sku_key unique (company_id, sku),
  constraint items_type_check check (item_type in ('consumable', 'tool', 'equipment', 'service'))
);

comment on table logistica.items is 'Ítems del módulo Logística. El control de stock futuro debe salir de ledger/movimientos.';

create table if not exists logistica.audit_log (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references public.companies(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_table text not null,
  entity_id uuid,
  old_data jsonb,
  new_data jsonb,
  metadata jsonb,
  created_at timestamptz not null default now()
);

comment on table logistica.audit_log is 'Auditoría del módulo Logística.';

create or replace function logistica.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = logistica, public
as $$
declare
  v_company_id uuid;
  v_entity_id uuid;
  v_old jsonb;
  v_new jsonb;
begin
  if tg_op = 'INSERT' then
    v_company_id := new.company_id;
    v_entity_id := new.id;
    v_new := to_jsonb(new);
  elsif tg_op = 'UPDATE' then
    v_company_id := coalesce(new.company_id, old.company_id);
    v_entity_id := coalesce(new.id, old.id);
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
  else
    v_company_id := old.company_id;
    v_entity_id := old.id;
    v_old := to_jsonb(old);
  end if;

  insert into logistica.audit_log (
    company_id,
    user_id,
    action,
    entity_table,
    entity_id,
    old_data,
    new_data,
    metadata
  ) values (
    v_company_id,
    auth.uid(),
    lower(tg_op),
    tg_table_name,
    v_entity_id,
    v_old,
    v_new,
    jsonb_build_object('trigger', true)
  );

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

create or replace function logistica.assert_logistica_access(p_company_id uuid, p_required_role text default null)
returns boolean
language plpgsql
security definer
set search_path = logistica, public
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if not public.has_company_access(p_company_id) then
    raise exception 'forbidden';
  end if;

  if not public.has_module_access(p_company_id, 'logistica') then
    raise exception 'module access required';
  end if;

  if p_required_role is not null then
    if not (public.is_owner(p_company_id) or public.has_role(p_company_id, p_required_role, 'logistica')) then
      raise exception 'insufficient role';
    end if;
  end if;

  return true;
end;
$$;

alter table logistica.warehouses enable row level security;
alter table logistica.locations enable row level security;
alter table logistica.item_categories enable row level security;
alter table logistica.items enable row level security;
alter table logistica.audit_log enable row level security;

drop policy if exists warehouses_select_company on logistica.warehouses;
create policy warehouses_select_company
on logistica.warehouses
for select
using (public.has_company_access(company_id) and public.has_module_access(company_id, 'logistica'));

drop policy if exists warehouses_insert_company on logistica.warehouses;
create policy warehouses_insert_company
on logistica.warehouses
for insert
with check (
  public.has_company_access(company_id)
  and public.has_module_access(company_id, 'logistica')
  and (public.is_owner(company_id) or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica'))
);

drop policy if exists warehouses_update_company on logistica.warehouses;
create policy warehouses_update_company
on logistica.warehouses
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

drop policy if exists warehouses_delete_company on logistica.warehouses;
create policy warehouses_delete_company
on logistica.warehouses
for delete
using (
  public.has_company_access(company_id)
  and public.has_module_access(company_id, 'logistica')
  and (public.is_owner(company_id) or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica'))
);

drop policy if exists locations_select_company on logistica.locations;
create policy locations_select_company
on logistica.locations
for select
using (public.has_company_access(company_id) and public.has_module_access(company_id, 'logistica'));

drop policy if exists locations_insert_company on logistica.locations;
create policy locations_insert_company
on logistica.locations
for insert
with check (
  public.has_company_access(company_id)
  and public.has_module_access(company_id, 'logistica')
  and (public.is_owner(company_id) or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica'))
);

drop policy if exists locations_update_company on logistica.locations;
create policy locations_update_company
on logistica.locations
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

drop policy if exists locations_delete_company on logistica.locations;
create policy locations_delete_company
on logistica.locations
for delete
using (
  public.has_company_access(company_id)
  and public.has_module_access(company_id, 'logistica')
  and (public.is_owner(company_id) or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica'))
);

drop policy if exists item_categories_select_company on logistica.item_categories;
create policy item_categories_select_company
on logistica.item_categories
for select
using (public.has_company_access(company_id) and public.has_module_access(company_id, 'logistica'));

drop policy if exists item_categories_insert_company on logistica.item_categories;
create policy item_categories_insert_company
on logistica.item_categories
for insert
with check (
  public.has_company_access(company_id)
  and public.has_module_access(company_id, 'logistica')
  and (public.is_owner(company_id) or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica'))
);

drop policy if exists item_categories_update_company on logistica.item_categories;
create policy item_categories_update_company
on logistica.item_categories
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

drop policy if exists item_categories_delete_company on logistica.item_categories;
create policy item_categories_delete_company
on logistica.item_categories
for delete
using (
  public.has_company_access(company_id)
  and public.has_module_access(company_id, 'logistica')
  and (public.is_owner(company_id) or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica'))
);

drop policy if exists items_select_company on logistica.items;
create policy items_select_company
on logistica.items
for select
using (public.has_company_access(company_id) and public.has_module_access(company_id, 'logistica'));

drop policy if exists items_insert_company on logistica.items;
create policy items_insert_company
on logistica.items
for insert
with check (
  public.has_company_access(company_id)
  and public.has_module_access(company_id, 'logistica')
  and (public.is_owner(company_id) or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica'))
);

drop policy if exists items_update_company on logistica.items;
create policy items_update_company
on logistica.items
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

drop policy if exists items_delete_company on logistica.items;
create policy items_delete_company
on logistica.items
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
  and (
    public.is_owner(company_id)
    or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica')
  )
);

create index if not exists warehouses_company_id_idx on logistica.warehouses (company_id);
create index if not exists warehouses_company_id_is_active_idx on logistica.warehouses (company_id, is_active);
create index if not exists locations_company_id_idx on logistica.locations (company_id);
create index if not exists locations_warehouse_id_idx on logistica.locations (warehouse_id);
create index if not exists locations_company_id_is_active_idx on logistica.locations (company_id, is_active);
create index if not exists item_categories_company_id_idx on logistica.item_categories (company_id);
create index if not exists item_categories_company_id_is_active_idx on logistica.item_categories (company_id, is_active);
create index if not exists items_company_id_idx on logistica.items (company_id);
create index if not exists items_company_id_sku_idx on logistica.items (company_id, sku);
create index if not exists items_company_id_item_type_idx on logistica.items (company_id, item_type);
create index if not exists items_company_id_is_active_idx on logistica.items (company_id, is_active);
create index if not exists audit_log_company_id_created_at_idx on logistica.audit_log (company_id, created_at desc);

grant usage on schema logistica to authenticated;
grant select, insert, update, delete on logistica.warehouses to authenticated;
grant select, insert, update, delete on logistica.locations to authenticated;
grant select, insert, update, delete on logistica.item_categories to authenticated;
grant select, insert, update, delete on logistica.items to authenticated;
grant select on logistica.audit_log to authenticated;
grant execute on function logistica.assert_logistica_access(uuid, text) to authenticated;

drop trigger if exists trg_logistica_warehouses_updated_at on logistica.warehouses;
create trigger trg_logistica_warehouses_updated_at
before update on logistica.warehouses
for each row execute function logistica.set_updated_at();

drop trigger if exists trg_logistica_locations_updated_at on logistica.locations;
create trigger trg_logistica_locations_updated_at
before update on logistica.locations
for each row execute function logistica.set_updated_at();

drop trigger if exists trg_logistica_item_categories_updated_at on logistica.item_categories;
create trigger trg_logistica_item_categories_updated_at
before update on logistica.item_categories
for each row execute function logistica.set_updated_at();

drop trigger if exists trg_logistica_items_updated_at on logistica.items;
create trigger trg_logistica_items_updated_at
before update on logistica.items
for each row execute function logistica.set_updated_at();

drop trigger if exists trg_logistica_warehouses_audit on logistica.warehouses;
create trigger trg_logistica_warehouses_audit
after insert or update or delete on logistica.warehouses
for each row execute function logistica.audit_row_change();

drop trigger if exists trg_logistica_locations_audit on logistica.locations;
create trigger trg_logistica_locations_audit
after insert or update or delete on logistica.locations
for each row execute function logistica.audit_row_change();

drop trigger if exists trg_logistica_item_categories_audit on logistica.item_categories;
create trigger trg_logistica_item_categories_audit
after insert or update or delete on logistica.item_categories
for each row execute function logistica.audit_row_change();

drop trigger if exists trg_logistica_items_audit on logistica.items;
create trigger trg_logistica_items_audit
after insert or update or delete on logistica.items
for each row execute function logistica.audit_row_change();
