create extension if not exists pgcrypto;

create table if not exists public.company_modules (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete cascade,
  module_key text not null,
  status text not null default 'active',
  enabled_at timestamptz,
  disabled_at timestamptz,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table if exists public.company_modules
  add column if not exists id uuid default gen_random_uuid(),
  add column if not exists company_id uuid,
  add column if not exists module_key text,
  add column if not exists status text default 'active',
  add column if not exists enabled_at timestamptz,
  add column if not exists disabled_at timestamptz,
  add column if not exists created_at timestamptz default now(),
  add column if not exists updated_at timestamptz default now();

do $$
declare
  v_duplicates integer;
begin
  select count(*) into v_duplicates
  from (
    select 1
    from public.company_modules
    group by company_id, module_key
    having count(*) > 1
  ) dupes;

  if v_duplicates = 0 then
    execute 'create unique index if not exists company_modules_company_id_module_key_key on public.company_modules (company_id, module_key)';
  else
    raise notice 'Skipping company_modules unique index due to % duplicate groups', v_duplicates;
  end if;
end $$;

do $$
declare
  v_incompatible integer;
begin
  select count(*) into v_incompatible
  from public.company_modules
  where company_id is null or module_key is null or status is null;

  if v_incompatible = 0 then
    if not exists (
      select 1
      from pg_constraint
      where conname = 'company_modules_required_fields_check'
    ) then
      alter table public.company_modules
        add constraint company_modules_required_fields_check
        check (company_id is not null and module_key is not null and status is not null);
    end if;
  else
    raise notice 'Skipping company_modules_required_fields_check due to % incompatible rows', v_incompatible;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'company_modules_status_check'
  ) then
    alter table public.company_modules
      add constraint company_modules_status_check
      check (status in ('active', 'inactive', 'trial', 'blocked'));
  end if;
end $$;

create table if not exists public.user_roles (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role_key text not null,
  module_key text,
  created_at timestamptz default now()
);

alter table if exists public.user_roles
  add column if not exists id uuid default gen_random_uuid(),
  add column if not exists company_id uuid,
  add column if not exists user_id uuid,
  add column if not exists role_key text,
  add column if not exists module_key text,
  add column if not exists created_at timestamptz default now();

do $$
declare
  v_owner_duplicates integer;
  v_module_duplicates integer;
begin
  select count(*) into v_owner_duplicates
  from (
    select 1
    from public.user_roles
    where upper(role_key) = 'OWNER' and module_key is null
    group by company_id, user_id
    having count(*) > 1
  ) dupes;

  select count(*) into v_module_duplicates
  from (
    select 1
    from public.user_roles
    where module_key is not null
    group by company_id, user_id, role_key, module_key
    having count(*) > 1
  ) dupes;

  if v_owner_duplicates = 0 then
    execute 'create unique index if not exists user_roles_owner_unique_idx on public.user_roles (company_id, user_id) where upper(role_key) = ''OWNER'' and module_key is null';
  else
    raise notice 'Skipping user_roles OWNER unique index due to % duplicate groups', v_owner_duplicates;
  end if;

  if v_module_duplicates = 0 then
    execute 'create unique index if not exists user_roles_module_unique_idx on public.user_roles (company_id, user_id, role_key, module_key) where module_key is not null';
  else
    raise notice 'Skipping user_roles module unique index due to % duplicate groups', v_module_duplicates;
  end if;
end $$;

do $$
declare
  v_incompatible integer;
begin
  select count(*) into v_incompatible
  from public.user_roles
  where company_id is null or user_id is null or role_key is null;

  if v_incompatible = 0 then
    if not exists (
      select 1
      from pg_constraint
      where conname = 'user_roles_required_fields_check'
    ) then
      alter table public.user_roles
        add constraint user_roles_required_fields_check
        check (company_id is not null and user_id is not null and role_key is not null);
    end if;
  else
    raise notice 'Skipping user_roles_required_fields_check due to % incompatible rows', v_incompatible;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'user_roles_owner_module_key_check'
  ) then
    alter table public.user_roles
      add constraint user_roles_owner_module_key_check
      check (
        (upper(role_key) = 'OWNER' and module_key is null)
        or (upper(role_key) <> 'OWNER' and module_key is not null)
      );
  end if;
end $$;

-- Diagnostic queries before applying constraints/policies:
-- select * from public.user_roles where upper(role_key) = 'OWNER' and module_key is not null;
-- select * from public.user_roles where upper(role_key) <> 'OWNER' and module_key is null;
-- select c.id, c.name from public.companies c left join public.company_modules cm on cm.company_id = c.id group by c.id, c.name having count(cm.id) = 0;
-- select c.id, c.name from public.companies c left join public.user_roles ur on ur.company_id = c.id group by c.id, c.name having count(ur.id) = 0;
-- select * from public.company_modules where status not in ('active', 'inactive', 'trial', 'blocked');

-- Optional backfill for legacy companies and owners.
-- This block is intentionally conservative and can be removed if legacy data is not present.
do $$
begin
  if to_regclass('public.companies') is not null then
    insert into public.company_modules (company_id, module_key, status, enabled_at, disabled_at)
    select c.id, 'logistica', 'trial', now(), null
    from public.companies c
    where not exists (
      select 1
      from public.company_modules cm
      where cm.company_id = c.id
        and lower(cm.module_key) = 'logistica'
    );
  end if;

  if to_regclass('public.company_users') is not null then
    insert into public.user_roles (company_id, user_id, role_key, module_key)
    select cu.company_id, cu.user_id, 'OWNER', null
    from public.company_users cu
    where upper(coalesce(cu.role, '')) = 'OWNER'
      and cu.user_id is not null
      and cu.company_id is not null
      and not exists (
        select 1
        from public.user_roles ur
        where ur.company_id = cu.company_id
          and ur.user_id = cu.user_id
          and upper(ur.role_key) = 'OWNER'
          and ur.module_key is null
      );
  end if;
end $$;

create table if not exists public.audit_log (
  id uuid primary key default gen_random_uuid(),
  company_id uuid,
  user_id uuid,
  action text not null,
  entity_schema text,
  entity_table text,
  entity_id uuid,
  old_data jsonb,
  new_data jsonb,
  metadata jsonb,
  created_at timestamptz default now()
);

create index if not exists audit_log_company_id_created_at_idx
  on public.audit_log (company_id, created_at desc);

create index if not exists audit_log_entity_table_entity_id_idx
  on public.audit_log (entity_table, entity_id);

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

create or replace function public.require_authenticated()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  return v_user_id;
end;
$$;

create or replace function public.has_role(
  p_company_id uuid,
  p_role_key text,
  p_module_key text default null
)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_roles ur
    where ur.company_id = p_company_id
      and ur.user_id = auth.uid()
      and upper(ur.role_key) = upper(p_role_key)
      and ur.module_key is not distinct from p_module_key
  );
$$;

create or replace function public.is_owner(p_company_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select public.has_role(p_company_id, 'OWNER', null);
$$;

create or replace function public.has_company_access(p_company_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select case
    when p_company_id is null or auth.uid() is null then false
    else exists (
      select 1
      from public.user_roles ur
      where ur.company_id = p_company_id
        and ur.user_id = auth.uid()
    )
  end;
$$;

create or replace function public.has_module_access(p_company_id uuid, p_module_key text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select case
    when p_company_id is null or p_module_key is null or auth.uid() is null then false
    when public.is_owner(p_company_id) then true
    else exists (
      select 1
      from public.user_roles ur
      join public.company_modules cm
        on cm.company_id = ur.company_id
       and lower(cm.module_key) = lower(ur.module_key)
      where ur.company_id = p_company_id
        and ur.user_id = auth.uid()
        and lower(ur.module_key) = lower(p_module_key)
        and cm.status in ('active', 'trial')
    )
  end;
$$;

create or replace function public.can_manage_company_roles(p_company_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select case
    when p_company_id is null or auth.uid() is null then false
    when public.is_owner(p_company_id) then true
    else exists (
      select 1
      from public.user_roles ur
      where ur.company_id = p_company_id
        and ur.user_id = auth.uid()
        and upper(ur.role_key) like 'ADMIN%'
    )
  end;
$$;

create or replace function public.audit_row_change()
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
    jsonb_build_object('trigger', true)
  );

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

alter table public.company_modules enable row level security;
alter table public.user_roles enable row level security;

drop policy if exists company_modules_select_own_company on public.company_modules;
create policy company_modules_select_own_company
on public.company_modules
for select
using (public.has_company_access(company_id));

drop policy if exists company_modules_manage_company on public.company_modules;
create policy company_modules_manage_company
on public.company_modules
for insert
with check (public.can_manage_company_roles(company_id));

drop policy if exists company_modules_update_company on public.company_modules;
create policy company_modules_update_company
on public.company_modules
for update
using (public.can_manage_company_roles(company_id))
with check (public.can_manage_company_roles(company_id));

drop policy if exists company_modules_delete_company on public.company_modules;
create policy company_modules_delete_company
on public.company_modules
for delete
using (public.can_manage_company_roles(company_id));

drop policy if exists user_roles_select_own_company on public.user_roles;
create policy user_roles_select_own_company
on public.user_roles
for select
using (public.has_company_access(company_id));

drop policy if exists user_roles_insert_company on public.user_roles;
create policy user_roles_insert_company
on public.user_roles
for insert
with check (
  public.can_manage_company_roles(company_id)
  and (
    upper(role_key) <> 'OWNER'
    or public.is_owner(company_id)
  )
);

drop policy if exists user_roles_update_company on public.user_roles;
create policy user_roles_update_company
on public.user_roles
for update
using (
  public.can_manage_company_roles(company_id)
  and (
    upper(role_key) <> 'OWNER'
    or public.is_owner(company_id)
  )
)
with check (
  public.can_manage_company_roles(company_id)
  and (
    upper(role_key) <> 'OWNER'
    or public.is_owner(company_id)
  )
);

drop policy if exists user_roles_delete_company on public.user_roles;
create policy user_roles_delete_company
on public.user_roles
for delete
using (
  public.can_manage_company_roles(company_id)
  and (
    upper(role_key) <> 'OWNER'
    or public.is_owner(company_id)
  )
);

drop trigger if exists trg_company_modules_updated_at on public.company_modules;
create trigger trg_company_modules_updated_at
before update on public.company_modules
for each row execute function public.set_updated_at();

drop trigger if exists trg_company_modules_audit on public.company_modules;
create trigger trg_company_modules_audit
after insert or update or delete on public.company_modules
for each row execute function public.audit_row_change();

drop trigger if exists trg_user_roles_audit on public.user_roles;
create trigger trg_user_roles_audit
after insert or update or delete on public.user_roles
for each row execute function public.audit_row_change();

create or replace function public.enable_company_module(
  p_company_id uuid,
  p_module_key text
)
returns public.company_modules
language plpgsql
security definer
set search_path = public
as $$
declare
  v_module public.company_modules;
  v_module_key text := lower(trim(p_module_key));
  v_actor uuid := public.require_authenticated();
begin
  if p_company_id is null or v_module_key is null or v_module_key = '' then
    raise exception 'company_id and module_key are required';
  end if;

  if not public.can_manage_company_roles(p_company_id) then
    raise exception 'forbidden';
  end if;

  insert into public.company_modules (
    company_id,
    module_key,
    status,
    enabled_at,
    disabled_at,
    updated_at
  ) values (
    p_company_id,
    v_module_key,
    'active',
    now(),
    null,
    now()
  )
  on conflict (company_id, module_key)
  do update set
    status = 'active',
    enabled_at = now(),
    disabled_at = null,
    updated_at = now()
  returning * into v_module;

  insert into public.audit_log (
    company_id, user_id, action, entity_schema, entity_table, entity_id, old_data, new_data, metadata
  ) values (
    p_company_id,
    v_actor,
    'enable_module',
    'public',
    'company_modules',
    v_module.id,
    null,
    to_jsonb(v_module),
    jsonb_build_object('rpc', 'enable_company_module')
  );

  return v_module;
end;
$$;

create or replace function public.disable_company_module(
  p_company_id uuid,
  p_module_key text
)
returns public.company_modules
language plpgsql
security definer
set search_path = public
as $$
declare
  v_module public.company_modules;
  v_module_key text := lower(trim(p_module_key));
  v_actor uuid := public.require_authenticated();
begin
  if p_company_id is null or v_module_key is null or v_module_key = '' then
    raise exception 'company_id and module_key are required';
  end if;

  if not public.can_manage_company_roles(p_company_id) then
    raise exception 'forbidden';
  end if;

  insert into public.company_modules (
    company_id,
    module_key,
    status,
    enabled_at,
    disabled_at,
    updated_at
  ) values (
    p_company_id,
    v_module_key,
    'inactive',
    null,
    now(),
    now()
  )
  on conflict (company_id, module_key)
  do update set
    status = 'inactive',
    disabled_at = now(),
    updated_at = now()
  returning * into v_module;

  insert into public.audit_log (
    company_id, user_id, action, entity_schema, entity_table, entity_id, old_data, new_data, metadata
  ) values (
    p_company_id,
    v_actor,
    'disable_module',
    'public',
    'company_modules',
    v_module.id,
    null,
    to_jsonb(v_module),
    jsonb_build_object('rpc', 'disable_company_module')
  );

  return v_module;
end;
$$;

create or replace function public.assign_user_role(
  p_company_id uuid,
  p_user_id uuid,
  p_role_key text,
  p_module_key text default null
)
returns public.user_roles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.user_roles;
  v_role_key text := upper(trim(p_role_key));
  v_module_key text := nullif(lower(trim(coalesce(p_module_key, ''))), '');
  v_actor uuid := public.require_authenticated();
begin
  if p_company_id is null or p_user_id is null or v_role_key is null or v_role_key = '' then
    raise exception 'company_id, user_id and role_key are required';
  end if;

  if p_user_id = v_actor then
    raise exception 'self role assignment is not allowed';
  end if;

  if not public.can_manage_company_roles(p_company_id) then
    raise exception 'forbidden';
  end if;

  if v_role_key = 'OWNER' and v_module_key is not null then
    raise exception 'OWNER must have module_key null';
  end if;

  if v_role_key <> 'OWNER' and v_module_key is null then
    raise exception 'operational roles must include module_key';
  end if;

  if v_role_key = 'OWNER' and not public.is_owner(p_company_id) then
    raise exception 'only OWNER can assign OWNER';
  end if;

  if v_role_key = 'OWNER' then
    insert into public.user_roles (
      company_id,
      user_id,
      role_key,
      module_key
    ) values (
      p_company_id,
      p_user_id,
      v_role_key,
      null
    )
    on conflict (company_id, user_id)
    where upper(role_key) = 'OWNER' and module_key is null
    do update set
      role_key = excluded.role_key,
      module_key = excluded.module_key
    returning * into v_role;
  else
    insert into public.user_roles (
      company_id,
      user_id,
      role_key,
      module_key
    ) values (
      p_company_id,
      p_user_id,
      v_role_key,
      v_module_key
    )
    on conflict (company_id, user_id, role_key, module_key)
    where module_key is not null
    do update set
      role_key = excluded.role_key,
      module_key = excluded.module_key
    returning * into v_role;
  end if;

  insert into public.audit_log (
    company_id, user_id, action, entity_schema, entity_table, entity_id, old_data, new_data, metadata
  ) values (
    p_company_id,
    v_actor,
    'assign_role',
    'public',
    'user_roles',
    v_role.id,
    null,
    to_jsonb(v_role),
    jsonb_build_object('rpc', 'assign_user_role')
  );

  return v_role;
end;
$$;

create or replace function public.revoke_user_role(
  p_company_id uuid,
  p_user_id uuid,
  p_role_key text,
  p_module_key text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role_key text := upper(trim(p_role_key));
  v_module_key text := nullif(lower(trim(coalesce(p_module_key, ''))), '');
  v_deleted integer;
  v_actor uuid := public.require_authenticated();
begin
  if p_company_id is null or p_user_id is null or v_role_key is null or v_role_key = '' then
    raise exception 'company_id, user_id and role_key are required';
  end if;

  if p_user_id = v_actor then
    raise exception 'self role revocation is not allowed';
  end if;

  if not public.can_manage_company_roles(p_company_id) then
    raise exception 'forbidden';
  end if;

  if v_role_key = 'OWNER' and not public.is_owner(p_company_id) then
    raise exception 'only OWNER can revoke OWNER';
  end if;

  delete from public.user_roles
  where company_id = p_company_id
    and user_id = p_user_id
    and upper(role_key) = v_role_key
    and module_key is not distinct from v_module_key;

  get diagnostics v_deleted = row_count;

  insert into public.audit_log (
    company_id, user_id, action, entity_schema, entity_table, entity_id, old_data, new_data, metadata
  ) values (
    p_company_id,
    v_actor,
    'revoke_role',
    'public',
    'user_roles',
    null,
    null,
    null,
    jsonb_build_object('rpc', 'revoke_user_role', 'deleted_rows', v_deleted)
  );

  return v_deleted > 0;
end;
$$;
