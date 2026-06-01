-- Prueba temporal de maestros operacionales compartidos.
-- Reemplazar el company_id placeholder antes de ejecutar.

do $$
declare
  v_company_id uuid := '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b';
  v_user_id uuid;
  v_project_id uuid;
  v_contractor_id uuid;
  v_worker_id uuid;
  v_supplier_id uuid;
begin
  delete from public.workers where company_id = v_company_id and tax_id = 'TEST_WORKER_001';
  delete from public.contractors where company_id = v_company_id and tax_id = 'TEST_CONTRACTOR_001';
  delete from public.suppliers where company_id = v_company_id and tax_id = 'TEST_SUPPLIER_001';
  delete from public.projects where company_id = v_company_id and code = 'TEST_PROJECT_001';

  select candidate.user_id
    into v_user_id
  from (
    select cu.user_id, 0 as priority, cu.created_at
    from public.company_users cu
    where cu.company_id = v_company_id and upper(coalesce(cu.role, '')) = 'OWNER'
    union all
    select cu.user_id, 1 as priority, cu.created_at
    from public.company_users cu
    where cu.company_id = v_company_id and upper(coalesce(cu.role, '')) like 'ADMIN%'
    union all
    select cu.user_id, 2 as priority, cu.created_at
    from public.company_users cu
    where cu.company_id = v_company_id
    union all
    select ur.user_id, 3 as priority, ur.created_at
    from public.user_roles ur
    where ur.company_id = v_company_id and upper(coalesce(ur.role_key, '')) = 'OWNER'
    union all
    select ur.user_id, 4 as priority, ur.created_at
    from public.user_roles ur
    where ur.company_id = v_company_id and upper(coalesce(ur.role_key, '')) like 'ADMIN%'
    union all
    select ur.user_id, 5 as priority, ur.created_at
    from public.user_roles ur
    where ur.company_id = v_company_id
    union all
    select c.created_by, 6 as priority, c.created_at
    from public.companies c
    where c.id = v_company_id and c.created_by is not null
  ) candidate
  order by candidate.priority, candidate.created_at asc nulls last
  limit 1;

  if v_user_id is null then
    raise exception 'No se encontró un usuario válido para la empresa de prueba';
  end if;

  perform set_config('request.jwt.claim.sub', v_user_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  insert into public.projects (
    company_id, code, name, description, status, start_date, expected_end_date, budget_amount, address, city, region, responsible_user_id, metadata, is_active, created_by, updated_by
  ) values (
    v_company_id, 'TEST_PROJECT_001', 'TEST_PROJECT_001', 'Proyecto temporal compartido de prueba', 'active', current_date, current_date + 30, 100000.00, 'TEST PROJECT ADDRESS', 'TEST CITY', 'TEST REGION', v_user_id, jsonb_build_object('test', true), true, v_user_id, v_user_id
  ) returning id into v_project_id;

  insert into public.contractors (
    company_id, tax_id, business_name, trade_name, contact_name, phone, email, address, city, region, status, metadata, is_active, created_by, updated_by
  ) values (
    v_company_id, 'TEST_CONTRACTOR_001', 'TEST_CONTRACTOR_001', 'TEST_CONTRACTOR_TRADE_001', 'TEST CONTACT', '+56900000021', 'test_contractor@example.com', 'TEST CONTRACTOR ADDRESS', 'TEST CITY', 'TEST REGION', 'active', jsonb_build_object('test', true), true, v_user_id, v_user_id
  ) returning id into v_contractor_id;

  insert into public.workers (
    company_id, contractor_id, tax_id, first_name, last_name, job_title, phone, email, status, metadata, is_active, created_by, updated_by
  ) values (
    v_company_id, v_contractor_id, 'TEST_WORKER_001', 'TEST', 'WORKER', 'Supervisor', '+56900000022', 'test_worker@example.com', 'active', jsonb_build_object('test', true), true, v_user_id, v_user_id
  ) returning id into v_worker_id;

  insert into public.suppliers (
    company_id, tax_id, business_name, trade_name, contact_name, phone, email, address, city, region, status, metadata, is_active, created_by, updated_by
  ) values (
    v_company_id, 'TEST_SUPPLIER_001', 'TEST_SUPPLIER_001', 'TEST_SUPPLIER_TRADE_001', 'TEST CONTACT', '+56900000023', 'test_supplier@example.com', 'TEST SUPPLIER ADDRESS', 'TEST CITY', 'TEST REGION', 'active', jsonb_build_object('test', true), true, v_user_id, v_user_id
  ) returning id into v_supplier_id;

  raise notice 'seeded shared master ids: %, %, %, %', v_project_id, v_contractor_id, v_worker_id, v_supplier_id;
end;
$$;
