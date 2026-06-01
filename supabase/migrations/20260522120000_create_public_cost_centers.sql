create table if not exists public.cost_centers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  code text not null,
  name text not null,
  description text,
  cost_center_type text not null,
  project_id uuid,
  is_default boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  constraint cost_centers_company_code_key unique (company_id, code),
  constraint cost_centers_type_check check (cost_center_type in ('project', 'office', 'administration', 'warehouse', 'maintenance', 'general_operation', 'other'))
);

comment on table public.cost_centers is 'Centro de costo transversal de Datix. Es la unidad financiera/operacional que absorbe costos de Logistica, Compras, Construccion y futuros modulos.';

alter table public.cost_centers add column if not exists project_id uuid;
alter table public.cost_centers add column if not exists is_default boolean;
alter table public.cost_centers add column if not exists is_active boolean;
alter table public.cost_centers add column if not exists created_at timestamptz;
alter table public.cost_centers add column if not exists updated_at timestamptz;
alter table public.cost_centers add column if not exists created_by uuid;
alter table public.cost_centers add column if not exists updated_by uuid;

alter table public.cost_centers alter column is_default set default false;
alter table public.cost_centers alter column is_active set default true;
alter table public.cost_centers alter column created_at set default now();
alter table public.cost_centers alter column updated_at set default now();

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'cost_centers_project_id_fkey'
  ) then
    alter table public.cost_centers
      add constraint cost_centers_project_id_fkey
      foreign key (project_id) references public.projects(id) on delete set null;
  end if;
end $$;

do $$
declare
  v_duplicate_groups integer;
begin
  select count(*) into v_duplicate_groups
  from (
    select 1
    from public.cost_centers
    where is_default = true
    group by company_id
    having count(*) > 1
  ) dupes;

  if v_duplicate_groups = 0 then
    create unique index if not exists cost_centers_company_default_key_idx
      on public.cost_centers (company_id)
      where is_default = true;
  else
    raise notice 'Skipping default cost center unique index due to % duplicate groups', v_duplicate_groups;
  end if;
end $$;

create index if not exists cost_centers_company_id_idx on public.cost_centers (company_id);
create index if not exists cost_centers_company_type_idx on public.cost_centers (company_id, cost_center_type);
create unique index if not exists cost_centers_project_id_key_idx on public.cost_centers (project_id) where project_id is not null;

alter table public.projects add column if not exists cost_center_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'projects_cost_center_id_fkey'
  ) then
    alter table public.projects
      add constraint projects_cost_center_id_fkey
      foreign key (cost_center_id) references public.cost_centers(id) on delete set null;
  end if;
end $$;

create index if not exists projects_cost_center_id_idx on public.projects (cost_center_id);
create unique index if not exists projects_cost_center_id_key_idx on public.projects (cost_center_id) where cost_center_id is not null;

alter table logistica.stock_movements add column if not exists cost_center_id uuid references public.cost_centers(id) on delete set null;
alter table logistica.stock_balances add column if not exists cost_center_id uuid references public.cost_centers(id) on delete set null;

create index if not exists stock_movements_company_cost_center_idx on logistica.stock_movements (company_id, cost_center_id);
create index if not exists stock_movements_cost_center_item_idx on logistica.stock_movements (cost_center_id, item_id);
create index if not exists stock_balances_company_cost_center_idx on logistica.stock_balances (company_id, cost_center_id);
create index if not exists stock_balances_cost_center_item_idx on logistica.stock_balances (cost_center_id, item_id);

create or replace function public.validate_cost_center_row()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_project_company_id uuid;
begin
  if new.company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if btrim(coalesce(new.code, '')) = '' then
    raise exception 'code es obligatorio';
  end if;

  if btrim(coalesce(new.name, '')) = '' then
    raise exception 'name es obligatorio';
  end if;

  if new.cost_center_type not in ('project', 'office', 'administration', 'warehouse', 'maintenance', 'general_operation', 'other') then
    raise exception 'cost_center_type inválido';
  end if;

  if new.project_id is not null and new.cost_center_type <> 'project' then
    raise exception 'project_id solo puede usarse cuando cost_center_type = project';
  end if;

  if new.project_id is not null then
    select p.company_id
      into v_project_company_id
    from public.projects p
    where p.id = new.project_id;

    if not found then
      raise exception 'project_id no existe';
    end if;

    if v_project_company_id <> new.company_id then
      raise exception 'project_id debe pertenecer a la misma empresa';
    end if;
  end if;

  return new;
end;
$$;

alter table public.cost_centers enable row level security;

drop policy if exists cost_centers_select_company on public.cost_centers;
create policy cost_centers_select_company
on public.cost_centers
for select
using (public.has_company_access(company_id));

drop policy if exists cost_centers_insert_company on public.cost_centers;
create policy cost_centers_insert_company
on public.cost_centers
for insert
with check (public.can_manage_company_roles(company_id));

drop policy if exists cost_centers_update_company on public.cost_centers;
create policy cost_centers_update_company
on public.cost_centers
for update
using (public.can_manage_company_roles(company_id))
with check (public.can_manage_company_roles(company_id));

drop trigger if exists trg_public_cost_centers_updated_at on public.cost_centers;
create trigger trg_public_cost_centers_updated_at
before update on public.cost_centers
for each row execute function public.set_updated_at();

drop trigger if exists trg_public_cost_centers_validation on public.cost_centers;
create trigger trg_public_cost_centers_validation
before insert or update on public.cost_centers
for each row execute function public.validate_cost_center_row();

drop trigger if exists trg_public_cost_centers_audit on public.cost_centers;
create trigger trg_public_cost_centers_audit
after insert or update or delete on public.cost_centers
for each row execute function public.audit_shared_master_change();

create or replace view public.v_cost_centers_summary as
select
  cc.id,
  cc.company_id,
  c.name as company_name,
  cc.code,
  cc.name,
  cc.description,
  cc.cost_center_type,
  cc.project_id,
  p.code as project_code,
  p.name as project_name,
  cc.is_default,
  cc.is_active,
  cc.created_at,
  cc.updated_at,
  cc.created_by,
  cc.updated_by
from public.cost_centers cc
join public.companies c on c.id = cc.company_id
left join public.projects p on p.id = cc.project_id;

grant select, insert, update on public.cost_centers to authenticated;
grant select on public.v_cost_centers_summary to authenticated;
