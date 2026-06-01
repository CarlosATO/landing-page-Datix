-- Verificación temporal de maestros operacionales compartidos.

select * from public.projects where company_id = '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b'::uuid and code = 'TEST_PROJECT_001';
select * from public.contractors where company_id = '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b'::uuid and tax_id = 'TEST_CONTRACTOR_001';
select * from public.workers where company_id = '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b'::uuid and tax_id = 'TEST_WORKER_001';
select * from public.suppliers where company_id = '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b'::uuid and tax_id = 'TEST_SUPPLIER_001';
