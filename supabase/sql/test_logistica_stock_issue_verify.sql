-- Verificación temporal de logistica.create_stock_issue.

select
  movement_type,
  count(*)::int as rows
from logistica.stock_movements
where company_id = '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b'::uuid
  and reference_number in ('TEST_LOG_ISSUE_GEN_001', 'TEST_LOG_ISSUE_CONS_001', 'TEST_LOG_ISSUE_ASSIGN_001')
group by movement_type
order by movement_type;

select
  i.sku,
  w.code as warehouse_code,
  l.code as location_code,
  b.quantity_on_hand,
  b.quantity_reserved,
  b.average_unit_cost,
  b.total_cost
from logistica.stock_balances b
join logistica.items i on i.id = b.item_id
join logistica.warehouses w on w.id = b.warehouse_id
left join logistica.locations l on l.id = b.location_id
where b.company_id = '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b'::uuid
  and i.sku in ('TEST_LOG_ITEM_CONS_001', 'TEST_LOG_ITEM_TOOL_001')
order by i.sku, w.code;

select
  serial_number,
  status,
  current_custodian_type,
  current_custodian_id,
  current_project_id,
  current_warehouse_id,
  current_location_id
from logistica.item_serials
where company_id = '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b'::uuid
  and serial_number = 'TEST_LOG_SERIAL_001';

select
  p.code as project_code,
  p.name as project_name,
  c.tax_id as contractor_tax_id,
  w.tax_id as worker_tax_id
from public.projects p
join public.contractors c on c.company_id = p.company_id
join public.workers w on w.company_id = p.company_id
where p.company_id = '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b'::uuid
  and p.code = 'TEST_SHARED_PROJECT_001'
  and c.tax_id = 'TEST_SHARED_CONTRACTOR_001'
  and w.tax_id = 'TEST_SHARED_WORKER_001';

select
  reference_number,
  movement_type,
  quantity,
  from_warehouse_name,
  from_location_name,
  sku,
  target_document_type,
  target_document_id
from logistica.v_kardex_movements
where company_id = '48e5e15d-8e6a-4e64-9610-70f2fb0bc53b'::uuid
  and reference_number in ('TEST_LOG_ISSUE_GEN_001', 'TEST_LOG_ISSUE_CONS_001', 'TEST_LOG_ISSUE_ASSIGN_001', 'TEST_LOG_RECEIPT_ISSUE_001')
order by reference_number, movement_type, sku;
