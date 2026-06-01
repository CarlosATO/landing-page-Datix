-- 20260529183000_public_suppliers_core.sql
-- Migracion A: public.suppliers como maestro transversal de proveedores.

do $$
begin
  if not exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'suppliers'
  ) then
    create table public.suppliers (
      id uuid primary key default gen_random_uuid(),
      company_id uuid not null references public.companies(id) on delete cascade,
      name text not null,
      tax_id text,
      email text,
      phone text,
      address text,
      is_active boolean not null default true,
      created_from_module text,
      created_by uuid references auth.users(id) on delete set null,
      updated_by uuid references auth.users(id) on delete set null,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),

      -- Compatibilidad con el maestro ya existente en el repo.
      business_name text not null,
      trade_name text,
      contact_name text,
      city text,
      region text,
      status text not null default 'active',
      metadata jsonb not null default '{}'::jsonb,

      constraint suppliers_status_check check (status in ('active', 'inactive', 'blocked'))
    );
  end if;
end $$;

alter table public.suppliers
  add column if not exists name text;

alter table public.suppliers
  add column if not exists tax_id text;

alter table public.suppliers
  add column if not exists email text;

alter table public.suppliers
  add column if not exists phone text;

alter table public.suppliers
  add column if not exists address text;

alter table public.suppliers
  add column if not exists is_active boolean;

alter table public.suppliers
  add column if not exists created_from_module text;

alter table public.suppliers
  add column if not exists created_by uuid;

alter table public.suppliers
  add column if not exists updated_by uuid;

alter table public.suppliers
  add column if not exists created_at timestamptz;

alter table public.suppliers
  add column if not exists updated_at timestamptz;

-- Preserve legacy columns already present in the repository schema.
alter table public.suppliers
  add column if not exists business_name text;

alter table public.suppliers
  add column if not exists trade_name text;

alter table public.suppliers
  add column if not exists contact_name text;

alter table public.suppliers
  add column if not exists city text;

alter table public.suppliers
  add column if not exists region text;

alter table public.suppliers
  add column if not exists status text;

alter table public.suppliers
  add column if not exists metadata jsonb;

alter table public.suppliers
  alter column is_active set default true;

alter table public.suppliers
  alter column created_at set default now();

alter table public.suppliers
  alter column updated_at set default now();

do $$
begin
  update public.suppliers
     set name = coalesce(nullif(btrim(name), ''), nullif(btrim(business_name), ''))
   where name is null or btrim(name) = '';

  update public.suppliers
     set business_name = coalesce(nullif(btrim(business_name), ''), nullif(btrim(name), ''))
   where business_name is null or btrim(business_name) = '';
end $$;

create index if not exists suppliers_company_is_active_idx
  on public.suppliers (company_id, is_active);

create index if not exists suppliers_company_created_from_module_idx
  on public.suppliers (company_id, created_from_module);

create index if not exists suppliers_company_name_lc_idx
  on public.suppliers (company_id, lower(coalesce(name, business_name)));

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

alter table public.suppliers enable row level security;

create or replace function public.can_manage_suppliers(p_company_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select case
    when p_company_id is null or auth.uid() is null then false
    when public.is_owner(p_company_id) then true
    when exists (
      select 1
      from public.company_modules cm
      where cm.company_id = p_company_id
        and lower(cm.module_key) = 'adquisiciones'
        and lower(cm.status) in ('active', 'trial')
    ) then public.has_role(p_company_id, 'ADMIN_ADQUISICIONES', 'adquisiciones')
    else public.has_role(p_company_id, 'ADMIN_LOGISTICA', 'logistica')
  end;
$$;

drop policy if exists suppliers_select_company on public.suppliers;
create policy suppliers_select_company
on public.suppliers
for select
using (public.has_company_access(company_id));

drop policy if exists suppliers_insert_company on public.suppliers;
create policy suppliers_insert_company
on public.suppliers
for insert
with check (public.can_manage_suppliers(company_id));

drop policy if exists suppliers_update_company on public.suppliers;
create policy suppliers_update_company
on public.suppliers
for update
using (public.can_manage_suppliers(company_id))
with check (public.can_manage_suppliers(company_id));

drop policy if exists suppliers_delete_company on public.suppliers;
create policy suppliers_delete_company
on public.suppliers
for delete
using (public.can_manage_suppliers(company_id));

create or replace function public.can_manage_shared_operational_masters(p_company_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select case
    when p_company_id is null or auth.uid() is null then false
    when public.is_owner(p_company_id) then true
    when exists (
      select 1
      from public.company_modules cm
      where cm.company_id = p_company_id
        and lower(cm.module_key) = 'logistica'
        and lower(cm.status) in ('active', 'trial')
    ) and public.has_role(p_company_id, 'ADMIN_LOGISTICA', 'logistica') then true
    when exists (
      select 1
      from public.company_modules cm
      where cm.company_id = p_company_id
        and lower(cm.module_key) = 'adquisiciones'
        and lower(cm.status) in ('active', 'trial')
    ) and public.has_role(p_company_id, 'ADMIN_ADQUISICIONES', 'adquisiciones') then true
    when exists (
      select 1
      from public.company_modules cm
      where cm.company_id = p_company_id
        and lower(cm.module_key) = 'construccion'
        and lower(cm.status) in ('active', 'trial')
    ) and public.has_role(p_company_id, 'ADMIN_CONSTRUCCION', 'construccion') then true
    else false
  end;
$$;

create or replace function public.create_supplier_minimal(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
  v_name text;
  v_tax_id text;
  v_email text;
  v_phone text;
  v_address text;
  v_created_from_module text := 'logistica';
  v_supplier public.suppliers%rowtype;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_name := nullif(btrim(coalesce(p_payload->>'name', p_payload->>'business_name', '')), '');
  v_tax_id := nullif(btrim(coalesce(p_payload->>'tax_id', '')), '');
  v_email := nullif(btrim(coalesce(p_payload->>'email', '')), '');
  v_phone := nullif(btrim(coalesce(p_payload->>'phone', '')), '');
  v_address := nullif(btrim(coalesce(p_payload->>'address', '')), '');

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if v_name is null then
    raise exception 'name es obligatorio';
  end if;

  if not public.has_company_access(v_company_id) then
    raise exception 'forbidden';
  end if;

  if not public.has_module_access(v_company_id, 'logistica') then
    raise exception 'module access required';
  end if;

  if exists (
    select 1
    from public.company_modules cm
    where cm.company_id = v_company_id
      and lower(cm.module_key) = 'adquisiciones'
      and lower(cm.status) in ('active', 'trial')
  ) then
    raise exception 'supplier creation is disabled because adquisiciones is contracted';
  end if;

  if not (public.is_owner(v_company_id) or public.has_role(v_company_id, 'ADMIN_LOGISTICA', 'logistica')) then
    raise exception 'insufficient role';
  end if;

  insert into public.suppliers (
    company_id,
    name,
    business_name,
    tax_id,
    email,
    phone,
    address,
    is_active,
    created_from_module,
    created_by,
    updated_by
  ) values (
    v_company_id,
    v_name,
    v_name,
    v_tax_id,
    v_email,
    v_phone,
    v_address,
    true,
    v_created_from_module,
    v_user_id,
    v_user_id
  )
  returning * into v_supplier;

  return jsonb_build_object(
    'supplier', to_jsonb(v_supplier)
  );
end;
$$;

create or replace function public.list_suppliers_by_company(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_include_inactive boolean := false;
  v_search text;
  v_suppliers jsonb := '[]'::jsonb;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido';
  end if;

  v_company_id := nullif(btrim(coalesce(p_payload->>'company_id', '')), '')::uuid;
  v_include_inactive := coalesce((p_payload->>'include_inactive')::boolean, false);
  v_search := nullif(btrim(coalesce(p_payload->>'search', '')), '');

  if v_company_id is null then
    raise exception 'company_id es obligatorio';
  end if;

  if not public.has_company_access(v_company_id) then
    raise exception 'forbidden';
  end if;

  if not public.has_module_access(v_company_id, 'logistica') then
    raise exception 'module access required';
  end if;

  select coalesce(jsonb_agg(row_to_json(s)::jsonb), '[]'::jsonb)
    into v_suppliers
  from (
    select
      sp.id,
      sp.company_id,
      coalesce(nullif(btrim(sp.name), ''), nullif(btrim(sp.business_name), '')) as name,
      sp.business_name,
      sp.tax_id,
      sp.email,
      sp.phone,
      sp.address,
      sp.is_active,
      sp.created_from_module,
      sp.created_at,
      sp.updated_at
    from public.suppliers sp
    where sp.company_id = v_company_id
      and (v_include_inactive or coalesce(sp.is_active, true) = true)
      and (
        v_search is null
        or coalesce(nullif(btrim(sp.name), ''), nullif(btrim(sp.business_name), ''), '') ilike ('%' || v_search || '%')
        or coalesce(sp.tax_id, '') ilike ('%' || v_search || '%')
      )
    order by coalesce(nullif(btrim(sp.name), ''), nullif(btrim(sp.business_name), '')) asc, sp.created_at desc
  ) s;

  return jsonb_build_object('suppliers', v_suppliers);
end;
$$;

grant select, insert, update on public.suppliers to authenticated;
grant execute on function public.create_supplier_minimal(jsonb) to authenticated;
grant execute on function public.list_suppliers_by_company(jsonb) to authenticated;
