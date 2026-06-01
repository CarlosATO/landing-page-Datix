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

create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  code text not null,
  name text not null,
  description text,
  status text not null default 'active',
  start_date date,
  expected_end_date date,
  real_end_date date,
  budget_amount numeric(14,2),
  address text,
  city text,
  region text,
  responsible_user_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint projects_status_check check (status in ('planned', 'active', 'paused', 'completed', 'cancelled'))
);

alter table public.projects add column if not exists company_id uuid;
alter table public.projects add column if not exists code text;
alter table public.projects add column if not exists name text;
alter table public.projects add column if not exists description text;
alter table public.projects add column if not exists status text;
alter table public.projects add column if not exists start_date date;
alter table public.projects add column if not exists expected_end_date date;
alter table public.projects add column if not exists real_end_date date;
alter table public.projects add column if not exists budget_amount numeric(14,2);
alter table public.projects add column if not exists address text;
alter table public.projects add column if not exists city text;
alter table public.projects add column if not exists region text;
alter table public.projects add column if not exists responsible_user_id uuid;
alter table public.projects add column if not exists metadata jsonb;
alter table public.projects add column if not exists is_active boolean;
alter table public.projects add column if not exists created_at timestamptz;
alter table public.projects add column if not exists updated_at timestamptz;
alter table public.projects add column if not exists created_by uuid;
alter table public.projects add column if not exists updated_by uuid;

alter table public.projects alter column status set default 'active';
alter table public.projects alter column metadata set default '{}'::jsonb;
alter table public.projects alter column is_active set default true;
alter table public.projects alter column created_at set default now();
alter table public.projects alter column updated_at set default now();

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'projects_status_check'
  ) then
    alter table public.projects
      add constraint projects_status_check
      check (status in ('planned', 'active', 'paused', 'completed', 'cancelled'));
  end if;
end $$;

do $$
declare
  v_duplicate_groups integer;
begin
  select count(*) into v_duplicate_groups
  from (
    select 1
    from public.projects
    group by company_id, code
    having count(*) > 1
  ) dupes;

  if v_duplicate_groups = 0 then
    create unique index if not exists projects_company_code_key_idx
      on public.projects (company_id, code);
  else
    raise notice 'Skipping projects unique index due to % duplicate groups', v_duplicate_groups;
  end if;
end $$;

comment on table public.projects is 'Maestro transversal de Datix. No pertenece a un módulo específico y debe ser reutilizado por Logística, Construcción, Adquisiciones y futuros módulos.';

create table if not exists public.contractors (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  tax_id text,
  business_name text not null,
  trade_name text,
  contact_name text,
  phone text,
  email text,
  address text,
  city text,
  region text,
  status text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint contractors_status_check check (status in ('active', 'inactive', 'blocked'))
);

alter table public.contractors add column if not exists company_id uuid;
alter table public.contractors add column if not exists tax_id text;
alter table public.contractors add column if not exists business_name text;
alter table public.contractors add column if not exists trade_name text;
alter table public.contractors add column if not exists contact_name text;
alter table public.contractors add column if not exists phone text;
alter table public.contractors add column if not exists email text;
alter table public.contractors add column if not exists address text;
alter table public.contractors add column if not exists city text;
alter table public.contractors add column if not exists region text;
alter table public.contractors add column if not exists status text;
alter table public.contractors add column if not exists metadata jsonb;
alter table public.contractors add column if not exists is_active boolean;
alter table public.contractors add column if not exists created_at timestamptz;
alter table public.contractors add column if not exists updated_at timestamptz;
alter table public.contractors add column if not exists created_by uuid;
alter table public.contractors add column if not exists updated_by uuid;

alter table public.contractors alter column status set default 'active';
alter table public.contractors alter column metadata set default '{}'::jsonb;
alter table public.contractors alter column is_active set default true;
alter table public.contractors alter column created_at set default now();
alter table public.contractors alter column updated_at set default now();

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'contractors_status_check'
  ) then
    alter table public.contractors
      add constraint contractors_status_check
      check (status in ('active', 'inactive', 'blocked'));
  end if;
end $$;

comment on table public.contractors is 'Maestro transversal de Datix. No pertenece a un módulo específico y debe ser reutilizado por Logística, Construcción, Adquisiciones y futuros módulos.';

create table if not exists public.workers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  contractor_id uuid references public.contractors(id) on delete set null,
  tax_id text,
  first_name text not null,
  last_name text not null,
  job_title text,
  phone text,
  email text,
  status text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint workers_status_check check (status in ('active', 'inactive', 'blocked'))
);

alter table public.workers add column if not exists company_id uuid;
alter table public.workers add column if not exists contractor_id uuid;
alter table public.workers add column if not exists tax_id text;
alter table public.workers add column if not exists first_name text;
alter table public.workers add column if not exists last_name text;
alter table public.workers add column if not exists job_title text;
alter table public.workers add column if not exists phone text;
alter table public.workers add column if not exists email text;
alter table public.workers add column if not exists status text;
alter table public.workers add column if not exists metadata jsonb;
alter table public.workers add column if not exists is_active boolean;
alter table public.workers add column if not exists created_at timestamptz;
alter table public.workers add column if not exists updated_at timestamptz;
alter table public.workers add column if not exists created_by uuid;
alter table public.workers add column if not exists updated_by uuid;

alter table public.workers alter column status set default 'active';
alter table public.workers alter column metadata set default '{}'::jsonb;
alter table public.workers alter column is_active set default true;
alter table public.workers alter column created_at set default now();
alter table public.workers alter column updated_at set default now();

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'workers_status_check'
  ) then
    alter table public.workers
      add constraint workers_status_check
      check (status in ('active', 'inactive', 'blocked'));
  end if;
end $$;

comment on table public.workers is 'Maestro transversal de Datix. No pertenece a un módulo específico y debe ser reutilizado por Logística, Construcción, Adquisiciones y futuros módulos.';

create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  tax_id text,
  business_name text not null,
  trade_name text,
  contact_name text,
  phone text,
  email text,
  address text,
  city text,
  region text,
  status text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint suppliers_status_check check (status in ('active', 'inactive', 'blocked'))
);

alter table public.suppliers add column if not exists company_id uuid;
alter table public.suppliers add column if not exists tax_id text;
alter table public.suppliers add column if not exists business_name text;
alter table public.suppliers add column if not exists trade_name text;
alter table public.suppliers add column if not exists contact_name text;
alter table public.suppliers add column if not exists phone text;
alter table public.suppliers add column if not exists email text;
alter table public.suppliers add column if not exists address text;
alter table public.suppliers add column if not exists city text;
alter table public.suppliers add column if not exists region text;
alter table public.suppliers add column if not exists status text;
alter table public.suppliers add column if not exists metadata jsonb;
alter table public.suppliers add column if not exists is_active boolean;
alter table public.suppliers add column if not exists created_at timestamptz;
alter table public.suppliers add column if not exists updated_at timestamptz;
alter table public.suppliers add column if not exists created_by uuid;
alter table public.suppliers add column if not exists updated_by uuid;

alter table public.suppliers alter column status set default 'active';
alter table public.suppliers alter column metadata set default '{}'::jsonb;
alter table public.suppliers alter column is_active set default true;
alter table public.suppliers alter column created_at set default now();
alter table public.suppliers alter column updated_at set default now();

-- Legacy public.suppliers rows may still use name/rut/legal_name/business_name equivalents.
-- Safe backfill examples are intentionally not executed here:
-- update public.suppliers set tax_id = coalesce(tax_id, rut), business_name = coalesce(business_name, name, legal_name) where company_id = ...;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'suppliers_status_check'
  ) then
    alter table public.suppliers
      add constraint suppliers_status_check
      check (status in ('active', 'inactive', 'blocked'));
  end if;
end $$;

comment on table public.suppliers is 'Maestro transversal de Datix. No pertenece a un módulo específico y debe ser reutilizado por Logística, Construcción, Adquisiciones y futuros módulos.';

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

create or replace function public.can_manage_shared_operational_masters(p_company_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select case
    when p_company_id is null or auth.uid() is null then false
    when public.is_owner(p_company_id) then true
    when public.has_module_access(p_company_id, 'logistica') and public.has_role(p_company_id, 'ADMIN_LOGISTICA', 'logistica') then true
    when public.has_module_access(p_company_id, 'adquisiciones') and public.has_role(p_company_id, 'ADMIN_ADQUISICIONES', 'adquisiciones') then true
    when public.has_module_access(p_company_id, 'construccion') and public.has_role(p_company_id, 'ADMIN_CONSTRUCCION', 'construccion') then true
    else false
  end;
$$;

alter table public.projects enable row level security;
alter table public.contractors enable row level security;
alter table public.workers enable row level security;
alter table public.suppliers enable row level security;

drop policy if exists projects_select_company on public.projects;
create policy projects_select_company
on public.projects
for select
using (public.has_company_access(company_id));

drop policy if exists projects_insert_company on public.projects;
create policy projects_insert_company
on public.projects
for insert
with check (public.can_manage_shared_operational_masters(company_id));

drop policy if exists projects_update_company on public.projects;
create policy projects_update_company
on public.projects
for update
using (public.can_manage_shared_operational_masters(company_id))
with check (public.can_manage_shared_operational_masters(company_id));

drop policy if exists contractors_select_company on public.contractors;
create policy contractors_select_company
on public.contractors
for select
using (public.has_company_access(company_id));

drop policy if exists contractors_insert_company on public.contractors;
create policy contractors_insert_company
on public.contractors
for insert
with check (public.can_manage_shared_operational_masters(company_id));

drop policy if exists contractors_update_company on public.contractors;
create policy contractors_update_company
on public.contractors
for update
using (public.can_manage_shared_operational_masters(company_id))
with check (public.can_manage_shared_operational_masters(company_id));

drop policy if exists workers_select_company on public.workers;
create policy workers_select_company
on public.workers
for select
using (public.has_company_access(company_id));

drop policy if exists workers_insert_company on public.workers;
create policy workers_insert_company
on public.workers
for insert
with check (public.can_manage_shared_operational_masters(company_id));

drop policy if exists workers_update_company on public.workers;
create policy workers_update_company
on public.workers
for update
using (public.can_manage_shared_operational_masters(company_id))
with check (public.can_manage_shared_operational_masters(company_id));

drop policy if exists suppliers_select_company on public.suppliers;
create policy suppliers_select_company
on public.suppliers
for select
using (public.has_company_access(company_id));

drop policy if exists suppliers_insert_company on public.suppliers;
create policy suppliers_insert_company
on public.suppliers
for insert
with check (public.can_manage_shared_operational_masters(company_id));

drop policy if exists suppliers_update_company on public.suppliers;
create policy suppliers_update_company
on public.suppliers
for update
using (public.can_manage_shared_operational_masters(company_id))
with check (public.can_manage_shared_operational_masters(company_id));

do $$
declare
  v_duplicate_groups integer;
begin
  select count(*) into v_duplicate_groups
  from (
    select 1
    from public.contractors
    where tax_id is not null
    group by company_id, tax_id
    having count(*) > 1
  ) dupes;

  if v_duplicate_groups = 0 then
    create unique index if not exists contractors_company_tax_id_key_idx
      on public.contractors (company_id, tax_id)
      where tax_id is not null;
  else
    raise notice 'Skipping contractors tax_id unique index due to % duplicate groups', v_duplicate_groups;
  end if;
end $$;

do $$
declare
  v_duplicate_groups integer;
begin
  select count(*) into v_duplicate_groups
  from (
    select 1
    from public.workers
    where tax_id is not null
    group by company_id, tax_id
    having count(*) > 1
  ) dupes;

  if v_duplicate_groups = 0 then
    create unique index if not exists workers_company_tax_id_key_idx
      on public.workers (company_id, tax_id)
      where tax_id is not null;
  else
    raise notice 'Skipping workers tax_id unique index due to % duplicate groups', v_duplicate_groups;
  end if;
end $$;

do $$
declare
  v_duplicate_groups integer;
begin
  select count(*) into v_duplicate_groups
  from (
    select 1
    from public.suppliers
    where tax_id is not null
    group by company_id, tax_id
    having count(*) > 1
  ) dupes;

  if v_duplicate_groups = 0 then
    create unique index if not exists suppliers_company_tax_id_key_idx
      on public.suppliers (company_id, tax_id)
      where tax_id is not null;
  else
    raise notice 'Skipping suppliers tax_id unique index due to % duplicate groups', v_duplicate_groups;
  end if;
end $$;

create index if not exists projects_company_id_idx on public.projects (company_id);
create index if not exists projects_company_is_active_idx on public.projects (company_id, is_active);
create index if not exists projects_company_status_idx on public.projects (company_id, status);
create index if not exists projects_responsible_user_id_idx on public.projects (responsible_user_id);

create index if not exists contractors_company_id_idx on public.contractors (company_id);
create index if not exists contractors_company_is_active_idx on public.contractors (company_id, is_active);
create index if not exists contractors_company_status_idx on public.contractors (company_id, status);

create index if not exists workers_company_id_idx on public.workers (company_id);
create index if not exists workers_company_is_active_idx on public.workers (company_id, is_active);
create index if not exists workers_company_status_idx on public.workers (company_id, status);
create index if not exists workers_contractor_id_idx on public.workers (contractor_id);

create index if not exists suppliers_company_id_idx on public.suppliers (company_id);
create index if not exists suppliers_company_is_active_idx on public.suppliers (company_id, is_active);
create index if not exists suppliers_company_status_idx on public.suppliers (company_id, status);

grant select, insert, update on public.projects to authenticated;
grant select, insert, update on public.contractors to authenticated;
grant select, insert, update on public.workers to authenticated;
grant select, insert, update on public.suppliers to authenticated;

revoke all on public.projects from anon;
revoke all on public.contractors from anon;
revoke all on public.workers from anon;
revoke all on public.suppliers from anon;

drop trigger if exists trg_public_projects_updated_at on public.projects;
create trigger trg_public_projects_updated_at
before update on public.projects
for each row execute function public.set_updated_at();

drop trigger if exists trg_public_contractors_updated_at on public.contractors;
create trigger trg_public_contractors_updated_at
before update on public.contractors
for each row execute function public.set_updated_at();

drop trigger if exists trg_public_workers_updated_at on public.workers;
create trigger trg_public_workers_updated_at
before update on public.workers
for each row execute function public.set_updated_at();

drop trigger if exists trg_public_suppliers_updated_at on public.suppliers;
create trigger trg_public_suppliers_updated_at
before update on public.suppliers
for each row execute function public.set_updated_at();

drop trigger if exists trg_public_projects_audit on public.projects;
create trigger trg_public_projects_audit
after insert or update or delete on public.projects
for each row execute function public.audit_shared_master_change();

drop trigger if exists trg_public_contractors_audit on public.contractors;
create trigger trg_public_contractors_audit
after insert or update or delete on public.contractors
for each row execute function public.audit_shared_master_change();

drop trigger if exists trg_public_workers_audit on public.workers;
create trigger trg_public_workers_audit
after insert or update or delete on public.workers
for each row execute function public.audit_shared_master_change();

drop trigger if exists trg_public_suppliers_audit on public.suppliers;
create trigger trg_public_suppliers_audit
after insert or update or delete on public.suppliers
for each row execute function public.audit_shared_master_change();
