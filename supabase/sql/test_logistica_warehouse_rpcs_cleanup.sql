-- Limpieza temporal de la prueba de RPCs de bodegas Logística.

do $$
declare
  v_company_id uuid := '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b';
begin
  delete from logistica.warehouses
  where company_id = v_company_id
    and code like 'TEST_LOG_WH_%';
end;
$$;
