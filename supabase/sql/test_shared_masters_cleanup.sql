-- Limpieza temporal de maestros operacionales compartidos.

do $$
declare
  v_company_id uuid := '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b';
begin
  delete from public.workers where company_id = v_company_id and tax_id = 'TEST_WORKER_001';
  delete from public.contractors where company_id = v_company_id and tax_id = 'TEST_CONTRACTOR_001';
  delete from public.suppliers where company_id = v_company_id and tax_id = 'TEST_SUPPLIER_001';
  delete from public.projects where company_id = v_company_id and code = 'TEST_PROJECT_001';
end;
$$;
