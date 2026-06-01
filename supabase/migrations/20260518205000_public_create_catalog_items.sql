create or replace function public.set_updated_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.audit_shared_master_change()
returns trigger
language plpgsql
security definer
set search_path = public
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

  insert into public.audit_log (
    company_id,
    user_id,
    action,
    entity_schema,
    entity_table,
    entity_id,
    old_data,
    new_data,
    metadata
  ) values (
    v_company_id,
    auth.uid(),
    lower(tg_op),
    tg_table_schema,
    tg_table_name,
    v_entity_id,
    v_old,
    v_new,
    jsonb_build_object('trigger', true, 'shared_master', true)
  );

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

create table if not exists public.catalog_categories (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  code text not null,
  name text not null,
  description text,
  category_type text not null default 'general',
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null
);

alter table public.catalog_categories add column if not exists company_id uuid;
alter table public.catalog_categories add column if not exists code text;
alter table public.catalog_categories add column if not exists name text;
alter table public.catalog_categories add column if not exists description text;
alter table public.catalog_categories add column if not exists category_type text;
alter table public.catalog_categories add column if not exists is_active boolean;
alter table public.catalog_categories add column if not exists metadata jsonb;
alter table public.catalog_categories add column if not exists created_at timestamptz;
alter table public.catalog_categories add column if not exists updated_at timestamptz;
alter table public.catalog_categories add column if not exists created_by uuid;
alter table public.catalog_categories add column if not exists updated_by uuid;

alter table public.catalog_categories alter column category_type set default 'general';
alter table public.catalog_categories alter column is_active set default true;
alter table public.catalog_categories alter column metadata set default '{}'::jsonb;
alter table public.catalog_categories alter column created_at set default now();
alter table public.catalog_categories alter column updated_at set default now();

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'catalog_categories_company_id_fkey'
  ) then
    alter table public.catalog_categories
      add constraint catalog_categories_company_id_fkey
      foreign key (company_id) references public.companies(id) on delete cascade;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'catalog_categories_created_by_fkey'
  ) then
    alter table public.catalog_categories
      add constraint catalog_categories_created_by_fkey
      foreign key (created_by) references auth.users(id) on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'catalog_categories_updated_by_fkey'
  ) then
    alter table public.catalog_categories
      add constraint catalog_categories_updated_by_fkey
      foreign key (updated_by) references auth.users(id) on delete set null;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'catalog_categories_type_check'
  ) then
    alter table public.catalog_categories
      add constraint catalog_categories_type_check
      check (category_type in ('material', 'service', 'expense', 'tool', 'equipment', 'general'));
  end if;
end $$;

do $$
declare
  v_duplicate_groups integer;
begin
  select count(*) into v_duplicate_groups
  from (
    select 1
    from public.catalog_categories
    group by company_id, code
    having count(*) > 1
  ) dupes;

  if v_duplicate_groups = 0 then
    create unique index if not exists catalog_categories_company_code_key_idx
      on public.catalog_categories (company_id, code);
  else
    raise notice 'Skipping catalog_categories unique index due to % duplicate groups', v_duplicate_groups;
  end if;
end $$;

comment on table public.catalog_categories is 'Catálogo transversal Datix para clasificar ítems, materiales, servicios y gastos compartidos por módulos.';

create table if not exists public.catalog_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  category_id uuid references public.catalog_categories(id) on delete set null,
  sku text not null,
  name text not null,
  description text,
  item_kind text not null,
  unit text not null default 'UN',
  is_stockable boolean not null default false,
  is_purchasable boolean not null default true,
  is_service boolean not null default false,
  is_expense boolean not null default false,
  is_returnable boolean not null default false,
  tracks_lot boolean not null default false,
  tracks_serial boolean not null default false,
  tracks_expiration boolean not null default false,
  default_tax_rate numeric(6,4),
  default_cost numeric(14,4),
  metadata jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null
);

alter table public.catalog_items add column if not exists company_id uuid;
alter table public.catalog_items add column if not exists category_id uuid;
alter table public.catalog_items add column if not exists sku text;
alter table public.catalog_items add column if not exists name text;
alter table public.catalog_items add column if not exists description text;
alter table public.catalog_items add column if not exists item_kind text;
alter table public.catalog_items add column if not exists unit text;
alter table public.catalog_items add column if not exists is_stockable boolean;
alter table public.catalog_items add column if not exists is_purchasable boolean;
alter table public.catalog_items add column if not exists is_service boolean;
alter table public.catalog_items add column if not exists is_expense boolean;
alter table public.catalog_items add column if not exists is_returnable boolean;
alter table public.catalog_items add column if not exists tracks_lot boolean;
alter table public.catalog_items add column if not exists tracks_serial boolean;
alter table public.catalog_items add column if not exists tracks_expiration boolean;
alter table public.catalog_items add column if not exists default_tax_rate numeric(6,4);
alter table public.catalog_items add column if not exists default_cost numeric(14,4);
alter table public.catalog_items add column if not exists metadata jsonb;
alter table public.catalog_items add column if not exists is_active boolean;
alter table public.catalog_items add column if not exists created_at timestamptz;
alter table public.catalog_items add column if not exists updated_at timestamptz;
alter table public.catalog_items add column if not exists created_by uuid;
alter table public.catalog_items add column if not exists updated_by uuid;

alter table public.catalog_items alter column unit set default 'UN';
alter table public.catalog_items alter column is_stockable set default false;
alter table public.catalog_items alter column is_purchasable set default true;
alter table public.catalog_items alter column is_service set default false;
alter table public.catalog_items alter column is_expense set default false;
alter table public.catalog_items alter column is_returnable set default false;
alter table public.catalog_items alter column tracks_lot set default false;
alter table public.catalog_items alter column tracks_serial set default false;
alter table public.catalog_items alter column tracks_expiration set default false;
alter table public.catalog_items alter column metadata set default '{}'::jsonb;
alter table public.catalog_items alter column is_active set default true;
alter table public.catalog_items alter column created_at set default now();
alter table public.catalog_items alter column updated_at set default now();

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'catalog_items_company_id_fkey'
  ) then
    alter table public.catalog_items
      add constraint catalog_items_company_id_fkey
      foreign key (company_id) references public.companies(id) on delete cascade;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'catalog_items_category_id_fkey'
  ) then
    alter table public.catalog_items
      add constraint catalog_items_category_id_fkey
      foreign key (category_id) references public.catalog_categories(id) on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'catalog_items_created_by_fkey'
  ) then
    alter table public.catalog_items
      add constraint catalog_items_created_by_fkey
      foreign key (created_by) references auth.users(id) on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'catalog_items_updated_by_fkey'
  ) then
    alter table public.catalog_items
      add constraint catalog_items_updated_by_fkey
      foreign key (updated_by) references auth.users(id) on delete set null;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'catalog_items_kind_check'
  ) then
    alter table public.catalog_items
      add constraint catalog_items_kind_check
      check (
        item_kind in ('physical', 'service', 'expense', 'tool', 'equipment', 'other')
        and (default_tax_rate is null or default_tax_rate >= 0)
        and (default_cost is null or default_cost >= 0)
      );
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'catalog_items_service_flags_check'
  ) then
    alter table public.catalog_items
      add constraint catalog_items_service_flags_check
      check (
        not (is_service and is_expense)
        and (
          item_kind in ('physical', 'tool', 'equipment', 'other')
          or (item_kind = 'service' and is_service = true and is_stockable = false and is_expense = false)
          or (item_kind = 'expense' and is_expense = true and is_stockable = false and is_service = false)
        )
      );
  end if;
end $$;

do $$
declare
  v_duplicate_groups integer;
begin
  select count(*) into v_duplicate_groups
  from (
    select 1
    from public.catalog_items
    group by company_id, sku
    having count(*) > 1
  ) dupes;

  if v_duplicate_groups = 0 then
    create unique index if not exists catalog_items_company_sku_key_idx
      on public.catalog_items (company_id, sku);
  else
    raise notice 'Skipping catalog_items unique index due to % duplicate groups', v_duplicate_groups;
  end if;
end $$;

comment on table public.catalog_items is 'Catálogo transversal Datix para materiales, servicios, gastos, herramientas y equipos compartidos por Logística, Adquisiciones y Construcción.';

alter table logistica.items add column if not exists catalog_item_id uuid references public.catalog_items(id) on delete set null;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'items_catalog_item_id_fkey'
  ) then
    alter table logistica.items
      add constraint items_catalog_item_id_fkey
      foreign key (catalog_item_id) references public.catalog_items(id) on delete set null;
  end if;
end $$;

create index if not exists logistica_items_company_catalog_item_idx
  on logistica.items (company_id, catalog_item_id);

alter table public.catalog_categories enable row level security;
alter table public.catalog_items enable row level security;

drop policy if exists catalog_categories_select_company on public.catalog_categories;
create policy catalog_categories_select_company
on public.catalog_categories
for select
using (public.has_company_access(company_id));

drop policy if exists catalog_categories_manage_company on public.catalog_categories;
create policy catalog_categories_manage_company
on public.catalog_categories
for insert
with check (
  public.is_owner(company_id)
  or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica')
  or public.has_role(company_id, 'ADMIN_ADQUISICIONES', 'adquisiciones')
  or public.has_role(company_id, 'ADMIN_CONSTRUCCION', 'construccion')
);

drop policy if exists catalog_categories_update_company on public.catalog_categories;
create policy catalog_categories_update_company
on public.catalog_categories
for update
using (
  public.is_owner(company_id)
  or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica')
  or public.has_role(company_id, 'ADMIN_ADQUISICIONES', 'adquisiciones')
  or public.has_role(company_id, 'ADMIN_CONSTRUCCION', 'construccion')
)
with check (
  public.is_owner(company_id)
  or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica')
  or public.has_role(company_id, 'ADMIN_ADQUISICIONES', 'adquisiciones')
  or public.has_role(company_id, 'ADMIN_CONSTRUCCION', 'construccion')
);

drop policy if exists catalog_items_select_company on public.catalog_items;
create policy catalog_items_select_company
on public.catalog_items
for select
using (public.has_company_access(company_id));

drop policy if exists catalog_items_manage_company on public.catalog_items;
create policy catalog_items_manage_company
on public.catalog_items
for insert
with check (
  public.is_owner(company_id)
  or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica')
  or public.has_role(company_id, 'ADMIN_ADQUISICIONES', 'adquisiciones')
  or public.has_role(company_id, 'ADMIN_CONSTRUCCION', 'construccion')
);

drop policy if exists catalog_items_update_company on public.catalog_items;
create policy catalog_items_update_company
on public.catalog_items
for update
using (
  public.is_owner(company_id)
  or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica')
  or public.has_role(company_id, 'ADMIN_ADQUISICIONES', 'adquisiciones')
  or public.has_role(company_id, 'ADMIN_CONSTRUCCION', 'construccion')
)
with check (
  public.is_owner(company_id)
  or public.has_role(company_id, 'ADMIN_LOGISTICA', 'logistica')
  or public.has_role(company_id, 'ADMIN_ADQUISICIONES', 'adquisiciones')
  or public.has_role(company_id, 'ADMIN_CONSTRUCCION', 'construccion')
);

grant select, insert, update on public.catalog_categories to authenticated;
grant select, insert, update on public.catalog_items to authenticated;

revoke all on public.catalog_categories from anon;
revoke all on public.catalog_items from anon;

drop trigger if exists trg_public_catalog_categories_updated_at on public.catalog_categories;
create trigger trg_public_catalog_categories_updated_at
before update on public.catalog_categories
for each row execute function public.set_updated_at();

drop trigger if exists trg_public_catalog_items_updated_at on public.catalog_items;
create trigger trg_public_catalog_items_updated_at
before update on public.catalog_items
for each row execute function public.set_updated_at();

drop trigger if exists trg_public_catalog_categories_audit on public.catalog_categories;
create trigger trg_public_catalog_categories_audit
after insert or update or delete on public.catalog_categories
for each row execute function public.audit_shared_master_change();

drop trigger if exists trg_public_catalog_items_audit on public.catalog_items;
create trigger trg_public_catalog_items_audit
after insert or update or delete on public.catalog_items
for each row execute function public.audit_shared_master_change();
