


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "pharmacy";


ALTER SCHEMA "pharmacy" OWNER TO "postgres";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "pharmacy"."calculate_prescription_valid_until"("p_prescription_type" "text", "p_issued_at" timestamp with time zone DEFAULT "now"()) RETURNS timestamp with time zone
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pharmacy', 'public'
    AS $$
declare
  v_days integer;
begin
  select validity_days
  into v_days
  from pharmacy.prescription_validity_rules
  where prescription_type = p_prescription_type;

  v_days := coalesce(v_days, 30);

  return p_issued_at + make_interval(days => v_days);
end;
$$;


ALTER FUNCTION "pharmacy"."calculate_prescription_valid_until"("p_prescription_type" "text", "p_issued_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "pharmacy"."create_pos_operator"("p_full_name" "text", "p_pin" "text", "p_warehouse_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
  v_company_id uuid;
  v_id uuid;
begin
  select company_id into v_company_id
  from public.company_users
  where user_id = auth.uid()
  limit 1;

  if v_company_id is null then
    raise exception 'Usuario sin empresa';
  end if;

  insert into pharmacy.pos_operators (
    company_id,
    warehouse_id,
    full_name,
    pin_hash
  )
  values (
    v_company_id,
    p_warehouse_id,
    p_full_name,
    crypt(p_pin, gen_salt('bf'))
  )
  returning id into v_id;

  return v_id;
end;
$$;


ALTER FUNCTION "pharmacy"."create_pos_operator"("p_full_name" "text", "p_pin" "text", "p_warehouse_id" "uuid") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "pharmacy"."pos_operators" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "warehouse_id" "uuid" NOT NULL,
    "full_name" "text" NOT NULL,
    "pin_hash" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "pharmacy"."pos_operators" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "pharmacy"."create_pos_operator"("p_company_id" "uuid", "p_warehouse_id" "uuid", "p_full_name" "text", "p_pin_code" "text") RETURNS "pharmacy"."pos_operators"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
  new_operator pharmacy.pos_operators;
begin
  if p_pin_code is null or length(trim(p_pin_code)) <> 4 then
    raise exception 'El PIN debe tener exactamente 4 digitos';
  end if;
  insert into pharmacy.pos_operators (
    company_id,
    warehouse_id,
    full_name,
    pin_hash,
    is_active
  )
  values (
    p_company_id,
    p_warehouse_id,
    upper(trim(p_full_name)),
    crypt(trim(p_pin_code), gen_salt('bf')),
    true
  )
  returning * into new_operator;
  return new_operator;
end;
$$;


ALTER FUNCTION "pharmacy"."create_pos_operator"("p_company_id" "uuid", "p_warehouse_id" "uuid", "p_full_name" "text", "p_pin_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "pharmacy"."create_prescription_with_items"("p_patient_id" "uuid", "p_folio_electronico" "text", "p_prescriber_rut" "text", "p_prescriber_name" "text", "p_institution_name" "text", "p_items" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pharmacy', 'public'
    AS $$
declare
  v_user_id uuid;
  v_company_id uuid;
  v_prescription_id uuid;
  v_item jsonb;
  v_product_id uuid;
  v_quantity numeric;
  v_dosage_instructions text;
  v_prescription_type text;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception 'Usuario no autenticado';
  end if;

  select company_id
  into v_company_id
  from public.company_users
  where user_id = v_user_id
  limit 1;

  if v_company_id is null then
    raise exception 'Usuario sin empresa asociada';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'La receta no contiene medicamentos';
  end if;

  -- validar paciente pertenece a la empresa
  if not exists (
    select 1
    from pharmacy.patients
    where id = p_patient_id
      and company_id = v_company_id
  ) then
    raise exception 'Paciente no pertenece a la empresa';
  end if;

  -- calcular tipo legal según medicamentos
  v_prescription_type := pharmacy.derive_prescription_type_from_items(p_items);

  insert into pharmacy.prescriptions (
    company_id,
    patient_id,
    folio_electronico,
    prescriber_rut,
    prescriber_name,
    institution_name,
    status,
    prescription_type,
    created_by
  )
  values (
    v_company_id,
    p_patient_id,
    p_folio_electronico,
    p_prescriber_rut,
    p_prescriber_name,
    p_institution_name,
    'PENDING',
    v_prescription_type,
    v_user_id
  )
  returning id into v_prescription_id;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_product_id := coalesce(
      nullif(v_item->>'product_id', '')::uuid,
      nullif(v_item->>'id', '')::uuid
    );

    v_quantity := coalesce(
      nullif(v_item->>'quantity_prescribed', '')::numeric,
      nullif(v_item->>'quantity', '')::numeric,
      1
    );

    v_dosage_instructions := coalesce(
      v_item->>'dosage_instructions',
      v_item->>'indications',
      ''
    );

    if v_product_id is null then
      raise exception 'Producto inválido en receta';
    end if;

    if v_quantity <= 0 then
      raise exception 'Cantidad inválida en receta';
    end if;

    -- validar producto pertenece a empresa
    if not exists (
      select 1
      from pharmacy.products
      where id = v_product_id
        and company_id = v_company_id
    ) then
      raise exception 'Producto no pertenece a la empresa';
    end if;

    insert into pharmacy.prescription_items (
      prescription_id,
      product_id,
      quantity_prescribed,
      quantity_dispensed,
      dosage_instructions
    )
    values (
      v_prescription_id,
      v_product_id,
      v_quantity,
      0,
      v_dosage_instructions
    );
  end loop;

  -- recalcular al final por seguridad
  perform pharmacy.recalculate_prescription_type(v_prescription_id);

  return jsonb_build_object(
    'success', true,
    'prescription_id', v_prescription_id,
    'prescription_type', v_prescription_type
  );
end;
$$;


ALTER FUNCTION "pharmacy"."create_prescription_with_items"("p_patient_id" "uuid", "p_folio_electronico" "text", "p_prescriber_rut" "text", "p_prescriber_name" "text", "p_institution_name" "text", "p_items" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "pharmacy"."create_prescription_with_items"("p_company_id" "uuid" DEFAULT NULL::"uuid", "p_diagnosis" "text" DEFAULT NULL::"text", "p_doctor_id" "uuid" DEFAULT NULL::"uuid", "p_folio_electronico" "text" DEFAULT NULL::"text", "p_issue_date" "date" DEFAULT NULL::"date", "p_items" "jsonb" DEFAULT '[]'::"jsonb", "p_notes" "text" DEFAULT NULL::"text", "p_patient_id" "uuid" DEFAULT NULL::"uuid", "p_prescriber_name" "text" DEFAULT NULL::"text", "p_prescriber_rut" "text" DEFAULT NULL::"text", "p_valid_until" "date" DEFAULT NULL::"date") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pharmacy', 'public'
    AS $$
declare
  v_user_id uuid;
  v_company_id uuid;
  v_prescription_id uuid;
  v_item jsonb;
  v_product_id uuid;
  v_quantity numeric;
  v_dosage_instructions text;
  v_prescription_type text;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception 'Usuario no autenticado';
  end if;

  select company_id
  into v_company_id
  from public.company_users
  where user_id = v_user_id
  limit 1;

  if v_company_id is null then
    raise exception 'Usuario sin empresa asociada';
  end if;

  if p_patient_id is null then
    raise exception 'Debe seleccionar paciente';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'La receta no contiene medicamentos';
  end if;

  v_prescription_type := pharmacy.derive_prescription_type_from_items(p_items);

  insert into pharmacy.prescriptions (
    company_id,
    patient_id,
    folio_electronico,
    prescriber_rut,
    prescriber_name,
    institution_name,
    status,
    prescription_type,
    created_by
  )
  values (
    v_company_id,
    p_patient_id,
    p_folio_electronico,
    coalesce(p_prescriber_rut, ''),
    coalesce(p_prescriber_name, ''),
    p_notes,
    'PENDING',
    v_prescription_type,
    v_user_id
  )
  returning id into v_prescription_id;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_product_id := coalesce(
      nullif(v_item->>'product_id', '')::uuid,
      nullif(v_item->>'id', '')::uuid
    );

    v_quantity := coalesce(
      nullif(v_item->>'quantity_prescribed', '')::numeric,
      nullif(v_item->>'quantity', '')::numeric,
      nullif(v_item->>'qty', '')::numeric,
      1
    );

    v_dosage_instructions := coalesce(
      v_item->>'dosage_instructions',
      v_item->>'instructions',
      v_item->>'indications',
      ''
    );

    if v_product_id is null then
      raise exception 'Producto inválido en receta';
    end if;

    insert into pharmacy.prescription_items (
      prescription_id,
      product_id,
      quantity_prescribed,
      quantity_dispensed,
      dosage_instructions
    )
    values (
      v_prescription_id,
      v_product_id,
      v_quantity,
      0,
      v_dosage_instructions
    );
  end loop;

  perform pharmacy.recalculate_prescription_type(v_prescription_id);

  select prescription_type
  into v_prescription_type
  from pharmacy.prescriptions
  where id = v_prescription_id;

  return jsonb_build_object(
    'success', true,
    'prescription_id', v_prescription_id,
    'prescription_type', v_prescription_type
  );
end;
$$;


ALTER FUNCTION "pharmacy"."create_prescription_with_items"("p_company_id" "uuid", "p_diagnosis" "text", "p_doctor_id" "uuid", "p_folio_electronico" "text", "p_issue_date" "date", "p_items" "jsonb", "p_notes" "text", "p_patient_id" "uuid", "p_prescriber_name" "text", "p_prescriber_rut" "text", "p_valid_until" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "pharmacy"."derive_prescription_type_from_items"("p_items" "jsonb") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pharmacy', 'public'
    AS $$
declare
  v_item jsonb;
  v_product_id uuid;

  v_sale_condition text;
  v_prescription_type text;
  v_is_controlled boolean;

  v_result text := 'RECETA_SIMPLE';
begin

  if p_items is null or jsonb_array_length(p_items) = 0 then
    return 'RECETA_SIMPLE';
  end if;

  for v_item in
    select * from jsonb_array_elements(p_items)
  loop

    v_product_id := coalesce(
      nullif(v_item->>'product_id', '')::uuid,
      nullif(v_item->>'id', '')::uuid
    );

    if v_product_id is null then
      continue;
    end if;

    select
      upper(coalesce(sale_condition, 'VD')),
      upper(coalesce(prescription_type, 'VENTA_LIBRE')),
      coalesce(is_controlled, false)
    into
      v_sale_condition,
      v_prescription_type,
      v_is_controlled
    from pharmacy.products
    where id = v_product_id;

    -- RECETA CHEQUE = máxima prioridad
    if v_sale_condition = 'RCH'
       or v_prescription_type = 'RECETA_CHEQUE'
    then
      return 'RECETA_CHEQUE';
    end if;

    -- RECETA RETENIDA
    if v_sale_condition = 'RR'
       or v_prescription_type = 'RECETA_RETENIDA'
       or v_is_controlled = true
    then
      v_result := 'RECETA_RETENIDA';
    end if;

  end loop;

  return v_result;
end;
$$;


ALTER FUNCTION "pharmacy"."derive_prescription_type_from_items"("p_items" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "pharmacy"."expire_overdue_prescriptions"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pharmacy', 'public'
    AS $$
declare
  v_count integer;
begin
  update pharmacy.prescriptions
  set status = 'EXPIRED',
      expired_at = now()
  where status in ('PENDING', 'PARTIAL')
    and valid_until is not null
    and valid_until < now();

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;


ALTER FUNCTION "pharmacy"."expire_overdue_prescriptions"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "pharmacy"."fetch_audit_logs"("p_start_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_end_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_event_type" "text" DEFAULT NULL::"text", "p_user_id" "uuid" DEFAULT NULL::"uuid", "p_limit" integer DEFAULT 50, "p_offset" integer DEFAULT 0) RETURNS TABLE("id" "uuid", "company_id" "uuid", "user_id" "uuid", "event_type" "text", "description" "text", "metadata" "jsonb", "ip_address" "text", "created_at" timestamp with time zone, "total_count" bigint)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pharmacy', 'public'
    AS $$
declare
  v_company_id uuid;
begin
  select cu.company_id
  into v_company_id
  from public.company_users cu
  where cu.user_id = auth.uid()
  limit 1;

  if v_company_id is null then
    raise exception 'Usuario sin empresa asociada';
  end if;

  return query
  with filtered as (
    select a.*
    from pharmacy.audit_logs a
    where a.company_id = v_company_id
      and (p_start_at is null or a.created_at >= p_start_at)
      and (p_end_at is null or a.created_at <= p_end_at)
      and (p_event_type is null or a.event_type ilike '%' || p_event_type || '%')
      and (p_user_id is null or a.user_id = p_user_id)
  )
  select
    f.id,
    f.company_id,
    f.user_id,
    f.event_type,
    f.description,
    f.metadata,
    f.ip_address,
    f.created_at,
    count(*) over() as total_count
  from filtered f
  order by f.created_at desc
  limit least(coalesce(p_limit, 50), 200)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;


ALTER FUNCTION "pharmacy"."fetch_audit_logs"("p_start_at" timestamp with time zone, "p_end_at" timestamp with time zone, "p_event_type" "text", "p_user_id" "uuid", "p_limit" integer, "p_offset" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "pharmacy"."get_my_company_id"() RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  SELECT company_id FROM public.company_users 
  WHERE user_id = auth.uid() 
  LIMIT 1;
$$;


ALTER FUNCTION "pharmacy"."get_my_company_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "pharmacy"."get_pos_products"("p_warehouse_id" "uuid", "p_search" "text" DEFAULT NULL::"text", "p_limit" integer DEFAULT 100) RETURNS TABLE("product_id" "uuid", "barcode" "text", "name" "text", "brand" "text", "dci" "text", "laboratory_name" "text", "sale_condition" "text", "prescription_type" "text", "requires_prescription" boolean, "is_controlled" boolean, "price_sale" numeric, "stock_available" numeric, "stock_quarantine" numeric)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'pharmacy', 'public'
    AS $$
  with my_company as (
    select company_id
    from public.company_users
    where user_id = auth.uid()
    limit 1
  ),
  stock as (
    select
      b.product_id,
      sum(
        case 
          when upper(l.location_type) <> 'QUARANTINE'
          then b.current_quantity 
          else 0 
        end
      ) as stock_available,
      sum(
        case 
          when upper(l.location_type) = 'QUARANTINE'
          then b.current_quantity 
          else 0 
        end
      ) as stock_quarantine
    from pharmacy.inventory_batches b
    join pharmacy.locations l on l.id = b.location_id
    join my_company mc on mc.company_id = b.company_id
    where l.warehouse_id = p_warehouse_id
      and l.company_id = mc.company_id
      and b.current_quantity > 0
    group by b.product_id
  )
  select
    p.id as product_id,
    p.barcode,
    p.name,
    p.brand,
    p.dci,
    p.laboratory_name,
    p.sale_condition,
    p.prescription_type,
    case 
      when p.prescription_type in ('RECETA_SIMPLE', 'RECETA_RETENIDA', 'RECETA_CHEQUE')
        or p.sale_condition in ('R', 'RR', 'RCH')
      then true 
      else false 
    end as requires_prescription,
    coalesce(p.is_controlled, false) as is_controlled,
    coalesce(pp.price_sale, p.price_sale, p.unit_price, 0) as price_sale,
    coalesce(s.stock_available, 0) as stock_available,
    coalesce(s.stock_quarantine, 0) as stock_quarantine
  from pharmacy.products p
  join my_company mc on mc.company_id = p.company_id
  left join stock s on s.product_id = p.id
  left join pharmacy.product_prices pp
    on pp.product_id = p.id
   and pp.company_id = p.company_id
   and pp.warehouse_id = p_warehouse_id
  where p.company_id = mc.company_id
    and (
      p_search is null
      or trim(p_search) = ''
      or p.name ilike '%' || p_search || '%'
      or p.barcode ilike '%' || p_search || '%'
      or p.dci ilike '%' || p_search || '%'
      or p.brand ilike '%' || p_search || '%'
      or p.laboratory_name ilike '%' || p_search || '%'
      or p.registro_sanitario ilike '%' || p_search || '%'
      or p.isp_registry_number ilike '%' || p_search || '%'
    )
  order by p.name asc
  limit least(coalesce(p_limit, 100), 300);
$$;


ALTER FUNCTION "pharmacy"."get_pos_products"("p_warehouse_id" "uuid", "p_search" "text", "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "pharmacy"."increment_dispensed_quantity"("p_prescription_id" "uuid", "p_product_id" "uuid", "p_quantity" numeric) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pharmacy', 'public'
    AS $$
declare
  v_company_id uuid;
  v_prescribed numeric;
  v_dispensed numeric;
  v_pending numeric;
begin
  select company_id
  into v_company_id
  from public.company_users
  where user_id = auth.uid()
  limit 1;

  if v_company_id is null then
    raise exception 'Usuario sin empresa asociada';
  end if;

  select 
    pi.quantity_prescribed,
    coalesce(pi.quantity_dispensed, 0)
  into
    v_prescribed,
    v_dispensed
  from pharmacy.prescription_items pi
  join pharmacy.prescriptions p on p.id = pi.prescription_id
  where pi.prescription_id = p_prescription_id
    and pi.product_id = p_product_id
    and p.company_id = v_company_id
  for update;

  if v_prescribed is null then
    raise exception 'Producto no encontrado en la receta';
  end if;

  v_pending := v_prescribed - v_dispensed;

  if p_quantity > v_pending then
    raise exception 'La cantidad despachada supera lo pendiente de la receta';
  end if;

  update pharmacy.prescription_items
  set quantity_dispensed = coalesce(quantity_dispensed, 0) + p_quantity
  where prescription_id = p_prescription_id
    and product_id = p_product_id;

  perform pharmacy.update_prescription_status(p_prescription_id);

  return true;
end;
$$;


ALTER FUNCTION "pharmacy"."increment_dispensed_quantity"("p_prescription_id" "uuid", "p_product_id" "uuid", "p_quantity" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "pharmacy"."log_audit_event"("p_event_type" "text", "p_description" "text", "p_metadata" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pharmacy', 'public'
    AS $$
declare
  v_company_id uuid;
  v_user_id uuid;
  v_audit_id uuid;
begin
  v_user_id := auth.uid();

  select company_id
  into v_company_id
  from public.company_users
  where user_id = v_user_id
  limit 1;

  if v_company_id is null then
    raise exception 'Usuario sin empresa asociada';
  end if;

  insert into pharmacy.audit_logs (
    company_id,
    user_id,
    event_type,
    description,
    metadata
  )
  values (
    v_company_id,
    v_user_id,
    p_event_type,
    p_description,
    coalesce(p_metadata, '{}'::jsonb)
  )
  returning id into v_audit_id;

  return v_audit_id;
end;
$$;


ALTER FUNCTION "pharmacy"."log_audit_event"("p_event_type" "text", "p_description" "text", "p_metadata" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "pharmacy"."mark_prescription_dispensed"("p_prescription_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pharmacy', 'public'
    AS $$
declare
  v_company_id uuid;
  v_rows int;
begin
  select company_id
  into v_company_id
  from public.company_users
  where user_id = auth.uid()
  limit 1;

  if v_company_id is null then
    raise exception 'Usuario sin empresa asociada';
  end if;

  update pharmacy.prescriptions
  set status = 'DISPENSED'
  where id = p_prescription_id
    and company_id = v_company_id
    and status = 'PENDING';

  get diagnostics v_rows = row_count;

  if v_rows = 0 then
    raise exception 'La receta no está disponible o ya fue despachada';
  end if;

  return true;
end;
$$;


ALTER FUNCTION "pharmacy"."mark_prescription_dispensed"("p_prescription_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "pharmacy"."process_pharmacy_sale"("p_warehouse_id" "uuid", "p_total_amount" numeric, "p_payment_method" "text", "p_document_number" "text", "p_patient_id" "uuid" DEFAULT NULL::"uuid", "p_prescription_id" "uuid" DEFAULT NULL::"uuid", "p_items" "jsonb" DEFAULT '[]'::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pharmacy', 'public'
    AS $$
declare
  v_user_id uuid;
  v_company_id uuid;
  v_session_id uuid;
  v_sale_id uuid;

  v_item jsonb;
  v_product_id uuid;
  v_quantity numeric;
  v_unit_price numeric;
  v_item_prescription_id uuid;

  v_remaining numeric;
  v_qty_to_deduct numeric;
  v_batch record;
  v_balance_after numeric;

  v_sale_condition text;
  v_product_prescription_type text;
  v_is_controlled boolean;

  v_prescription_status text;
  v_prescription_type text;
  v_prescription_patient_id uuid;
  v_qty_prescribed numeric;
  v_qty_dispensed numeric;
  v_qty_pending numeric;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception 'Usuario no autenticado';
  end if;

  select company_id
  into v_company_id
  from public.company_users
  where user_id = v_user_id
  limit 1;

  if v_company_id is null then
    raise exception 'Usuario sin empresa asociada';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'La venta no contiene productos';
  end if;

  select id
  into v_session_id
  from pharmacy.pos_sessions
  where company_id = v_company_id
    and user_id = v_user_id
    and warehouse_id = p_warehouse_id
    and status = 'OPEN'
  order by created_at desc
  limit 1
  for update;

  if v_session_id is null then
    raise exception 'Debes abrir caja antes de vender';
  end if;

  insert into pharmacy.sales (
    company_id,
    user_id,
    session_id,
    patient_id,
    total_amount,
    payment_method,
    document_number
  )
  values (
    v_company_id,
    v_user_id,
    v_session_id,
    p_patient_id,
    p_total_amount,
    coalesce(p_payment_method, 'CASH'),
    coalesce(p_document_number, 'TICKET-' || extract(epoch from now())::bigint)
  )
  returning id into v_sale_id;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_product_id := coalesce(
      nullif(v_item->>'product_id', '')::uuid,
      nullif(v_item->>'id', '')::uuid
    );

    v_item_prescription_id := coalesce(
      nullif(v_item->>'prescription_id', '')::uuid,
      p_prescription_id
    );

    v_quantity := coalesce((v_item->>'quantity')::numeric, 0);

    v_unit_price := coalesce(
      nullif(v_item->>'unit_price', '')::numeric,
      nullif(v_item->>'price_sale', '')::numeric,
      0
    );

    if v_product_id is null then
      raise exception 'Producto inválido en carrito';
    end if;

    if v_quantity <= 0 then
      raise exception 'Cantidad inválida para producto %', v_product_id;
    end if;

    select
      upper(coalesce(sale_condition, 'VD')),
      upper(coalesce(prescription_type, 'VENTA_LIBRE')),
      coalesce(is_controlled, false)
    into
      v_sale_condition,
      v_product_prescription_type,
      v_is_controlled
    from pharmacy.products
    where id = v_product_id
      and company_id = v_company_id;

    if v_sale_condition is null then
      raise exception 'Producto no encontrado o no pertenece a la empresa';
    end if;

    if v_is_controlled = true
       or v_sale_condition in ('R', 'RR', 'RCH')
       or v_product_prescription_type in ('RECETA_SIMPLE', 'RECETA_RETENIDA', 'RECETA_CHEQUE')
    then
      if v_item_prescription_id is null then
        raise exception 'El producto requiere receta médica válida';
      end if;

      select
        status,
        upper(coalesce(prescription_type, 'RECETA_SIMPLE')),
        patient_id
      into
        v_prescription_status,
        v_prescription_type,
        v_prescription_patient_id
      from pharmacy.prescriptions
      where id = v_item_prescription_id
        and company_id = v_company_id
      for update;

      if v_prescription_status is null then
        raise exception 'Receta no encontrada';
      end if;

      if v_prescription_status not in ('PENDING', 'PARTIAL') then
        raise exception 'La receta no está disponible para despacho';
      end if;

      if p_patient_id is not null and v_prescription_patient_id <> p_patient_id then
        raise exception 'La receta no pertenece al paciente seleccionado';
      end if;

      if v_sale_condition = 'RR'
         and v_prescription_type <> 'RECETA_RETENIDA'
      then
        raise exception 'Este producto requiere receta retenida';
      end if;

      if v_sale_condition = 'RCH'
         and v_prescription_type <> 'RECETA_CHEQUE'
      then
        raise exception 'Este producto requiere receta cheque';
      end if;

      if v_product_prescription_type = 'RECETA_RETENIDA'
         and v_prescription_type <> 'RECETA_RETENIDA'
      then
        raise exception 'Este producto requiere receta retenida';
      end if;

      if v_product_prescription_type = 'RECETA_CHEQUE'
         and v_prescription_type <> 'RECETA_CHEQUE'
      then
        raise exception 'Este producto requiere receta cheque';
      end if;

      select
        quantity_prescribed,
        coalesce(quantity_dispensed, 0)
      into
        v_qty_prescribed,
        v_qty_dispensed
      from pharmacy.prescription_items
      where prescription_id = v_item_prescription_id
        and product_id = v_product_id
      for update;

      if v_qty_prescribed is null then
        raise exception 'El producto no está incluido en la receta';
      end if;

      v_qty_pending := v_qty_prescribed - v_qty_dispensed;

      if v_qty_pending <= 0 then
        raise exception 'El producto ya fue completamente despachado en esta receta';
      end if;

      if v_quantity > v_qty_pending then
        raise exception 'La cantidad vendida supera la cantidad pendiente de la receta';
      end if;
    end if;

    v_remaining := v_quantity;

    for v_batch in
      select 
        b.id,
        b.product_id,
        b.batch_number,
        b.current_quantity,
        b.location_id,
        b.expiry_date
      from pharmacy.inventory_batches b
      join pharmacy.locations l on l.id = b.location_id
      where b.company_id = v_company_id
        and b.product_id = v_product_id
        and b.current_quantity > 0
        and l.company_id = v_company_id
        and l.warehouse_id = p_warehouse_id
        and upper(l.location_type) <> 'QUARANTINE'
      order by 
        case when upper(l.location_type) = 'SALES' then 0 else 1 end,
        b.expiry_date asc
      for update of b
    loop
      exit when v_remaining <= 0;

      v_qty_to_deduct := least(v_remaining, v_batch.current_quantity);

      update pharmacy.inventory_batches
      set current_quantity = current_quantity - v_qty_to_deduct
      where id = v_batch.id
        and company_id = v_company_id;

      insert into pharmacy.sale_items (
        company_id,
        sale_id,
        product_id,
        batch_id,
        quantity,
        unit_price,
        subtotal,
        prescription_id
      )
      values (
        v_company_id,
        v_sale_id,
        v_product_id,
        v_batch.id,
        v_qty_to_deduct,
        v_unit_price,
        v_qty_to_deduct * v_unit_price,
        v_item_prescription_id
      );

      select coalesce(sum(current_quantity), 0)
      into v_balance_after
      from pharmacy.inventory_batches
      where company_id = v_company_id
        and product_id = v_product_id
        and location_id = v_batch.location_id;

      insert into pharmacy.inventory_movements (
        company_id,
        product_id,
        batch_id,
        batch_number,
        from_location_id,
        movement_type,
        quantity,
        balance_after,
        reference_folio,
        created_by
      )
      values (
        v_company_id,
        v_product_id,
        v_batch.id,
        v_batch.batch_number,
        v_batch.location_id,
        'SALE',
        -abs(v_qty_to_deduct),
        v_balance_after,
        coalesce(p_document_number, 'VENTA_POS'),
        v_user_id
      );

      v_remaining := v_remaining - v_qty_to_deduct;
    end loop;

    if v_remaining > 0 then
      raise exception 'Stock insuficiente para el producto %. Faltan % unidades.', v_product_id, v_remaining;
    end if;

    if v_item_prescription_id is not null then
      update pharmacy.prescription_items
      set quantity_dispensed = coalesce(quantity_dispensed, 0) + v_quantity
      where prescription_id = v_item_prescription_id
        and product_id = v_product_id;
    end if;
  end loop;

  update pharmacy.prescriptions p
  set status = case
    when totals.total_dispensed <= 0 then 'PENDING'
    when totals.total_dispensed < totals.total_prescribed then 'PARTIAL'
    else 'DISPENSED'
  end
  from (
    select
      pi.prescription_id,
      sum(pi.quantity_prescribed) as total_prescribed,
      sum(coalesce(pi.quantity_dispensed, 0)) as total_dispensed
    from pharmacy.prescription_items pi
    where pi.prescription_id in (
      select distinct coalesce(
        nullif(item->>'prescription_id', '')::uuid,
        p_prescription_id
      )
      from jsonb_array_elements(p_items) item
      where coalesce(
        nullif(item->>'prescription_id', ''),
        p_prescription_id::text
      ) is not null
    )
    group by pi.prescription_id
  ) totals
  where p.id = totals.prescription_id
    and p.company_id = v_company_id;

  return jsonb_build_object(
    'sale_id', v_sale_id,
    'session_id', v_session_id,
    'company_id', v_company_id,
    'success', true
  );
end;
$$;


ALTER FUNCTION "pharmacy"."process_pharmacy_sale"("p_warehouse_id" "uuid", "p_total_amount" numeric, "p_payment_method" "text", "p_document_number" "text", "p_patient_id" "uuid", "p_prescription_id" "uuid", "p_items" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "pharmacy"."recalculate_prescription_type"("p_prescription_id" "uuid") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pharmacy', 'public'
    AS $$
declare
  v_type text;
begin
  select
    case
      when bool_or(p.sale_condition = 'RCH' or p.prescription_type = 'RECETA_CHEQUE')
        then 'RECETA_CHEQUE'
      when bool_or(p.sale_condition = 'RR' or p.prescription_type = 'RECETA_RETENIDA' or p.is_controlled = true)
        then 'RECETA_RETENIDA'
      else 'RECETA_SIMPLE'
    end
  into v_type
  from pharmacy.prescription_items pi
  join pharmacy.products p on p.id = pi.product_id
  where pi.prescription_id = p_prescription_id;

  v_type := coalesce(v_type, 'RECETA_SIMPLE');

  update pharmacy.prescriptions
  set prescription_type = v_type
  where id = p_prescription_id;

  return v_type;
end;
$$;


ALTER FUNCTION "pharmacy"."recalculate_prescription_type"("p_prescription_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "pharmacy"."reset_pos_operator_pin"("p_operator_id" "uuid", "p_new_pin" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
  v_company_id uuid;
begin
  select company_id into v_company_id
  from public.company_users
  where user_id = auth.uid()
  limit 1;

  update pharmacy.pos_operators
  set pin_hash = crypt(p_new_pin, gen_salt('bf'))
  where id = p_operator_id
    and company_id = v_company_id;

  return true;
end;
$$;


ALTER FUNCTION "pharmacy"."reset_pos_operator_pin"("p_operator_id" "uuid", "p_new_pin" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "pharmacy"."reset_pos_operator_pin"("p_operator_id" "uuid", "p_company_id" "uuid", "p_warehouse_id" "uuid", "p_pin_code" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
  -- 1. Validar que el PIN tenga exactamente 4 dígitos
  if p_pin_code is null or length(trim(p_pin_code)) <> 4 then
    raise exception 'El PIN debe tener exactamente 4 digitos';
  end if;

  -- 2. Actualizar el PIN encriptándolo con pgcrypto
  update pharmacy.pos_operators
  set pin_hash = crypt(trim(p_pin_code), gen_salt('bf'))
  where id = p_operator_id
    and company_id = p_company_id
    and warehouse_id = p_warehouse_id;

  -- 3. Confirmar que se encontró y actualizó el registro
  if not found then
    raise exception 'Operador POS no encontrado para la empresa/sucursal indicada';
  end if;

  return true;
end;
$$;


ALTER FUNCTION "pharmacy"."reset_pos_operator_pin"("p_operator_id" "uuid", "p_company_id" "uuid", "p_warehouse_id" "uuid", "p_pin_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "pharmacy"."set_po_number"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- Busca el número máximo actual para esa empresa y le suma 1
  SELECT COALESCE(MAX(po_number), 0) + 1 INTO NEW.po_number
  FROM pharmacy.purchase_orders
  WHERE company_id = NEW.company_id;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "pharmacy"."set_po_number"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "pharmacy"."trg_recalculate_prescription_type"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pharmacy', 'public'
    AS $$
begin
  if tg_op = 'DELETE' then
    perform pharmacy.recalculate_prescription_type(old.prescription_id);
    return old;
  else
    perform pharmacy.recalculate_prescription_type(new.prescription_id);
    return new;
  end if;
end;
$$;


ALTER FUNCTION "pharmacy"."trg_recalculate_prescription_type"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "pharmacy"."trg_set_prescription_validity"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pharmacy', 'public'
    AS $$
begin
  new.issued_at := coalesce(new.issued_at, now());

  new.valid_until := pharmacy.calculate_prescription_valid_until(
    coalesce(new.prescription_type, 'RECETA_SIMPLE'),
    new.issued_at
  );

  return new;
end;
$$;


ALTER FUNCTION "pharmacy"."trg_set_prescription_validity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "pharmacy"."update_prescription_status"("p_prescription_id" "uuid") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pharmacy', 'public'
    AS $$
declare
  v_total numeric;
  v_dispensed numeric;
  v_company_id uuid;
begin
  select company_id
  into v_company_id
  from public.company_users
  where user_id = auth.uid()
  limit 1;

  select 
    sum(quantity_prescribed),
    sum(quantity_dispensed)
  into v_total, v_dispensed
  from pharmacy.prescription_items pi
  join pharmacy.prescriptions p on p.id = pi.prescription_id
  where pi.prescription_id = p_prescription_id
    and p.company_id = v_company_id;

  if v_dispensed = 0 then
    update pharmacy.prescriptions
    set status = 'PENDING'
    where id = p_prescription_id;

    return 'PENDING';

  elsif v_dispensed < v_total then
    update pharmacy.prescriptions
    set status = 'PARTIAL'
    where id = p_prescription_id;

    return 'PARTIAL';

  else
    update pharmacy.prescriptions
    set status = 'DISPENSED'
    where id = p_prescription_id;

    return 'DISPENSED';
  end if;
end;
$$;


ALTER FUNCTION "pharmacy"."update_prescription_status"("p_prescription_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "pharmacy"."validate_prescription_pending"("p_prescription_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pharmacy', 'public'
    AS $$
declare
  v_company_id uuid;
  v_status text;
begin
  select company_id
  into v_company_id
  from public.company_users
  where user_id = auth.uid()
  limit 1;

  if v_company_id is null then
    raise exception 'Usuario sin empresa asociada';
  end if;

  select status
  into v_status
  from pharmacy.prescriptions
  where id = p_prescription_id
    and company_id = v_company_id
  for update;

  if v_status is null then
    raise exception 'Receta no encontrada';
  end if;

  if v_status <> 'PENDING' then
    raise exception 'Esta receta ya fue despachada o no está disponible';
  end if;

  return true;
end;
$$;


ALTER FUNCTION "pharmacy"."validate_prescription_pending"("p_prescription_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "pharmacy"."verify_pos_operator_pin"("p_operator_id" "uuid", "p_pin" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
  v_hash text;
  v_company_id uuid;
begin
  select company_id into v_company_id
  from public.company_users
  where user_id = auth.uid()
  limit 1;

  select pin_hash into v_hash
  from pharmacy.pos_operators
  where id = p_operator_id
    and company_id = v_company_id
    and is_active = true;

  if v_hash is null then
    return false;
  end if;

  return v_hash = crypt(p_pin, v_hash);
end;
$$;


ALTER FUNCTION "pharmacy"."verify_pos_operator_pin"("p_operator_id" "uuid", "p_pin" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "pharmacy"."verify_pos_operator_pin"("p_operator_id" "uuid", "p_company_id" "uuid", "p_warehouse_id" "uuid", "p_pin_code" "text") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  select exists (
    select 1
    from pharmacy.pos_operators po
    where po.id = p_operator_id
      and po.company_id = p_company_id
      and po.warehouse_id = p_warehouse_id
      and po.is_active = true
      and po.pin_hash = crypt(trim(p_pin_code), po.pin_hash)
  );
$$;


ALTER FUNCTION "pharmacy"."verify_pos_operator_pin"("p_operator_id" "uuid", "p_company_id" "uuid", "p_warehouse_id" "uuid", "p_pin_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."confirm_password_change"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
  -- Update the company_users table for the executing user
  update public.company_users
  set must_change_password = false
  where user_id = auth.uid();
  
  -- If no row was updated, it means the user has no company_users entry or something is wrong
  if not found then
    raise exception 'User not found in company_users or not authorized';
  end if;
end;
$$;


ALTER FUNCTION "public"."confirm_password_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_worker"("worker_email" "text", "worker_password" "text", "worker_full_name" "text", "worker_role" "text", "target_company_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    new_user_id uuid;
BEGIN
    -- 1. Insertar en auth.users
    INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, recovery_sent_at, last_sign_in_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token)
    VALUES (
        '00000000-0000-0000-0000-000000000000',
        gen_random_uuid(),
        'authenticated',
        'authenticated',
        worker_email,
        crypt(worker_password, gen_salt('bf')),
        now(),
        now(),
        now(),
        '{"provider":"email","providers":["email"]}',
        format('{"full_name":"%s"}', worker_full_name)::jsonb,
        now(),
        now(),
        '',
        '',
        '',
        ''
    )
    RETURNING id INTO new_user_id;

    -- 2. Insertar en nuestra tabla con must_change_password = TRUE
    INSERT INTO public.company_users (company_id, user_id, role, email, full_name, must_change_password)
    VALUES (target_company_id, new_user_id, worker_role, worker_email, worker_full_name, true);
END;
$$;


ALTER FUNCTION "public"."create_worker"("worker_email" "text", "worker_password" "text", "worker_full_name" "text", "worker_role" "text", "target_company_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."decrement_stock"("p_id" "uuid", "p_qty" numeric) RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    UPDATE products
    SET stock_quantity = stock_quantity - p_qty
    WHERE id = p_id;
END;
$$;


ALTER FUNCTION "public"."decrement_stock"("p_id" "uuid", "p_qty" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_companies"() RETURNS SETOF "uuid"
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  SELECT company_id FROM public.company_users WHERE user_id = auth.uid();
$$;


ALTER FUNCTION "public"."get_my_companies"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_company_id"() RETURNS "uuid"
    LANGUAGE "sql" STABLE
    AS $$
  SELECT 
    NULLIF(
      (current_setting('request.jwt.claims', true)::jsonb -> 'app_metadata' ->> 'company_id'),
      ''
    )::uuid;
$$;


ALTER FUNCTION "public"."get_my_company_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user_provisioning"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_company_id uuid;
  v_empresa_nombre text;
BEGIN
  -- Extraer el nombre de la empresa desde los metadatos brutos (inyectados por el Frontend)
  v_empresa_nombre := NEW.raw_user_meta_data->>'empresa_nombre';

  -- Solo aprovisionamos si el usuario entregó un nombre de empresa 
  -- (Esto previene conflictos cuando agreguemos invitaciones a empleados después)
  IF v_empresa_nombre IS NOT NULL THEN
      -- A. Crear la nueva empresa con plan TRIAL de 14 días
      INSERT INTO public.companies (name, plan_type, trial_ends_at)
      VALUES (
          v_empresa_nombre, 
          'TRIAL', 
          NOW() + INTERVAL '14 days'
      )
      RETURNING id INTO v_company_id;

      -- B. Vincular al usuario recién creado con su nueva empresa como Dueño
      -- OJO: Esto dispara tu trigger `sync_user_company_metadata`
      -- lo cual inyectará el company_id y role en el app_metadata correctamente.
      INSERT INTO public.company_users (company_id, user_id, role)
      VALUES (v_company_id, NEW.id, 'OWNER');
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_new_user_provisioning"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_purchase_order_number"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    next_number integer;
BEGIN
    -- Obtener el número máximo actual para esta empresa y sumarle 1
    -- Usamos COALESCE para que si es NULL (no hay órdenes para la empresa), empiece en 1
    SELECT COALESCE(MAX(po_number), 0) + 1 
    INTO next_number
    FROM public.purchase_orders 
    WHERE company_id = NEW.company_id;

    -- Asignar el nuevo número generado a la fila que se está insertando
    NEW.po_number := next_number;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."set_purchase_order_number"() OWNER TO "postgres";


CREATE PROCEDURE "public"."setup_saas_policies"(IN "target_table" "text")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    EXECUTE format('DROP POLICY IF EXISTS "saas_tenant_isolation" ON public.%I', target_table);
    
    EXECUTE format('
        CREATE POLICY "saas_tenant_isolation" ON public.%I 
        FOR ALL 
        USING (company_id = public.get_my_company_id())
        WITH CHECK (company_id = public.get_my_company_id())
    ', target_table);
END;
$$;


ALTER PROCEDURE "public"."setup_saas_policies"(IN "target_table" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_user_company_metadata"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  current_plan_type text;
  v_meta_jsonb jsonb;
BEGIN
    -- 1. Buscamos el plan
    SELECT plan_type INTO current_plan_type FROM public.companies WHERE id = NEW.company_id;

    v_meta_jsonb := jsonb_build_object(
        'company_id', NEW.company_id,
        'role', NEW.role,
        'plan_type', COALESCE(current_plan_type, 'TRIAL')
    );

    -- 2. Intentamos actualizar con el nombre moderno 'app_metadata'
    BEGIN
        UPDATE auth.users 
        SET app_metadata = COALESCE(app_metadata, '{}'::jsonb) || v_meta_jsonb
        WHERE id = NEW.user_id;
    EXCEPTION WHEN undefined_column THEN
        -- 3. Si falla, intentamos con el nombre legacy 'raw_app_meta_data'
        UPDATE auth.users 
        SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) || v_meta_jsonb
        WHERE id = NEW.user_id;
    END;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_user_company_metadata"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "pharmacy"."audit_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "event_type" "text" NOT NULL,
    "description" "text",
    "metadata" "jsonb",
    "ip_address" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "pharmacy"."audit_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "pharmacy"."cash_movements" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "session_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "movement_type" "text" NOT NULL,
    "amount" numeric NOT NULL,
    "reason" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "cash_movements_movement_type_check" CHECK (("movement_type" = ANY (ARRAY['IN'::"text", 'OUT'::"text"])))
);


ALTER TABLE "pharmacy"."cash_movements" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "pharmacy"."doctors" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "rut" "text" NOT NULL,
    "full_name" "text" NOT NULL,
    "specialty" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "pharmacy"."doctors" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "pharmacy"."inventory_batches" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "po_id" "uuid",
    "location_id" "uuid",
    "batch_number" "text" NOT NULL,
    "expiry_date" "date" NOT NULL,
    "initial_quantity" numeric DEFAULT 0 NOT NULL,
    "current_quantity" numeric DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "pharmacy"."inventory_batches" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "pharmacy"."inventory_movements" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "batch_id" "uuid",
    "batch_number" "text",
    "from_location_id" "uuid",
    "to_location_id" "uuid",
    "movement_type" "text" NOT NULL,
    "quantity" numeric NOT NULL,
    "unit_cost" numeric DEFAULT 0,
    "notes" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "receipt_id" "uuid",
    "source_location_id" "uuid",
    "destination_location_id" "uuid",
    "reference_folio" "text",
    "balance_after" numeric
);


ALTER TABLE "pharmacy"."inventory_movements" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "pharmacy"."inventory_receipts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "po_id" "uuid",
    "supplier_id" "uuid",
    "document_type" "text" NOT NULL,
    "document_number" "text" NOT NULL,
    "received_date" timestamp with time zone DEFAULT "now"(),
    "notes" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "inventory_receipts_document_type_check" CHECK (("document_type" = ANY (ARRAY['GUIA_DESPACHO'::"text", 'FACTURA'::"text", 'BOLETA'::"text", 'AJUSTE'::"text"])))
);


ALTER TABLE "pharmacy"."inventory_receipts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "pharmacy"."locations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "warehouse_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "location_type" "text" NOT NULL,
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "parent_location_id" "uuid",
    "barcode" "text",
    CONSTRAINT "locations_location_type_check" CHECK (("location_type" = ANY (ARRAY['QUARANTINE'::"text", 'STORAGE'::"text", 'SALES'::"text", 'COLD_CHAIN'::"text", 'SECURE'::"text"])))
);


ALTER TABLE "pharmacy"."locations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "pharmacy"."patients" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "rut" "text" NOT NULL,
    "full_name" "text" NOT NULL,
    "email" "text",
    "phone" "text",
    "birth_date" "date",
    "gender" "text",
    "allergies" "text"[],
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "pharmacy"."patients" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "pharmacy"."pos_sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "warehouse_id" "uuid" NOT NULL,
    "start_time" timestamp with time zone DEFAULT "now"(),
    "end_time" timestamp with time zone,
    "opening_balance" numeric DEFAULT 0 NOT NULL,
    "closing_balance" numeric,
    "difference" numeric,
    "status" "text" DEFAULT 'OPEN'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "operator_id" "uuid",
    "terminal_id" "uuid",
    CONSTRAINT "pos_sessions_status_check" CHECK (("status" = ANY (ARRAY['PENDING'::"text", 'OPEN'::"text", 'CLOSED'::"text"])))
);


ALTER TABLE "pharmacy"."pos_sessions" OWNER TO "postgres";


COMMENT ON COLUMN "pharmacy"."pos_sessions"."status" IS 'PENDING: Pre-abierta por admin, OPEN: Activa por cajero, CLOSED: Arqueada';



CREATE TABLE IF NOT EXISTS "pharmacy"."pos_terminals" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "warehouse_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "pharmacy"."pos_terminals" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "pharmacy"."prescription_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "prescription_id" "uuid" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "quantity_prescribed" numeric NOT NULL,
    "dosage_instructions" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "quantity_dispensed" numeric DEFAULT 0
);


ALTER TABLE "pharmacy"."prescription_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "pharmacy"."prescription_validity_rules" (
    "prescription_type" "text" NOT NULL,
    "validity_days" integer NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "pharmacy"."prescription_validity_rules" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "pharmacy"."prescriptions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "patient_id" "uuid" NOT NULL,
    "folio_electronico" "text",
    "prescriber_rut" "text" NOT NULL,
    "prescriber_name" "text" NOT NULL,
    "institution_name" "text",
    "status" "text" DEFAULT 'PENDING'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "created_by" "uuid",
    "prescription_type" "text" DEFAULT 'RECETA_SIMPLE'::"text",
    "issued_at" timestamp with time zone DEFAULT "now"(),
    "valid_until" timestamp with time zone,
    "expired_at" timestamp with time zone,
    CONSTRAINT "prescriptions_prescription_type_check" CHECK (("prescription_type" = ANY (ARRAY['RECETA_SIMPLE'::"text", 'RECETA_RETENIDA'::"text", 'RECETA_CHEQUE'::"text"]))),
    CONSTRAINT "prescriptions_status_check" CHECK (("status" = ANY (ARRAY['PENDING'::"text", 'PARTIAL'::"text", 'DISPENSED'::"text", 'EXPIRED'::"text", 'CANCELLED'::"text"])))
);


ALTER TABLE "pharmacy"."prescriptions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "pharmacy"."product_prices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "warehouse_id" "uuid" NOT NULL,
    "price_sale" numeric DEFAULT 0 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "pharmacy"."product_prices" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "pharmacy"."products" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "brand" "text",
    "dci" "text" NOT NULL,
    "registro_sanitario" "text" NOT NULL,
    "barcode" "text",
    "active_principle" "text",
    "concentration" "text",
    "presentation" "text",
    "is_bioequivalent" boolean DEFAULT false,
    "is_controlled" boolean DEFAULT false,
    "sale_condition" "text" NOT NULL,
    "stock_quantity" numeric DEFAULT 0,
    "min_stock" numeric DEFAULT 5,
    "price_sale" numeric DEFAULT 0 NOT NULL,
    "cost_unit" numeric DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "created_by" "uuid",
    "updated_by" "uuid",
    "active_ingredient" "text",
    "laboratory_name" "text",
    "isp_registry_number" "text",
    "unit_price" numeric DEFAULT 0,
    "purchase_uom" "text" DEFAULT 'CAJA'::"text",
    "sale_uom" "text" DEFAULT 'UNIDAD'::"text",
    "conversion_factor" numeric DEFAULT 1,
    "barcode_purchase" "text",
    "last_cost" numeric DEFAULT 0,
    "average_cost" numeric DEFAULT 0,
    "family" "text",
    "subfamily" "text",
    "prescription_type" "text" DEFAULT 'VENTA_LIBRE'::"text",
    CONSTRAINT "products_prescription_type_check" CHECK (("prescription_type" = ANY (ARRAY['VENTA_LIBRE'::"text", 'RECETA_SIMPLE'::"text", 'RECETA_RETENIDA'::"text", 'RECETA_CHEQUE'::"text"]))),
    CONSTRAINT "products_sale_condition_check" CHECK (("sale_condition" = ANY (ARRAY['VD'::"text", 'R'::"text", 'RR'::"text", 'RCH'::"text"]))),
    CONSTRAINT "valid_sale_condition" CHECK (("sale_condition" = ANY (ARRAY['VD'::"text", 'R'::"text", 'RR'::"text", 'RCH'::"text"])))
);


ALTER TABLE "pharmacy"."products" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "pharmacy"."purchase_order_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "po_id" "uuid" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "quantity" numeric NOT NULL,
    "unit_cost" numeric DEFAULT 0 NOT NULL,
    "total_cost" numeric DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "quantity_received" numeric DEFAULT 0,
    "updated_by" "uuid",
    "conversion_factor" numeric DEFAULT 1,
    CONSTRAINT "purchase_order_items_quantity_check" CHECK (("quantity" > (0)::numeric))
);


ALTER TABLE "pharmacy"."purchase_order_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "pharmacy"."purchase_orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "supplier_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'PENDING'::"text",
    "total_neto" numeric DEFAULT 0,
    "tax_amount" numeric DEFAULT 0,
    "total_amount" numeric DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "po_number" integer,
    "created_by" "uuid",
    "expected_delivery_date" "date",
    "issue_date" timestamp with time zone DEFAULT "now"(),
    "total_net" numeric DEFAULT 0,
    "observation_notes" "text",
    "payment_terms_days" integer,
    "updated_by" "uuid",
    "warehouse_id" "uuid",
    CONSTRAINT "purchase_orders_status_check" CHECK (("status" = ANY (ARRAY['PENDING'::"text", 'PARTIAL'::"text", 'RECEIVED'::"text", 'CANCELLED'::"text", 'DRAFT'::"text"])))
);


ALTER TABLE "pharmacy"."purchase_orders" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "pharmacy"."sale_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "sale_id" "uuid",
    "product_id" "uuid",
    "batch_id" "uuid",
    "quantity" numeric NOT NULL,
    "unit_price" numeric NOT NULL,
    "subtotal" numeric NOT NULL,
    "company_id" "uuid",
    "prescription_id" "uuid"
);


ALTER TABLE "pharmacy"."sale_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "pharmacy"."sales" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "patient_id" "uuid",
    "total_amount" numeric NOT NULL,
    "payment_method" "text",
    "document_number" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "session_id" "uuid",
    CONSTRAINT "sales_payment_method_check" CHECK (("payment_method" = ANY (ARRAY['CASH'::"text", 'CARD'::"text", 'TRANSFER'::"text"])))
);


ALTER TABLE "pharmacy"."sales" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "pharmacy"."suppliers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "rut" "text" NOT NULL,
    "legal_name" "text" NOT NULL,
    "commercial_name" "text",
    "business_line" "text" DEFAULT 'Laboratorio Farmacéutico'::"text",
    "contact_email" "text",
    "contact_phone" "text",
    "address" "text",
    "isp_resolution_number" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "created_by" "uuid",
    "updated_by" "uuid",
    "legal_representative" "text",
    "contact_person_name" "text",
    "contact_person_role" "text",
    "address_city" "text",
    "address_commune" "text",
    "website_url" "text",
    "social_media_links" "jsonb" DEFAULT '{}'::"jsonb",
    "payment_terms_days" integer DEFAULT 30,
    "bank_details" "jsonb" DEFAULT '{}'::"jsonb",
    "observation_notes" "text",
    "compliance_rate" numeric DEFAULT 100,
    "average_delivery_days" integer
);


ALTER TABLE "pharmacy"."suppliers" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "pharmacy"."transfer_folio_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "pharmacy"."transfer_folio_seq" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "pharmacy"."transfer_request_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "transfer_request_id" "uuid" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "batch_id" "uuid" NOT NULL,
    "source_location_id" "uuid" NOT NULL,
    "quantity" numeric NOT NULL,
    "company_id" "uuid",
    "destination_location_id" "uuid",
    "status" "text" DEFAULT 'PENDING'::"text",
    "received_quantity" numeric,
    CONSTRAINT "transfer_request_items_quantity_check" CHECK (("quantity" > (0)::numeric))
);


ALTER TABLE "pharmacy"."transfer_request_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "pharmacy"."transfer_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "source_warehouse_id" "uuid" NOT NULL,
    "destination_warehouse_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'PENDING'::"text",
    "requested_by" "uuid",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "folio" "text" DEFAULT ('TR-'::"text" || "lpad"(("nextval"('"pharmacy"."transfer_folio_seq"'::"regclass"))::"text", 6, '0'::"text")),
    "dispatch_guide" "text",
    CONSTRAINT "transfer_requests_status_check" CHECK (("status" = ANY (ARRAY['PENDING'::"text", 'IN_TRANSIT'::"text", 'COMPLETED'::"text", 'CANCELLED'::"text"])))
);


ALTER TABLE "pharmacy"."transfer_requests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "pharmacy"."warehouses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "created_by" "uuid",
    "description" "text",
    "address" "text",
    "city" "text" DEFAULT 'San Javier'::"text",
    "manager_name" "text",
    "phone" "text",
    "opening_hours" "jsonb"
);


ALTER TABLE "pharmacy"."warehouses" OWNER TO "postgres";


CREATE OR REPLACE VIEW "pharmacy"."v_kardex_professional" AS
 SELECT "m"."created_at" AS "fecha",
    "p"."id" AS "product_id",
    "p"."name" AS "producto",
    "p"."dci",
    "w"."id" AS "warehouse_id",
    "w"."name" AS "sucursal",
    "l"."name" AS "bodega_ubicacion",
        CASE
            WHEN ("m"."movement_type" = 'IN_PURCHASE'::"text") THEN 'Ingreso por Compra'::"text"
            WHEN ("m"."movement_type" = 'PURCHASE_RECEIPT'::"text") THEN 'Ingreso por Compra'::"text"
            WHEN ("m"."movement_type" = 'INBOUND_TRANSFER'::"text") THEN 'Recepción de Traspaso'::"text"
            WHEN ("m"."movement_type" = 'OUTBOUND_TRANSFER'::"text") THEN 'Envío a Sucursal'::"text"
            WHEN ("m"."movement_type" = 'INTERNAL_TRANSFER'::"text") THEN 'Acomodo Interno'::"text"
            WHEN ("m"."movement_type" = 'SALE'::"text") THEN 'Venta a Público'::"text"
            WHEN ("m"."movement_type" = 'ADJUSTMENT_IN'::"text") THEN 'Ajuste de Inventario (+)'::"text"
            WHEN ("m"."movement_type" = 'ADJUSTMENT_OUT'::"text") THEN 'Ajuste de Inventario (-)'::"text"
            ELSE "m"."movement_type"
        END AS "tipo_movimiento_humano",
    "m"."reference_folio" AS "referencia",
    "b"."batch_number" AS "lote",
        CASE
            WHEN ("m"."quantity" > (0)::numeric) THEN "m"."quantity"
            ELSE (0)::numeric
        END AS "entrada",
        CASE
            WHEN ("m"."quantity" < (0)::numeric) THEN "abs"("m"."quantity")
            ELSE (0)::numeric
        END AS "salida",
    "m"."balance_after" AS "saldo_acumulado"
   FROM (((("pharmacy"."inventory_movements" "m"
     JOIN "pharmacy"."inventory_batches" "b" ON (("m"."batch_id" = "b"."id")))
     JOIN "pharmacy"."products" "p" ON (("b"."product_id" = "p"."id")))
     JOIN "pharmacy"."locations" "l" ON (("b"."location_id" = "l"."id")))
     JOIN "pharmacy"."warehouses" "w" ON (("l"."warehouse_id" = "w"."id")));


ALTER VIEW "pharmacy"."v_kardex_professional" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cash_movements" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "session_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "movement_type" "text" NOT NULL,
    "amount" numeric NOT NULL,
    "reason" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "cash_movements_movement_type_check" CHECK (("movement_type" = ANY (ARRAY['IN'::"text", 'OUT'::"text"])))
);


ALTER TABLE "public"."cash_movements" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."companies" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "name" "text" NOT NULL,
    "business_type" "text",
    "active" boolean DEFAULT true,
    "fantasy_name" "text",
    "legal_name" "text",
    "rut" "text",
    "activity" "text",
    "address" "text",
    "city" "text",
    "phone" "text",
    "logo_url" "text",
    "receipt_message" "text" DEFAULT '¡Gracias por su compra!'::"text",
    "created_by" "uuid" DEFAULT "auth"."uid"(),
    "pos_close_mode" "text" DEFAULT 'TRANSPARENT'::"text",
    "plan_type" character varying(50) DEFAULT 'TRIAL'::character varying,
    "trial_ends_at" timestamp with time zone,
    "stripe_customer_id" character varying(255),
    "stripe_subscription_id" character varying(255),
    "subscription_status" character varying(50) DEFAULT 'trialing'::character varying,
    "stripe_price_id" "text",
    "current_period_end" timestamp with time zone,
    "po_approval_threshold" numeric(15,2) DEFAULT 0,
    CONSTRAINT "companies_pos_close_mode_check" CHECK (("pos_close_mode" = ANY (ARRAY['TRANSPARENT'::"text", 'BLIND'::"text"])))
);


ALTER TABLE "public"."companies" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."company_users" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid",
    "user_id" "uuid",
    "role" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "email" "text",
    "full_name" "text",
    "must_change_password" boolean DEFAULT true,
    "app_access" "text"[] DEFAULT '{POS}'::"text"[],
    "module_roles" "jsonb" DEFAULT '{}'::"jsonb",
    CONSTRAINT "company_users_role_check" CHECK (("role" = ANY (ARRAY['OWNER'::"text", 'MANAGER'::"text", 'CASHIER'::"text", 'STOCKER'::"text", 'MEMBER'::"text"])))
);


ALTER TABLE "public"."company_users" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customer_payments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "cashier_id" "uuid",
    "amount" numeric NOT NULL,
    "payment_method" "text" DEFAULT 'CASH'::"text",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "session_id" "uuid",
    CONSTRAINT "customer_payments_payment_method_check" CHECK (("payment_method" = ANY (ARRAY['CASH'::"text", 'CARD'::"text", 'TRANSFER'::"text"])))
);


ALTER TABLE "public"."customer_payments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "phone" "text",
    "debt_balance" numeric DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "rut" "text",
    "email" "text",
    "address" "text",
    "notes" "text",
    "credit_limit" numeric DEFAULT 50000,
    "next_due_date" "date"
);


ALTER TABLE "public"."customers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."expenses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "category" "text" NOT NULL,
    "amount" numeric NOT NULL,
    "description" "text" NOT NULL,
    "expense_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "po_id" "uuid",
    "supplier_id" "uuid",
    "document_number" character varying,
    "due_date" "date",
    "status" character varying(20) DEFAULT 'PENDING_PAYMENT'::character varying,
    "receipt_id" "uuid",
    "paid_amount" numeric(15,2) DEFAULT 0,
    "internal_id" character varying(50),
    CONSTRAINT "expenses_category_check" CHECK (("category" = ANY (ARRAY['SERVICIOS_BASICOS'::"text", 'ARRIENDO'::"text", 'SUELDOS'::"text", 'MANTENCION'::"text", 'INSUMOS'::"text", 'OTROS'::"text"])))
);


ALTER TABLE "public"."expenses" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."inventory_movements" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "movement_type" "text" NOT NULL,
    "quantity" numeric NOT NULL,
    "reason" "text",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "receipt_id" "uuid",
    "batch_id" "uuid",
    CONSTRAINT "inventory_movements_movement_type_check" CHECK (("movement_type" = ANY (ARRAY['IN'::"text", 'OUT'::"text", 'ADJUSTMENT'::"text", 'INITIAL_LOAD'::"text"])))
);


ALTER TABLE "public"."inventory_movements" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."inventory_receipts" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "po_id" "uuid",
    "supplier_id" "uuid",
    "receipt_number" integer NOT NULL,
    "status" character varying(20) DEFAULT 'DONE'::character varying,
    "document_type" character varying(20),
    "document_number" character varying(50),
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "created_by" "uuid"
);


ALTER TABLE "public"."inventory_receipts" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."inventory_receipts_receipt_number_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."inventory_receipts_receipt_number_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."inventory_receipts_receipt_number_seq" OWNED BY "public"."inventory_receipts"."receipt_number";



CREATE TABLE IF NOT EXISTS "public"."landed_cost_allocations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "expense_id" "uuid",
    "receipt_id" "uuid",
    "allocated_amount" numeric(15,2) NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "created_by" "uuid",
    CONSTRAINT "landed_cost_allocations_allocated_amount_check" CHECK (("allocated_amount" > (0)::numeric))
);


ALTER TABLE "public"."landed_cost_allocations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pos_sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "cashier_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'OPEN'::"text",
    "opened_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "closed_at" timestamp with time zone,
    "initial_cash" numeric DEFAULT 0,
    "expected_cash" numeric,
    "declared_cash" numeric,
    "notes" "text",
    CONSTRAINT "pos_sessions_status_check" CHECK (("status" = ANY (ARRAY['OPEN'::"text", 'CLOSED'::"text"])))
);


ALTER TABLE "public"."pos_sessions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."product_batches" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "po_id" "uuid",
    "quantity_received" numeric NOT NULL,
    "expiry_date" "date" NOT NULL,
    "status" "text" DEFAULT 'ACTIVE'::"text",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "unit_cost" numeric(12,2) DEFAULT 0,
    "quantity_remaining" numeric,
    CONSTRAINT "product_batches_status_check" CHECK (("status" = ANY (ARRAY['ACTIVE'::"text", 'DISMISSED'::"text", 'EXHAUSTED'::"text", 'DEPLETED'::"text"])))
);


ALTER TABLE "public"."product_batches" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."product_categories" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid",
    "name" character varying(100) NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."product_categories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."products" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "name" "text" NOT NULL,
    "barcode" "text",
    "price" numeric DEFAULT 0 NOT NULL,
    "stock_quantity" numeric DEFAULT 0,
    "unit_type" "text" DEFAULT 'UN'::"text",
    "image_url" "text",
    "active" boolean DEFAULT true,
    "cost_price" numeric DEFAULT 0,
    "category" "text" DEFAULT 'General'::"text",
    "supplier_id" "uuid",
    "minimum_stock" numeric DEFAULT 5,
    "wholesale_price" numeric DEFAULT 0,
    "wholesale_min_quantity" integer DEFAULT 0,
    "internal_reference" character varying(100),
    "product_type" character varying(50) DEFAULT 'STORABLE'::character varying,
    "can_be_purchased" boolean DEFAULT true,
    "can_be_sold" boolean DEFAULT true,
    "weight" numeric(10,2),
    "volume" numeric(10,3),
    "supplier_lead_time" integer DEFAULT 0,
    "purchase_notes" "text",
    "receipt_notes" "text",
    "category_id" "uuid",
    "currency_purchase" character varying(10) DEFAULT 'CLP'::character varying,
    "currency_sale" character varying(10) DEFAULT 'CLP'::character varying,
    "currency" character varying(10) DEFAULT 'CLP'::character varying,
    CONSTRAINT "products_unit_type_check" CHECK (("unit_type" = ANY (ARRAY['UN'::"text", 'KG'::"text"])))
);


ALTER TABLE "public"."products" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."promotions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid",
    "name" "text" NOT NULL,
    "promo_type" "text" NOT NULL,
    "target_product_id" "uuid",
    "discount_percentage" numeric DEFAULT 0,
    "fixed_promo_price" numeric DEFAULT 0,
    "trigger_product_id" "uuid",
    "trigger_qty" integer DEFAULT 1,
    "reward_product_id" "uuid",
    "reward_discount_percentage" numeric DEFAULT 0,
    "start_date" timestamp with time zone NOT NULL,
    "end_date" timestamp with time zone NOT NULL,
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"())
);


ALTER TABLE "public"."promotions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."purchase_order_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "po_id" "uuid" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "quantity" numeric NOT NULL,
    "unit_cost" numeric NOT NULL,
    "total_cost" numeric NOT NULL,
    "received_quantity" numeric(15,3) DEFAULT 0,
    "company_id" "uuid"
);


ALTER TABLE "public"."purchase_order_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."purchase_order_lines" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "purchase_order_id" "uuid",
    "supplier_product_id" "uuid",
    "description" character varying(255),
    "quantity" numeric(10,2),
    "unit_price" numeric(12,2),
    "tax_rate" numeric(5,2) DEFAULT 19.00,
    "line_total" numeric(12,2),
    "received_quantity" numeric(10,2) DEFAULT 0,
    "company_id" "uuid" DEFAULT "public"."get_my_company_id"()
);


ALTER TABLE "public"."purchase_order_lines" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."purchase_orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "supplier_id" "uuid" NOT NULL,
    "created_by" "uuid" NOT NULL,
    "status" "text" DEFAULT 'PENDING'::"text",
    "total_amount" numeric DEFAULT 0,
    "expected_delivery_date" "date",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "document_type" "text",
    "document_number" "text",
    "document_date" "date",
    "received_at" timestamp with time zone,
    "issue_date" "date" DEFAULT CURRENT_DATE,
    "subtotal" numeric(12,2) DEFAULT 0,
    "tax_amount" numeric(12,2) DEFAULT 0,
    "po_number" integer,
    "billing_status" character varying(20) DEFAULT 'NOT_BILLED'::character varying,
    "approved_by" "uuid",
    "approval_date" timestamp with time zone,
    CONSTRAINT "purchase_orders_document_type_check" CHECK (("document_type" = ANY (ARRAY['FACTURA'::"text", 'GUIA_DESPACHO'::"text", 'BOLETA'::"text", 'OTRO'::"text"]))),
    CONSTRAINT "purchase_orders_status_check" CHECK (("status" = ANY (ARRAY['DRAFT'::"text", 'WAITING_APPROVAL'::"text", 'PENDING'::"text", 'PARTIAL'::"text", 'RECEIVED'::"text", 'CANCELLED'::"text"])))
);


ALTER TABLE "public"."purchase_orders" OWNER TO "postgres";


COMMENT ON COLUMN "public"."purchase_orders"."document_type" IS 'Tipo de documento presentado en la recepción física';



COMMENT ON COLUMN "public"."purchase_orders"."document_number" IS 'Folio o número de identificación del documento de recepción';



COMMENT ON COLUMN "public"."purchase_orders"."document_date" IS 'Fecha de emisión del documento de recepción';



CREATE TABLE IF NOT EXISTS "public"."sale_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "sale_id" "uuid",
    "company_id" "uuid",
    "product_id" "uuid",
    "product_name" "text" NOT NULL,
    "quantity" numeric NOT NULL,
    "price_at_time" numeric NOT NULL
);


ALTER TABLE "public"."sale_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sales" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "company_id" "uuid",
    "cashier_id" "uuid",
    "total_amount" numeric NOT NULL,
    "net_amount" numeric NOT NULL,
    "tax_amount" numeric NOT NULL,
    "payment_method" "text",
    "customer_id" "uuid",
    "session_id" "uuid",
    "total_cost" numeric DEFAULT 0,
    CONSTRAINT "sales_payment_method_check" CHECK (("payment_method" = ANY (ARRAY['CASH'::"text", 'CARD'::"text", 'TRANSFER'::"text", 'CREDIT'::"text"])))
);


ALTER TABLE "public"."sales" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."supplier_payments" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "expense_id" "uuid",
    "amount" numeric(15,2) NOT NULL,
    "payment_date" "date" NOT NULL,
    "payment_method" character varying(50),
    "reference_number" character varying(100),
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "created_by" "uuid"
);


ALTER TABLE "public"."supplier_payments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."supplier_products" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "company_id" "uuid",
    "supplier_id" "uuid",
    "product_name" character varying(255),
    "supplier_sku" character varying(100),
    "cost_price" numeric(12,2),
    "last_updated" timestamp with time zone DEFAULT "now"(),
    "product_id" "uuid"
);


ALTER TABLE "public"."supplier_products" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."suppliers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "rut" "text",
    "contact_name" "text",
    "phone" "text",
    "email" "text",
    "address" "text",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "legal_name" "text",
    "business_line" "text",
    "bank_name" "text",
    "bank_account_type" "text",
    "bank_account_number" "text",
    "billing_email" "text",
    "payment_terms" "text" DEFAULT 'CONTADO'::"text",
    "delivery_days" "text",
    "logo_url" "text",
    "business_name" character varying(255),
    "fantasy_name" character varying(255),
    "giro" character varying(255),
    "contact_person" character varying(255)
);


ALTER TABLE "public"."suppliers" OWNER TO "postgres";


ALTER TABLE ONLY "public"."inventory_receipts" ALTER COLUMN "receipt_number" SET DEFAULT "nextval"('"public"."inventory_receipts_receipt_number_seq"'::"regclass");



ALTER TABLE ONLY "pharmacy"."audit_logs"
    ADD CONSTRAINT "audit_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "pharmacy"."cash_movements"
    ADD CONSTRAINT "cash_movements_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "pharmacy"."doctors"
    ADD CONSTRAINT "doctors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "pharmacy"."doctors"
    ADD CONSTRAINT "doctors_rut_unique" UNIQUE ("company_id", "rut");



ALTER TABLE ONLY "pharmacy"."inventory_batches"
    ADD CONSTRAINT "inventory_batches_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "pharmacy"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "pharmacy"."inventory_receipts"
    ADD CONSTRAINT "inventory_receipts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "pharmacy"."locations"
    ADD CONSTRAINT "locations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "pharmacy"."locations"
    ADD CONSTRAINT "locations_warehouse_name_unique" UNIQUE ("warehouse_id", "name");



ALTER TABLE ONLY "pharmacy"."patients"
    ADD CONSTRAINT "patients_company_id_rut_key" UNIQUE ("company_id", "rut");



ALTER TABLE ONLY "pharmacy"."patients"
    ADD CONSTRAINT "patients_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "pharmacy"."pos_operators"
    ADD CONSTRAINT "pos_operators_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "pharmacy"."pos_sessions"
    ADD CONSTRAINT "pos_sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "pharmacy"."pos_terminals"
    ADD CONSTRAINT "pos_terminals_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "pharmacy"."prescription_items"
    ADD CONSTRAINT "prescription_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "pharmacy"."prescription_validity_rules"
    ADD CONSTRAINT "prescription_validity_rules_pkey" PRIMARY KEY ("prescription_type");



ALTER TABLE ONLY "pharmacy"."prescriptions"
    ADD CONSTRAINT "prescriptions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "pharmacy"."product_prices"
    ADD CONSTRAINT "product_prices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "pharmacy"."products"
    ADD CONSTRAINT "products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "pharmacy"."purchase_order_items"
    ADD CONSTRAINT "purchase_order_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "pharmacy"."purchase_orders"
    ADD CONSTRAINT "purchase_orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "pharmacy"."sale_items"
    ADD CONSTRAINT "sale_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "pharmacy"."sales"
    ADD CONSTRAINT "sales_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "pharmacy"."suppliers"
    ADD CONSTRAINT "suppliers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "pharmacy"."transfer_request_items"
    ADD CONSTRAINT "transfer_request_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "pharmacy"."transfer_requests"
    ADD CONSTRAINT "transfer_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "pharmacy"."product_prices"
    ADD CONSTRAINT "unique_product_per_warehouse" UNIQUE ("product_id", "warehouse_id");



ALTER TABLE ONLY "pharmacy"."warehouses"
    ADD CONSTRAINT "warehouses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cash_movements"
    ADD CONSTRAINT "cash_movements_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."companies"
    ADD CONSTRAINT "companies_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."company_users"
    ADD CONSTRAINT "company_users_company_id_user_id_key" UNIQUE ("company_id", "user_id");



ALTER TABLE ONLY "public"."company_users"
    ADD CONSTRAINT "company_users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customer_payments"
    ADD CONSTRAINT "customer_payments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inventory_receipts"
    ADD CONSTRAINT "inventory_receipts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."landed_cost_allocations"
    ADD CONSTRAINT "landed_cost_allocations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pos_sessions"
    ADD CONSTRAINT "pos_sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."product_batches"
    ADD CONSTRAINT "product_batches_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."product_categories"
    ADD CONSTRAINT "product_categories_company_id_name_key" UNIQUE ("company_id", "name");



ALTER TABLE ONLY "public"."product_categories"
    ADD CONSTRAINT "product_categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."promotions"
    ADD CONSTRAINT "promotions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."purchase_order_items"
    ADD CONSTRAINT "purchase_order_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."purchase_order_lines"
    ADD CONSTRAINT "purchase_order_lines_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."purchase_orders"
    ADD CONSTRAINT "purchase_orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sale_items"
    ADD CONSTRAINT "sale_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales"
    ADD CONSTRAINT "sales_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."supplier_payments"
    ADD CONSTRAINT "supplier_payments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."supplier_products"
    ADD CONSTRAINT "supplier_products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_batches_company_current_qty" ON "pharmacy"."inventory_batches" USING "btree" ("company_id", "current_quantity");



CREATE INDEX "idx_batches_company_product_location" ON "pharmacy"."inventory_batches" USING "btree" ("company_id", "product_id", "location_id");



CREATE INDEX "idx_batches_product_expiry" ON "pharmacy"."inventory_batches" USING "btree" ("product_id", "expiry_date");



CREATE INDEX "idx_cash_movements_company_session" ON "pharmacy"."cash_movements" USING "btree" ("company_id", "session_id");



CREATE INDEX "idx_inventory_movements_company_batch" ON "pharmacy"."inventory_movements" USING "btree" ("company_id", "batch_id");



CREATE INDEX "idx_inventory_movements_company_product_created" ON "pharmacy"."inventory_movements" USING "btree" ("company_id", "product_id", "created_at" DESC);



CREATE INDEX "idx_locations_company_warehouse_type" ON "pharmacy"."locations" USING "btree" ("company_id", "warehouse_id", "location_type");



CREATE INDEX "idx_operators_company_warehouse_active" ON "pharmacy"."pos_operators" USING "btree" ("company_id", "warehouse_id", "is_active");



CREATE INDEX "idx_patients_company_name" ON "pharmacy"."patients" USING "btree" ("company_id", "full_name");



CREATE INDEX "idx_patients_company_rut" ON "pharmacy"."patients" USING "btree" ("company_id", "rut");



CREATE INDEX "idx_pharmacy_inventory_batches_company_product_location_qty" ON "pharmacy"."inventory_batches" USING "btree" ("company_id", "product_id", "location_id", "current_quantity");



CREATE INDEX "idx_pharmacy_locations_company_warehouse_type" ON "pharmacy"."locations" USING "btree" ("company_id", "warehouse_id", "location_type");



CREATE INDEX "idx_pharmacy_product_prices_company_warehouse_product" ON "pharmacy"."product_prices" USING "btree" ("company_id", "warehouse_id", "product_id");



CREATE INDEX "idx_pharmacy_products_company_barcode" ON "pharmacy"."products" USING "btree" ("company_id", "barcode");



CREATE INDEX "idx_pharmacy_products_company_brand" ON "pharmacy"."products" USING "btree" ("company_id", "brand");



CREATE INDEX "idx_pharmacy_products_company_dci" ON "pharmacy"."products" USING "btree" ("company_id", "dci");



CREATE INDEX "idx_pharmacy_products_company_laboratory_name" ON "pharmacy"."products" USING "btree" ("company_id", "laboratory_name");



CREATE INDEX "idx_pharmacy_products_company_name" ON "pharmacy"."products" USING "btree" ("company_id", "name");



CREATE INDEX "idx_pos_operators_company" ON "pharmacy"."pos_operators" USING "btree" ("company_id");



CREATE INDEX "idx_pos_operators_company_warehouse_active" ON "pharmacy"."pos_operators" USING "btree" ("company_id", "warehouse_id", "is_active");



CREATE INDEX "idx_pos_operators_warehouse" ON "pharmacy"."pos_operators" USING "btree" ("warehouse_id");



CREATE INDEX "idx_pos_sessions_company_warehouse_status" ON "pharmacy"."pos_sessions" USING "btree" ("company_id", "warehouse_id", "status");



CREATE INDEX "idx_pos_sessions_operator" ON "pharmacy"."pos_sessions" USING "btree" ("operator_id");



CREATE INDEX "idx_prescriptions_company_folio" ON "pharmacy"."prescriptions" USING "btree" ("company_id", "folio_electronico");



CREATE INDEX "idx_prescriptions_company_patient_status" ON "pharmacy"."prescriptions" USING "btree" ("company_id", "patient_id", "status");



CREATE INDEX "idx_prices_company_warehouse_product" ON "pharmacy"."product_prices" USING "btree" ("company_id", "warehouse_id", "product_id");



CREATE INDEX "idx_products_company_barcode" ON "pharmacy"."products" USING "btree" ("company_id", "barcode");



CREATE INDEX "idx_products_company_dci" ON "pharmacy"."products" USING "btree" ("company_id", "dci");



CREATE INDEX "idx_products_company_laboratory" ON "pharmacy"."products" USING "btree" ("company_id", "laboratory_name");



CREATE INDEX "idx_products_company_name" ON "pharmacy"."products" USING "btree" ("company_id", "name");



CREATE INDEX "idx_purchase_orders_company_supplier_status" ON "pharmacy"."purchase_orders" USING "btree" ("company_id", "supplier_id", "status");



CREATE INDEX "idx_purchase_orders_company_warehouse_status" ON "pharmacy"."purchase_orders" USING "btree" ("company_id", "warehouse_id", "status");



CREATE INDEX "idx_sale_items_company_sale" ON "pharmacy"."sale_items" USING "btree" ("company_id", "sale_id");



CREATE INDEX "idx_sales_company_session_created" ON "pharmacy"."sales" USING "btree" ("company_id", "session_id", "created_at" DESC);



CREATE INDEX "idx_sessions_company_warehouse_status" ON "pharmacy"."pos_sessions" USING "btree" ("company_id", "warehouse_id", "status");



CREATE INDEX "idx_suppliers_company_rut" ON "pharmacy"."suppliers" USING "btree" ("company_id", "rut");



CREATE INDEX "idx_terminals_company_warehouse" ON "pharmacy"."pos_terminals" USING "btree" ("company_id", "warehouse_id");



CREATE INDEX "idx_transfer_requests_company_destination_status" ON "pharmacy"."transfer_requests" USING "btree" ("company_id", "destination_warehouse_id", "status");



CREATE INDEX "idx_transfer_requests_company_source_status" ON "pharmacy"."transfer_requests" USING "btree" ("company_id", "source_warehouse_id", "status");



CREATE UNIQUE INDEX "ux_pos_operators_company_warehouse_name" ON "pharmacy"."pos_operators" USING "btree" ("company_id", "warehouse_id", "full_name");



CREATE UNIQUE INDEX "ux_pos_sessions_open_operator" ON "pharmacy"."pos_sessions" USING "btree" ("company_id", "warehouse_id", "operator_id") WHERE ("status" = 'OPEN'::"text");



CREATE INDEX "idx_expenses_internal_id" ON "public"."expenses" USING "btree" ("internal_id");



CREATE INDEX "idx_lca_company_id" ON "public"."landed_cost_allocations" USING "btree" ("company_id");



CREATE INDEX "idx_lca_expense_id" ON "public"."landed_cost_allocations" USING "btree" ("expense_id");



CREATE INDEX "idx_lca_receipt_id" ON "public"."landed_cost_allocations" USING "btree" ("receipt_id");



CREATE INDEX "idx_po_waiting_approval" ON "public"."purchase_orders" USING "btree" ("company_id", "status") WHERE ("status" = 'WAITING_APPROVAL'::"text");



CREATE OR REPLACE TRIGGER "prescription_items_recalculate_type" AFTER INSERT OR DELETE OR UPDATE ON "pharmacy"."prescription_items" FOR EACH ROW EXECUTE FUNCTION "pharmacy"."trg_recalculate_prescription_type"();



CREATE OR REPLACE TRIGGER "prescriptions_set_validity" BEFORE INSERT OR UPDATE OF "prescription_type", "issued_at" ON "pharmacy"."prescriptions" FOR EACH ROW EXECUTE FUNCTION "pharmacy"."trg_set_prescription_validity"();



CREATE OR REPLACE TRIGGER "trg_set_po_number_pharmacy" BEFORE INSERT ON "pharmacy"."purchase_orders" FOR EACH ROW EXECUTE FUNCTION "pharmacy"."set_po_number"();



CREATE OR REPLACE TRIGGER "tr_sync_user_company_metadata" AFTER INSERT OR UPDATE ON "public"."company_users" FOR EACH ROW EXECUTE FUNCTION "public"."sync_user_company_metadata"();



CREATE OR REPLACE TRIGGER "trigger_set_purchase_order_number" BEFORE INSERT ON "public"."purchase_orders" FOR EACH ROW EXECUTE FUNCTION "public"."set_purchase_order_number"();



ALTER TABLE ONLY "pharmacy"."audit_logs"
    ADD CONSTRAINT "audit_logs_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");



ALTER TABLE ONLY "pharmacy"."audit_logs"
    ADD CONSTRAINT "audit_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "pharmacy"."cash_movements"
    ADD CONSTRAINT "cash_movements_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");



ALTER TABLE ONLY "pharmacy"."cash_movements"
    ADD CONSTRAINT "cash_movements_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "pharmacy"."pos_sessions"("id");



ALTER TABLE ONLY "pharmacy"."cash_movements"
    ADD CONSTRAINT "cash_movements_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "pharmacy"."doctors"
    ADD CONSTRAINT "doctors_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");



ALTER TABLE ONLY "pharmacy"."purchase_orders"
    ADD CONSTRAINT "fk_pharmacy_po_supplier" FOREIGN KEY ("supplier_id") REFERENCES "pharmacy"."suppliers"("id");



ALTER TABLE ONLY "pharmacy"."inventory_batches"
    ADD CONSTRAINT "inventory_batches_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");



ALTER TABLE ONLY "pharmacy"."inventory_batches"
    ADD CONSTRAINT "inventory_batches_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "pharmacy"."locations"("id");



ALTER TABLE ONLY "pharmacy"."inventory_batches"
    ADD CONSTRAINT "inventory_batches_po_id_fkey" FOREIGN KEY ("po_id") REFERENCES "pharmacy"."purchase_orders"("id");



ALTER TABLE ONLY "pharmacy"."inventory_batches"
    ADD CONSTRAINT "inventory_batches_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "pharmacy"."products"("id");



ALTER TABLE ONLY "pharmacy"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_batch_id_fkey" FOREIGN KEY ("batch_id") REFERENCES "pharmacy"."inventory_batches"("id");



ALTER TABLE ONLY "pharmacy"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");



ALTER TABLE ONLY "pharmacy"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "pharmacy"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_destination_location_id_fkey" FOREIGN KEY ("destination_location_id") REFERENCES "pharmacy"."locations"("id");



ALTER TABLE ONLY "pharmacy"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_from_location_id_fkey" FOREIGN KEY ("from_location_id") REFERENCES "pharmacy"."locations"("id");



ALTER TABLE ONLY "pharmacy"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "pharmacy"."products"("id");



ALTER TABLE ONLY "pharmacy"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_receipt_id_fkey" FOREIGN KEY ("receipt_id") REFERENCES "pharmacy"."inventory_receipts"("id");



ALTER TABLE ONLY "pharmacy"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_source_location_id_fkey" FOREIGN KEY ("source_location_id") REFERENCES "pharmacy"."locations"("id");



ALTER TABLE ONLY "pharmacy"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_to_location_id_fkey" FOREIGN KEY ("to_location_id") REFERENCES "pharmacy"."locations"("id");



ALTER TABLE ONLY "pharmacy"."inventory_receipts"
    ADD CONSTRAINT "inventory_receipts_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");



ALTER TABLE ONLY "pharmacy"."inventory_receipts"
    ADD CONSTRAINT "inventory_receipts_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "pharmacy"."inventory_receipts"
    ADD CONSTRAINT "inventory_receipts_po_id_fkey" FOREIGN KEY ("po_id") REFERENCES "pharmacy"."purchase_orders"("id");



ALTER TABLE ONLY "pharmacy"."inventory_receipts"
    ADD CONSTRAINT "inventory_receipts_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "pharmacy"."suppliers"("id");



ALTER TABLE ONLY "pharmacy"."locations"
    ADD CONSTRAINT "locations_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");



ALTER TABLE ONLY "pharmacy"."locations"
    ADD CONSTRAINT "locations_parent_location_id_fkey" FOREIGN KEY ("parent_location_id") REFERENCES "pharmacy"."locations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "pharmacy"."locations"
    ADD CONSTRAINT "locations_warehouse_id_fkey" FOREIGN KEY ("warehouse_id") REFERENCES "pharmacy"."warehouses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "pharmacy"."patients"
    ADD CONSTRAINT "patients_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");



ALTER TABLE ONLY "pharmacy"."pos_operators"
    ADD CONSTRAINT "pos_operators_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");



ALTER TABLE ONLY "pharmacy"."pos_operators"
    ADD CONSTRAINT "pos_operators_warehouse_id_fkey" FOREIGN KEY ("warehouse_id") REFERENCES "pharmacy"."warehouses"("id");



ALTER TABLE ONLY "pharmacy"."pos_sessions"
    ADD CONSTRAINT "pos_sessions_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");



ALTER TABLE ONLY "pharmacy"."pos_sessions"
    ADD CONSTRAINT "pos_sessions_operator_id_fkey" FOREIGN KEY ("operator_id") REFERENCES "pharmacy"."pos_operators"("id");



ALTER TABLE ONLY "pharmacy"."pos_sessions"
    ADD CONSTRAINT "pos_sessions_terminal_id_fkey" FOREIGN KEY ("terminal_id") REFERENCES "pharmacy"."pos_terminals"("id");



ALTER TABLE ONLY "pharmacy"."pos_sessions"
    ADD CONSTRAINT "pos_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "pharmacy"."pos_sessions"
    ADD CONSTRAINT "pos_sessions_warehouse_id_fkey" FOREIGN KEY ("warehouse_id") REFERENCES "pharmacy"."warehouses"("id");



ALTER TABLE ONLY "pharmacy"."pos_terminals"
    ADD CONSTRAINT "pos_terminals_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");



ALTER TABLE ONLY "pharmacy"."pos_terminals"
    ADD CONSTRAINT "pos_terminals_warehouse_id_fkey" FOREIGN KEY ("warehouse_id") REFERENCES "pharmacy"."warehouses"("id");



ALTER TABLE ONLY "pharmacy"."prescription_items"
    ADD CONSTRAINT "prescription_items_prescription_id_fkey" FOREIGN KEY ("prescription_id") REFERENCES "pharmacy"."prescriptions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "pharmacy"."prescription_items"
    ADD CONSTRAINT "prescription_items_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "pharmacy"."products"("id");



ALTER TABLE ONLY "pharmacy"."prescriptions"
    ADD CONSTRAINT "prescriptions_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");



ALTER TABLE ONLY "pharmacy"."prescriptions"
    ADD CONSTRAINT "prescriptions_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "pharmacy"."prescriptions"
    ADD CONSTRAINT "prescriptions_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "pharmacy"."patients"("id");



ALTER TABLE ONLY "pharmacy"."product_prices"
    ADD CONSTRAINT "product_prices_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "pharmacy"."products"("id");



ALTER TABLE ONLY "pharmacy"."product_prices"
    ADD CONSTRAINT "product_prices_warehouse_id_fkey" FOREIGN KEY ("warehouse_id") REFERENCES "pharmacy"."warehouses"("id");



ALTER TABLE ONLY "pharmacy"."products"
    ADD CONSTRAINT "products_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");



ALTER TABLE ONLY "pharmacy"."products"
    ADD CONSTRAINT "products_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "pharmacy"."products"
    ADD CONSTRAINT "products_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "pharmacy"."purchase_order_items"
    ADD CONSTRAINT "purchase_order_items_po_id_fkey" FOREIGN KEY ("po_id") REFERENCES "pharmacy"."purchase_orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "pharmacy"."purchase_order_items"
    ADD CONSTRAINT "purchase_order_items_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "pharmacy"."products"("id");



ALTER TABLE ONLY "pharmacy"."purchase_order_items"
    ADD CONSTRAINT "purchase_order_items_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "pharmacy"."purchase_orders"
    ADD CONSTRAINT "purchase_orders_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");



ALTER TABLE ONLY "pharmacy"."purchase_orders"
    ADD CONSTRAINT "purchase_orders_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "pharmacy"."purchase_orders"
    ADD CONSTRAINT "purchase_orders_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "pharmacy"."purchase_orders"
    ADD CONSTRAINT "purchase_orders_warehouse_id_fkey" FOREIGN KEY ("warehouse_id") REFERENCES "pharmacy"."warehouses"("id");



ALTER TABLE ONLY "pharmacy"."sale_items"
    ADD CONSTRAINT "sale_items_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");



ALTER TABLE ONLY "pharmacy"."sale_items"
    ADD CONSTRAINT "sale_items_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "pharmacy"."products"("id");



ALTER TABLE ONLY "pharmacy"."sale_items"
    ADD CONSTRAINT "sale_items_sale_id_fkey" FOREIGN KEY ("sale_id") REFERENCES "pharmacy"."sales"("id");



ALTER TABLE ONLY "pharmacy"."sales"
    ADD CONSTRAINT "sales_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");



ALTER TABLE ONLY "pharmacy"."sales"
    ADD CONSTRAINT "sales_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "pharmacy"."patients"("id");



ALTER TABLE ONLY "pharmacy"."sales"
    ADD CONSTRAINT "sales_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "pharmacy"."pos_sessions"("id");



ALTER TABLE ONLY "pharmacy"."sales"
    ADD CONSTRAINT "sales_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "pharmacy"."suppliers"
    ADD CONSTRAINT "suppliers_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");



ALTER TABLE ONLY "pharmacy"."suppliers"
    ADD CONSTRAINT "suppliers_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "pharmacy"."suppliers"
    ADD CONSTRAINT "suppliers_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "pharmacy"."transfer_request_items"
    ADD CONSTRAINT "transfer_request_items_batch_id_fkey" FOREIGN KEY ("batch_id") REFERENCES "pharmacy"."inventory_batches"("id");



ALTER TABLE ONLY "pharmacy"."transfer_request_items"
    ADD CONSTRAINT "transfer_request_items_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");



ALTER TABLE ONLY "pharmacy"."transfer_request_items"
    ADD CONSTRAINT "transfer_request_items_destination_location_id_fkey" FOREIGN KEY ("destination_location_id") REFERENCES "pharmacy"."locations"("id");



ALTER TABLE ONLY "pharmacy"."transfer_request_items"
    ADD CONSTRAINT "transfer_request_items_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "pharmacy"."products"("id");



ALTER TABLE ONLY "pharmacy"."transfer_request_items"
    ADD CONSTRAINT "transfer_request_items_source_location_id_fkey" FOREIGN KEY ("source_location_id") REFERENCES "pharmacy"."locations"("id");



ALTER TABLE ONLY "pharmacy"."transfer_request_items"
    ADD CONSTRAINT "transfer_request_items_transfer_request_id_fkey" FOREIGN KEY ("transfer_request_id") REFERENCES "pharmacy"."transfer_requests"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "pharmacy"."transfer_requests"
    ADD CONSTRAINT "transfer_requests_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");



ALTER TABLE ONLY "pharmacy"."transfer_requests"
    ADD CONSTRAINT "transfer_requests_destination_warehouse_id_fkey" FOREIGN KEY ("destination_warehouse_id") REFERENCES "pharmacy"."warehouses"("id");



ALTER TABLE ONLY "pharmacy"."transfer_requests"
    ADD CONSTRAINT "transfer_requests_requested_by_fkey" FOREIGN KEY ("requested_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "pharmacy"."transfer_requests"
    ADD CONSTRAINT "transfer_requests_source_warehouse_id_fkey" FOREIGN KEY ("source_warehouse_id") REFERENCES "pharmacy"."warehouses"("id");



ALTER TABLE ONLY "pharmacy"."warehouses"
    ADD CONSTRAINT "warehouses_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");



ALTER TABLE ONLY "pharmacy"."warehouses"
    ADD CONSTRAINT "warehouses_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."cash_movements"
    ADD CONSTRAINT "cash_movements_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."cash_movements"
    ADD CONSTRAINT "cash_movements_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."pos_sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."cash_movements"
    ADD CONSTRAINT "cash_movements_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."company_users"
    ADD CONSTRAINT "company_users_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."company_users"
    ADD CONSTRAINT "company_users_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."customer_payments"
    ADD CONSTRAINT "customer_payments_cashier_id_fkey" FOREIGN KEY ("cashier_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."customer_payments"
    ADD CONSTRAINT "customer_payments_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."customer_payments"
    ADD CONSTRAINT "customer_payments_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."customer_payments"
    ADD CONSTRAINT "customer_payments_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."pos_sessions"("id");



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_po_id_fkey" FOREIGN KEY ("po_id") REFERENCES "public"."purchase_orders"("id");



ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_receipt_id_fkey" FOREIGN KEY ("receipt_id") REFERENCES "public"."inventory_receipts"("id");



ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."suppliers"("id");



ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_receipt_id_fkey" FOREIGN KEY ("receipt_id") REFERENCES "public"."inventory_receipts"("id");



ALTER TABLE ONLY "public"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."inventory_receipts"
    ADD CONSTRAINT "inventory_receipts_po_id_fkey" FOREIGN KEY ("po_id") REFERENCES "public"."purchase_orders"("id");



ALTER TABLE ONLY "public"."inventory_receipts"
    ADD CONSTRAINT "inventory_receipts_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."suppliers"("id");



ALTER TABLE ONLY "public"."landed_cost_allocations"
    ADD CONSTRAINT "landed_cost_allocations_expense_id_fkey" FOREIGN KEY ("expense_id") REFERENCES "public"."expenses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."landed_cost_allocations"
    ADD CONSTRAINT "landed_cost_allocations_receipt_id_fkey" FOREIGN KEY ("receipt_id") REFERENCES "public"."inventory_receipts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."pos_sessions"
    ADD CONSTRAINT "pos_sessions_cashier_id_fkey" FOREIGN KEY ("cashier_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."pos_sessions"
    ADD CONSTRAINT "pos_sessions_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."product_batches"
    ADD CONSTRAINT "product_batches_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."product_batches"
    ADD CONSTRAINT "product_batches_po_id_fkey" FOREIGN KEY ("po_id") REFERENCES "public"."purchase_orders"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."product_batches"
    ADD CONSTRAINT "product_batches_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."product_categories"
    ADD CONSTRAINT "product_categories_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."product_categories"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."suppliers"("id");



ALTER TABLE ONLY "public"."promotions"
    ADD CONSTRAINT "promotions_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."promotions"
    ADD CONSTRAINT "promotions_reward_product_id_fkey" FOREIGN KEY ("reward_product_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."promotions"
    ADD CONSTRAINT "promotions_target_product_id_fkey" FOREIGN KEY ("target_product_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."promotions"
    ADD CONSTRAINT "promotions_trigger_product_id_fkey" FOREIGN KEY ("trigger_product_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."purchase_order_items"
    ADD CONSTRAINT "purchase_order_items_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");



ALTER TABLE ONLY "public"."purchase_order_items"
    ADD CONSTRAINT "purchase_order_items_po_id_fkey" FOREIGN KEY ("po_id") REFERENCES "public"."purchase_orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."purchase_order_items"
    ADD CONSTRAINT "purchase_order_items_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."purchase_order_lines"
    ADD CONSTRAINT "purchase_order_lines_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");



ALTER TABLE ONLY "public"."purchase_order_lines"
    ADD CONSTRAINT "purchase_order_lines_purchase_order_id_fkey" FOREIGN KEY ("purchase_order_id") REFERENCES "public"."purchase_orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."purchase_order_lines"
    ADD CONSTRAINT "purchase_order_lines_supplier_product_id_fkey" FOREIGN KEY ("supplier_product_id") REFERENCES "public"."supplier_products"("id");



ALTER TABLE ONLY "public"."purchase_orders"
    ADD CONSTRAINT "purchase_orders_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."purchase_orders"
    ADD CONSTRAINT "purchase_orders_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."purchase_orders"
    ADD CONSTRAINT "purchase_orders_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."purchase_orders"
    ADD CONSTRAINT "purchase_orders_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."suppliers"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."sale_items"
    ADD CONSTRAINT "sale_items_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");



ALTER TABLE ONLY "public"."sale_items"
    ADD CONSTRAINT "sale_items_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id");



ALTER TABLE ONLY "public"."sale_items"
    ADD CONSTRAINT "sale_items_sale_id_fkey" FOREIGN KEY ("sale_id") REFERENCES "public"."sales"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sales"
    ADD CONSTRAINT "sales_cashier_id_fkey" FOREIGN KEY ("cashier_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."sales"
    ADD CONSTRAINT "sales_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");



ALTER TABLE ONLY "public"."sales"
    ADD CONSTRAINT "sales_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id");



ALTER TABLE ONLY "public"."sales"
    ADD CONSTRAINT "sales_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."pos_sessions"("id");



ALTER TABLE ONLY "public"."supplier_payments"
    ADD CONSTRAINT "supplier_payments_expense_id_fkey" FOREIGN KEY ("expense_id") REFERENCES "public"."expenses"("id");



ALTER TABLE ONLY "public"."supplier_products"
    ADD CONSTRAINT "supplier_products_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."supplier_products"
    ADD CONSTRAINT "supplier_products_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."supplier_products"
    ADD CONSTRAINT "supplier_products_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."suppliers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;



CREATE POLICY "Acceso estricto a detalle ventas" ON "pharmacy"."sale_items" TO "authenticated" USING (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE ("company_users"."user_id" = "auth"."uid"())))) WITH CHECK (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE ("company_users"."user_id" = "auth"."uid"()))));



CREATE POLICY "Aislamiento estricto por Empresa" ON "pharmacy"."product_prices" TO "authenticated" USING (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE ("company_users"."user_id" = "auth"."uid"())))) WITH CHECK (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE ("company_users"."user_id" = "auth"."uid"()))));



CREATE POLICY "Doctores INSERT" ON "pharmacy"."doctors" FOR INSERT TO "authenticated" WITH CHECK (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE ("company_users"."user_id" = "auth"."uid"()))));



CREATE POLICY "Doctores SELECT" ON "pharmacy"."doctors" FOR SELECT TO "authenticated" USING (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE ("company_users"."user_id" = "auth"."uid"()))));



CREATE POLICY "Los usuarios ven doctores de su propia empresa" ON "pharmacy"."doctors" TO "authenticated" USING (("company_id" = ((("auth"."jwt"() -> 'user_metadata'::"text") ->> 'company_id'::"text"))::"uuid"));



CREATE POLICY "Only Admin can delete products" ON "pharmacy"."products" FOR DELETE TO "authenticated" USING ((("company_id" = "pharmacy"."get_my_company_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."company_users"
  WHERE (("company_users"."user_id" = "auth"."uid"()) AND ("company_users"."role" = ANY (ARRAY['OWNER'::"text", 'MANAGER'::"text"])))))));



CREATE POLICY "Permitir DELETE a usuarios autenticados" ON "pharmacy"."pos_terminals" FOR DELETE TO "authenticated" USING (true);



CREATE POLICY "Permitir INSERT a usuarios autenticados" ON "pharmacy"."pos_terminals" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Permitir SELECT a usuarios autenticados" ON "pharmacy"."pos_terminals" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Permitir UPDATE a usuarios autenticados" ON "pharmacy"."pos_terminals" FOR UPDATE TO "authenticated" USING (true);



CREATE POLICY "Permitir actualización a usuarios autenticados" ON "pharmacy"."transfer_requests" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Permitir actualización de items a usuarios autenticados" ON "pharmacy"."transfer_request_items" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Permitir inserción a usuarios autenticados" ON "pharmacy"."transfer_requests" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Permitir inserción de items a usuarios autenticados" ON "pharmacy"."transfer_request_items" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Permitir lectura a usuarios autenticados" ON "pharmacy"."transfer_requests" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Permitir lectura de items a usuarios autenticados" ON "pharmacy"."transfer_request_items" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Permitir todo a usuarios de la misma empresa - Batches" ON "pharmacy"."inventory_batches" TO "authenticated" USING (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE ("company_users"."user_id" = "auth"."uid"())))) WITH CHECK (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE ("company_users"."user_id" = "auth"."uid"()))));



CREATE POLICY "Permitir todo a usuarios de la misma empresa - Movements" ON "pharmacy"."inventory_movements" TO "authenticated" USING (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE ("company_users"."user_id" = "auth"."uid"())))) WITH CHECK (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE ("company_users"."user_id" = "auth"."uid"()))));



CREATE POLICY "Permitir todo a usuarios de la misma empresa - Receipts" ON "pharmacy"."inventory_receipts" TO "authenticated" USING (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE ("company_users"."user_id" = "auth"."uid"())))) WITH CHECK (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE ("company_users"."user_id" = "auth"."uid"()))));



CREATE POLICY "Tenant Isolation - PO" ON "pharmacy"."purchase_orders" TO "authenticated" USING (("company_id" = "pharmacy"."get_my_company_id"()));



CREATE POLICY "Tenant Isolation - PO Items" ON "pharmacy"."purchase_order_items" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "pharmacy"."purchase_orders" "po"
  WHERE (("po"."id" = "purchase_order_items"."po_id") AND ("po"."company_id" = "pharmacy"."get_my_company_id"())))));



CREATE POLICY "Tenant Isolation - Patients" ON "pharmacy"."patients" TO "authenticated" USING (("company_id" = "pharmacy"."get_my_company_id"()));



CREATE POLICY "Tenant Isolation - Pharmacy Suppliers" ON "pharmacy"."suppliers" TO "authenticated" USING (("company_id" = "pharmacy"."get_my_company_id"()));



CREATE POLICY "Tenant Isolation - Prescription Items" ON "pharmacy"."prescription_items" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "pharmacy"."prescriptions" "p"
  WHERE (("p"."id" = "prescription_items"."prescription_id") AND ("p"."company_id" = "pharmacy"."get_my_company_id"())))));



CREATE POLICY "Tenant Isolation - Prescriptions" ON "pharmacy"."prescriptions" TO "authenticated" USING (("company_id" = "pharmacy"."get_my_company_id"()));



CREATE POLICY "Tenant Isolation - Products" ON "pharmacy"."products" TO "authenticated" USING (("company_id" = "pharmacy"."get_my_company_id"()));



CREATE POLICY "Tenant Isolation - Sales" ON "pharmacy"."sales" TO "authenticated" USING (("company_id" = "pharmacy"."get_my_company_id"()));



CREATE POLICY "Tenant Isolation Insert - Prescription Items" ON "pharmacy"."prescription_items" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "pharmacy"."prescriptions" "p"
  WHERE (("p"."id" = "prescription_items"."prescription_id") AND ("p"."company_id" = "pharmacy"."get_my_company_id"())))));



CREATE POLICY "Tenant Isolation Insert - Prescriptions" ON "pharmacy"."prescriptions" FOR INSERT TO "authenticated" WITH CHECK (("company_id" = "pharmacy"."get_my_company_id"()));



CREATE POLICY "Tenant Isolation Update - Prescriptions" ON "pharmacy"."prescriptions" FOR UPDATE TO "authenticated" USING (("company_id" = "pharmacy"."get_my_company_id"()));



ALTER TABLE "pharmacy"."audit_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "pharmacy"."cash_movements" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "cash_movements_insert_same_company" ON "pharmacy"."cash_movements" FOR INSERT TO "authenticated" WITH CHECK (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE ("company_users"."user_id" = "auth"."uid"()))));



CREATE POLICY "cash_movements_select_same_company" ON "pharmacy"."cash_movements" FOR SELECT TO "authenticated" USING (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE ("company_users"."user_id" = "auth"."uid"()))));



ALTER TABLE "pharmacy"."doctors" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "pharmacy"."inventory_batches" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "pharmacy"."inventory_movements" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "pharmacy"."inventory_receipts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "pharmacy"."patients" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "pharmacy"."pos_operators" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pos_operators_insert_same_company" ON "pharmacy"."pos_operators" FOR INSERT TO "authenticated" WITH CHECK (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE ("company_users"."user_id" = "auth"."uid"()))));



CREATE POLICY "pos_operators_select_same_company" ON "pharmacy"."pos_operators" FOR SELECT TO "authenticated" USING (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE ("company_users"."user_id" = "auth"."uid"()))));



CREATE POLICY "pos_operators_update_same_company" ON "pharmacy"."pos_operators" FOR UPDATE TO "authenticated" USING (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE ("company_users"."user_id" = "auth"."uid"())))) WITH CHECK (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE ("company_users"."user_id" = "auth"."uid"()))));



ALTER TABLE "pharmacy"."pos_sessions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pos_sessions_insert_same_company" ON "pharmacy"."pos_sessions" FOR INSERT TO "authenticated" WITH CHECK (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE ("company_users"."user_id" = "auth"."uid"()))));



CREATE POLICY "pos_sessions_select_same_company" ON "pharmacy"."pos_sessions" FOR SELECT TO "authenticated" USING (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE ("company_users"."user_id" = "auth"."uid"()))));



CREATE POLICY "pos_sessions_update_same_company" ON "pharmacy"."pos_sessions" FOR UPDATE TO "authenticated" USING (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE ("company_users"."user_id" = "auth"."uid"())))) WITH CHECK (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE ("company_users"."user_id" = "auth"."uid"()))));



ALTER TABLE "pharmacy"."pos_terminals" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "pharmacy"."prescription_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "pharmacy"."prescription_validity_rules" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "pharmacy"."prescriptions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "pharmacy"."product_prices" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "pharmacy"."products" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "pharmacy"."purchase_order_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "pharmacy"."purchase_orders" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "pharmacy"."sale_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "pharmacy"."sales" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "pharmacy"."suppliers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "pharmacy"."transfer_request_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "pharmacy"."transfer_requests" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "Admins manage batches" ON "public"."product_batches" USING (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE (("company_users"."user_id" = "auth"."uid"()) AND ("company_users"."role" = ANY (ARRAY['OWNER'::"text", 'MANAGER'::"text"]))))));



CREATE POLICY "Aislamiento de Catalogo" ON "public"."supplier_products" USING (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE ("company_users"."user_id" = "auth"."uid"()))));



CREATE POLICY "Aislamiento de Compras" ON "public"."purchase_orders" USING (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE ("company_users"."user_id" = "auth"."uid"()))));



CREATE POLICY "Aislamiento de Proveedores" ON "public"."suppliers" USING (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE ("company_users"."user_id" = "auth"."uid"()))));



CREATE POLICY "Control PO items mi empresa" ON "public"."purchase_order_items" USING (("po_id" IN ( SELECT "purchase_orders"."id"
   FROM "public"."purchase_orders"
  WHERE ("purchase_orders"."company_id" IN ( SELECT "public"."get_my_companies"() AS "get_my_companies")))));



CREATE POLICY "Control POs mi empresa" ON "public"."purchase_orders" USING (("company_id" IN ( SELECT "public"."get_my_companies"() AS "get_my_companies")));



CREATE POLICY "Control clientes mi empresa" ON "public"."customers" USING (("company_id" IN ( SELECT "public"."get_my_companies"() AS "get_my_companies")));



CREATE POLICY "Control gastos mi empresa" ON "public"."expenses" USING (("company_id" IN ( SELECT "public"."get_my_companies"() AS "get_my_companies")));



CREATE POLICY "Control kardex mi empresa" ON "public"."inventory_movements" USING (("company_id" IN ( SELECT "public"."get_my_companies"() AS "get_my_companies")));



CREATE POLICY "Control lotes mi empresa" ON "public"."product_batches" USING (("company_id" IN ( SELECT "public"."get_my_companies"() AS "get_my_companies")));



CREATE POLICY "Control movimientos mi empresa" ON "public"."cash_movements" USING (("company_id" IN ( SELECT "public"."get_my_companies"() AS "get_my_companies")));



CREATE POLICY "Control pagos mi empresa" ON "public"."customer_payments" USING (("company_id" IN ( SELECT "public"."get_my_companies"() AS "get_my_companies")));



CREATE POLICY "Control proveedores mi empresa" ON "public"."suppliers" USING (("company_id" IN ( SELECT "public"."get_my_companies"() AS "get_my_companies")));



CREATE POLICY "Control sesiones mi empresa" ON "public"."pos_sessions" USING (("company_id" IN ( SELECT "public"."get_my_companies"() AS "get_my_companies")));



CREATE POLICY "Control total de mis productos" ON "public"."products" USING (("company_id" IN ( SELECT "public"."get_my_companies"() AS "get_my_companies")));



CREATE POLICY "Owners and managers can manage expenses" ON "public"."expenses" USING (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE (("company_users"."user_id" = "auth"."uid"()) AND ("company_users"."role" = ANY (ARRAY['OWNER'::"text", 'MANAGER'::"text"]))))));



CREATE POLICY "Permitir actualización a dueños" ON "public"."companies" FOR UPDATE TO "authenticated" USING (("id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE (("company_users"."user_id" = "auth"."uid"()) AND ("company_users"."role" = 'OWNER'::"text"))))) WITH CHECK (("id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE (("company_users"."user_id" = "auth"."uid"()) AND ("company_users"."role" = 'OWNER'::"text")))));



CREATE POLICY "Permitir crear empresa" ON "public"."companies" FOR INSERT WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Permitir todo en sale_items" ON "public"."sale_items" USING (true);



CREATE POLICY "Permitir todo en sales" ON "public"."sales" USING (true);



CREATE POLICY "Permitir unirse a empresa" ON "public"."company_users" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can manage their own companies promotions" ON "public"."promotions" USING (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE ("company_users"."user_id" = "auth"."uid"()))));



CREATE POLICY "Users can view their company expenses" ON "public"."expenses" FOR SELECT USING (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE ("company_users"."user_id" = "auth"."uid"()))));



CREATE POLICY "Users view their batches" ON "public"."product_batches" FOR SELECT USING (("company_id" IN ( SELECT "company_users"."company_id"
   FROM "public"."company_users"
  WHERE ("company_users"."user_id" = "auth"."uid"()))));



CREATE POLICY "Ver equipo de mi empresa" ON "public"."company_users" FOR SELECT USING (("company_id" IN ( SELECT "public"."get_my_companies"() AS "get_my_companies")));



CREATE POLICY "Ver propia empresa" ON "public"."companies" FOR SELECT USING ((("id" IN ( SELECT "public"."get_my_companies"() AS "get_my_companies")) OR ("created_by" = "auth"."uid"())));



ALTER TABLE "public"."cash_movements" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."companies" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."company_users" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."customer_payments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."customers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."expenses" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."inventory_movements" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."inventory_receipts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."landed_cost_allocations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pos_sessions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."product_batches" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."product_categories" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."products" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."promotions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."purchase_order_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."purchase_order_lines" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."purchase_orders" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "saas_companies_isolation" ON "public"."companies" USING (("id" = "public"."get_my_company_id"()));



CREATE POLICY "saas_company_users_isolation" ON "public"."company_users" USING (("company_id" = "public"."get_my_company_id"()));



CREATE POLICY "saas_tenant_isolation" ON "public"."cash_movements" USING (("company_id" = "public"."get_my_company_id"())) WITH CHECK (("company_id" = "public"."get_my_company_id"()));



CREATE POLICY "saas_tenant_isolation" ON "public"."customer_payments" USING (("company_id" = "public"."get_my_company_id"())) WITH CHECK (("company_id" = "public"."get_my_company_id"()));



CREATE POLICY "saas_tenant_isolation" ON "public"."customers" USING (("company_id" = "public"."get_my_company_id"())) WITH CHECK (("company_id" = "public"."get_my_company_id"()));



CREATE POLICY "saas_tenant_isolation" ON "public"."expenses" USING (("company_id" = "public"."get_my_company_id"())) WITH CHECK (("company_id" = "public"."get_my_company_id"()));



CREATE POLICY "saas_tenant_isolation" ON "public"."inventory_movements" USING (("company_id" = "public"."get_my_company_id"())) WITH CHECK (("company_id" = "public"."get_my_company_id"()));



CREATE POLICY "saas_tenant_isolation" ON "public"."inventory_receipts" USING (("company_id" = "public"."get_my_company_id"())) WITH CHECK (("company_id" = "public"."get_my_company_id"()));



CREATE POLICY "saas_tenant_isolation" ON "public"."landed_cost_allocations" USING (("company_id" = "public"."get_my_company_id"())) WITH CHECK (("company_id" = "public"."get_my_company_id"()));



CREATE POLICY "saas_tenant_isolation" ON "public"."pos_sessions" USING (("company_id" = "public"."get_my_company_id"())) WITH CHECK (("company_id" = "public"."get_my_company_id"()));



CREATE POLICY "saas_tenant_isolation" ON "public"."product_batches" USING (("company_id" = "public"."get_my_company_id"())) WITH CHECK (("company_id" = "public"."get_my_company_id"()));



CREATE POLICY "saas_tenant_isolation" ON "public"."product_categories" USING (("company_id" = "public"."get_my_company_id"())) WITH CHECK (("company_id" = "public"."get_my_company_id"()));



CREATE POLICY "saas_tenant_isolation" ON "public"."products" USING (("company_id" = "public"."get_my_company_id"())) WITH CHECK (("company_id" = "public"."get_my_company_id"()));



CREATE POLICY "saas_tenant_isolation" ON "public"."promotions" USING (("company_id" = "public"."get_my_company_id"())) WITH CHECK (("company_id" = "public"."get_my_company_id"()));



CREATE POLICY "saas_tenant_isolation" ON "public"."purchase_order_items" USING (("company_id" = "public"."get_my_company_id"())) WITH CHECK (("company_id" = "public"."get_my_company_id"()));



CREATE POLICY "saas_tenant_isolation" ON "public"."purchase_order_lines" USING (("company_id" = "public"."get_my_company_id"())) WITH CHECK (("company_id" = "public"."get_my_company_id"()));



CREATE POLICY "saas_tenant_isolation" ON "public"."purchase_orders" USING (("company_id" = "public"."get_my_company_id"())) WITH CHECK (("company_id" = "public"."get_my_company_id"()));



CREATE POLICY "saas_tenant_isolation" ON "public"."sale_items" USING (("company_id" = "public"."get_my_company_id"())) WITH CHECK (("company_id" = "public"."get_my_company_id"()));



CREATE POLICY "saas_tenant_isolation" ON "public"."sales" USING (("company_id" = "public"."get_my_company_id"())) WITH CHECK (("company_id" = "public"."get_my_company_id"()));



CREATE POLICY "saas_tenant_isolation" ON "public"."supplier_payments" USING (("company_id" = "public"."get_my_company_id"())) WITH CHECK (("company_id" = "public"."get_my_company_id"()));



CREATE POLICY "saas_tenant_isolation" ON "public"."supplier_products" USING (("company_id" = "public"."get_my_company_id"())) WITH CHECK (("company_id" = "public"."get_my_company_id"()));



CREATE POLICY "saas_tenant_isolation" ON "public"."suppliers" USING (("company_id" = "public"."get_my_company_id"())) WITH CHECK (("company_id" = "public"."get_my_company_id"()));



ALTER TABLE "public"."sale_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sales" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."supplier_payments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."supplier_products" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."suppliers" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






GRANT USAGE ON SCHEMA "pharmacy" TO "authenticated";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";






















































































































































GRANT ALL ON FUNCTION "pharmacy"."calculate_prescription_valid_until"("p_prescription_type" "text", "p_issued_at" timestamp with time zone) TO "authenticated";



GRANT ALL ON FUNCTION "pharmacy"."create_pos_operator"("p_full_name" "text", "p_pin" "text", "p_warehouse_id" "uuid") TO "authenticated";



GRANT ALL ON TABLE "pharmacy"."pos_operators" TO "authenticated";



GRANT ALL ON FUNCTION "pharmacy"."create_pos_operator"("p_company_id" "uuid", "p_warehouse_id" "uuid", "p_full_name" "text", "p_pin_code" "text") TO "authenticated";



GRANT ALL ON FUNCTION "pharmacy"."create_prescription_with_items"("p_patient_id" "uuid", "p_folio_electronico" "text", "p_prescriber_rut" "text", "p_prescriber_name" "text", "p_institution_name" "text", "p_items" "jsonb") TO "authenticated";



GRANT ALL ON FUNCTION "pharmacy"."create_prescription_with_items"("p_company_id" "uuid", "p_diagnosis" "text", "p_doctor_id" "uuid", "p_folio_electronico" "text", "p_issue_date" "date", "p_items" "jsonb", "p_notes" "text", "p_patient_id" "uuid", "p_prescriber_name" "text", "p_prescriber_rut" "text", "p_valid_until" "date") TO "authenticated";



GRANT ALL ON FUNCTION "pharmacy"."derive_prescription_type_from_items"("p_items" "jsonb") TO "authenticated";



GRANT ALL ON FUNCTION "pharmacy"."expire_overdue_prescriptions"() TO "authenticated";



GRANT ALL ON FUNCTION "pharmacy"."fetch_audit_logs"("p_start_at" timestamp with time zone, "p_end_at" timestamp with time zone, "p_event_type" "text", "p_user_id" "uuid", "p_limit" integer, "p_offset" integer) TO "authenticated";



GRANT ALL ON FUNCTION "pharmacy"."get_my_company_id"() TO "authenticated";



GRANT ALL ON FUNCTION "pharmacy"."get_pos_products"("p_warehouse_id" "uuid", "p_search" "text", "p_limit" integer) TO "authenticated";



GRANT ALL ON FUNCTION "pharmacy"."increment_dispensed_quantity"("p_prescription_id" "uuid", "p_product_id" "uuid", "p_quantity" numeric) TO "authenticated";



GRANT ALL ON FUNCTION "pharmacy"."log_audit_event"("p_event_type" "text", "p_description" "text", "p_metadata" "jsonb") TO "authenticated";



GRANT ALL ON FUNCTION "pharmacy"."mark_prescription_dispensed"("p_prescription_id" "uuid") TO "authenticated";



GRANT ALL ON FUNCTION "pharmacy"."process_pharmacy_sale"("p_warehouse_id" "uuid", "p_total_amount" numeric, "p_payment_method" "text", "p_document_number" "text", "p_patient_id" "uuid", "p_prescription_id" "uuid", "p_items" "jsonb") TO "authenticated";



GRANT ALL ON FUNCTION "pharmacy"."recalculate_prescription_type"("p_prescription_id" "uuid") TO "authenticated";



GRANT ALL ON FUNCTION "pharmacy"."reset_pos_operator_pin"("p_operator_id" "uuid", "p_new_pin" "text") TO "authenticated";



GRANT ALL ON FUNCTION "pharmacy"."reset_pos_operator_pin"("p_operator_id" "uuid", "p_company_id" "uuid", "p_warehouse_id" "uuid", "p_pin_code" "text") TO "authenticated";



GRANT ALL ON FUNCTION "pharmacy"."set_po_number"() TO "authenticated";



GRANT ALL ON FUNCTION "pharmacy"."update_prescription_status"("p_prescription_id" "uuid") TO "authenticated";



GRANT ALL ON FUNCTION "pharmacy"."validate_prescription_pending"("p_prescription_id" "uuid") TO "authenticated";



GRANT ALL ON FUNCTION "pharmacy"."verify_pos_operator_pin"("p_operator_id" "uuid", "p_pin" "text") TO "authenticated";



GRANT ALL ON FUNCTION "pharmacy"."verify_pos_operator_pin"("p_operator_id" "uuid", "p_company_id" "uuid", "p_warehouse_id" "uuid", "p_pin_code" "text") TO "authenticated";



GRANT ALL ON FUNCTION "public"."confirm_password_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."confirm_password_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."confirm_password_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."create_worker"("worker_email" "text", "worker_password" "text", "worker_full_name" "text", "worker_role" "text", "target_company_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."create_worker"("worker_email" "text", "worker_password" "text", "worker_full_name" "text", "worker_role" "text", "target_company_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_worker"("worker_email" "text", "worker_password" "text", "worker_full_name" "text", "worker_role" "text", "target_company_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."decrement_stock"("p_id" "uuid", "p_qty" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."decrement_stock"("p_id" "uuid", "p_qty" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."decrement_stock"("p_id" "uuid", "p_qty" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_my_companies"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_my_companies"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_companies"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_my_company_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_my_company_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_company_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user_provisioning"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user_provisioning"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user_provisioning"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_purchase_order_number"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_purchase_order_number"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_purchase_order_number"() TO "service_role";



GRANT ALL ON PROCEDURE "public"."setup_saas_policies"(IN "target_table" "text") TO "anon";
GRANT ALL ON PROCEDURE "public"."setup_saas_policies"(IN "target_table" "text") TO "authenticated";
GRANT ALL ON PROCEDURE "public"."setup_saas_policies"(IN "target_table" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_user_company_metadata"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_user_company_metadata"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_user_company_metadata"() TO "service_role";


















GRANT ALL ON TABLE "pharmacy"."audit_logs" TO "authenticated";



GRANT ALL ON TABLE "pharmacy"."cash_movements" TO "authenticated";



GRANT ALL ON TABLE "pharmacy"."doctors" TO "authenticated";



GRANT ALL ON TABLE "pharmacy"."inventory_batches" TO "authenticated";
GRANT ALL ON TABLE "pharmacy"."inventory_batches" TO "service_role";



GRANT ALL ON TABLE "pharmacy"."inventory_movements" TO "authenticated";



GRANT ALL ON TABLE "pharmacy"."inventory_receipts" TO "authenticated";



GRANT ALL ON TABLE "pharmacy"."locations" TO "authenticated";



GRANT ALL ON TABLE "pharmacy"."patients" TO "authenticated";



GRANT ALL ON TABLE "pharmacy"."pos_sessions" TO "authenticated";



GRANT ALL ON TABLE "pharmacy"."pos_terminals" TO "authenticated";



GRANT ALL ON TABLE "pharmacy"."prescription_items" TO "authenticated";



GRANT ALL ON TABLE "pharmacy"."prescription_validity_rules" TO "authenticated";



GRANT ALL ON TABLE "pharmacy"."prescriptions" TO "authenticated";



GRANT ALL ON TABLE "pharmacy"."product_prices" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "pharmacy"."product_prices" TO "service_role";



GRANT ALL ON TABLE "pharmacy"."products" TO "authenticated";



GRANT ALL ON TABLE "pharmacy"."purchase_order_items" TO "authenticated";



GRANT ALL ON TABLE "pharmacy"."purchase_orders" TO "authenticated";



GRANT ALL ON TABLE "pharmacy"."sale_items" TO "authenticated";



GRANT ALL ON TABLE "pharmacy"."sales" TO "authenticated";



GRANT ALL ON TABLE "pharmacy"."suppliers" TO "authenticated";



GRANT SELECT,USAGE ON SEQUENCE "pharmacy"."transfer_folio_seq" TO "authenticated";
GRANT SELECT,USAGE ON SEQUENCE "pharmacy"."transfer_folio_seq" TO "service_role";



GRANT ALL ON TABLE "pharmacy"."transfer_request_items" TO "authenticated";



GRANT ALL ON TABLE "pharmacy"."transfer_requests" TO "authenticated";



GRANT ALL ON TABLE "pharmacy"."warehouses" TO "authenticated";



GRANT ALL ON TABLE "pharmacy"."v_kardex_professional" TO "authenticated";



GRANT ALL ON TABLE "public"."cash_movements" TO "anon";
GRANT ALL ON TABLE "public"."cash_movements" TO "authenticated";
GRANT ALL ON TABLE "public"."cash_movements" TO "service_role";



GRANT ALL ON TABLE "public"."companies" TO "anon";
GRANT ALL ON TABLE "public"."companies" TO "authenticated";
GRANT ALL ON TABLE "public"."companies" TO "service_role";



GRANT ALL ON TABLE "public"."company_users" TO "anon";
GRANT ALL ON TABLE "public"."company_users" TO "authenticated";
GRANT ALL ON TABLE "public"."company_users" TO "service_role";



GRANT ALL ON TABLE "public"."customer_payments" TO "anon";
GRANT ALL ON TABLE "public"."customer_payments" TO "authenticated";
GRANT ALL ON TABLE "public"."customer_payments" TO "service_role";



GRANT ALL ON TABLE "public"."customers" TO "anon";
GRANT ALL ON TABLE "public"."customers" TO "authenticated";
GRANT ALL ON TABLE "public"."customers" TO "service_role";



GRANT ALL ON TABLE "public"."expenses" TO "anon";
GRANT ALL ON TABLE "public"."expenses" TO "authenticated";
GRANT ALL ON TABLE "public"."expenses" TO "service_role";



GRANT ALL ON TABLE "public"."inventory_movements" TO "anon";
GRANT ALL ON TABLE "public"."inventory_movements" TO "authenticated";
GRANT ALL ON TABLE "public"."inventory_movements" TO "service_role";



GRANT ALL ON TABLE "public"."inventory_receipts" TO "anon";
GRANT ALL ON TABLE "public"."inventory_receipts" TO "authenticated";
GRANT ALL ON TABLE "public"."inventory_receipts" TO "service_role";



GRANT ALL ON SEQUENCE "public"."inventory_receipts_receipt_number_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."inventory_receipts_receipt_number_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."inventory_receipts_receipt_number_seq" TO "service_role";



GRANT ALL ON TABLE "public"."landed_cost_allocations" TO "anon";
GRANT ALL ON TABLE "public"."landed_cost_allocations" TO "authenticated";
GRANT ALL ON TABLE "public"."landed_cost_allocations" TO "service_role";



GRANT ALL ON TABLE "public"."pos_sessions" TO "anon";
GRANT ALL ON TABLE "public"."pos_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."pos_sessions" TO "service_role";



GRANT ALL ON TABLE "public"."product_batches" TO "anon";
GRANT ALL ON TABLE "public"."product_batches" TO "authenticated";
GRANT ALL ON TABLE "public"."product_batches" TO "service_role";



GRANT ALL ON TABLE "public"."product_categories" TO "anon";
GRANT ALL ON TABLE "public"."product_categories" TO "authenticated";
GRANT ALL ON TABLE "public"."product_categories" TO "service_role";



GRANT ALL ON TABLE "public"."products" TO "anon";
GRANT ALL ON TABLE "public"."products" TO "authenticated";
GRANT ALL ON TABLE "public"."products" TO "service_role";



GRANT ALL ON TABLE "public"."promotions" TO "anon";
GRANT ALL ON TABLE "public"."promotions" TO "authenticated";
GRANT ALL ON TABLE "public"."promotions" TO "service_role";



GRANT ALL ON TABLE "public"."purchase_order_items" TO "anon";
GRANT ALL ON TABLE "public"."purchase_order_items" TO "authenticated";
GRANT ALL ON TABLE "public"."purchase_order_items" TO "service_role";



GRANT ALL ON TABLE "public"."purchase_order_lines" TO "anon";
GRANT ALL ON TABLE "public"."purchase_order_lines" TO "authenticated";
GRANT ALL ON TABLE "public"."purchase_order_lines" TO "service_role";



GRANT ALL ON TABLE "public"."purchase_orders" TO "anon";
GRANT ALL ON TABLE "public"."purchase_orders" TO "authenticated";
GRANT ALL ON TABLE "public"."purchase_orders" TO "service_role";



GRANT ALL ON TABLE "public"."sale_items" TO "anon";
GRANT ALL ON TABLE "public"."sale_items" TO "authenticated";
GRANT ALL ON TABLE "public"."sale_items" TO "service_role";



GRANT ALL ON TABLE "public"."sales" TO "anon";
GRANT ALL ON TABLE "public"."sales" TO "authenticated";
GRANT ALL ON TABLE "public"."sales" TO "service_role";



GRANT ALL ON TABLE "public"."supplier_payments" TO "anon";
GRANT ALL ON TABLE "public"."supplier_payments" TO "authenticated";
GRANT ALL ON TABLE "public"."supplier_payments" TO "service_role";



GRANT ALL ON TABLE "public"."supplier_products" TO "anon";
GRANT ALL ON TABLE "public"."supplier_products" TO "authenticated";
GRANT ALL ON TABLE "public"."supplier_products" TO "service_role";



GRANT ALL ON TABLE "public"."suppliers" TO "anon";
GRANT ALL ON TABLE "public"."suppliers" TO "authenticated";
GRANT ALL ON TABLE "public"."suppliers" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "pharmacy" GRANT ALL ON TABLES TO "authenticated";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";































drop extension if exists "pg_net";

CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_provisioning();


  create policy "Logos_proveedor 1x2ykb0_0"
  on "storage"."objects"
  as permissive
  for select
  to public
using ((bucket_id = 'provider-logos'::text));



  create policy "Logos_proveedor 1x2ykb0_1"
  on "storage"."objects"
  as permissive
  for insert
  to public
with check ((bucket_id = 'provider-logos'::text));



  create policy "Logos_proveedor 1x2ykb0_2"
  on "storage"."objects"
  as permissive
  for update
  to public
using ((bucket_id = 'provider-logos'::text));



  create policy "Logos_proveedor 1x2ykb0_3"
  on "storage"."objects"
  as permissive
  for delete
  to public
using ((bucket_id = 'provider-logos'::text));



  create policy "Logos_proveedor 1y3lpeg_0"
  on "storage"."objects"
  as permissive
  for select
  to public
using ((bucket_id = 'company-logos'::text));



  create policy "Logos_proveedor 1y3lpeg_1"
  on "storage"."objects"
  as permissive
  for insert
  to public
with check ((bucket_id = 'company-logos'::text));



  create policy "Logos_proveedor 1y3lpeg_2"
  on "storage"."objects"
  as permissive
  for update
  to public
using ((bucket_id = 'company-logos'::text));



  create policy "Logos_proveedor 1y3lpeg_3"
  on "storage"."objects"
  as permissive
  for delete
  to public
using ((bucket_id = 'company-logos'::text));



  create policy "Método Seguro UI 1x2ykb0_0"
  on "storage"."objects"
  as permissive
  for insert
  to authenticated
with check (((storage.foldername(name))[1] = ((auth.jwt() -> 'app_metadata'::text) ->> 'company_id'::text)));



  create policy "Método Seguro UI 1x2ykb0_1"
  on "storage"."objects"
  as permissive
  for update
  to authenticated
using (((storage.foldername(name))[1] = ((auth.jwt() -> 'app_metadata'::text) ->> 'company_id'::text)));



  create policy "Método Seguro UI 1x2ykb0_3"
  on "storage"."objects"
  as permissive
  for delete
  to authenticated
using (((storage.foldername(name))[1] = ((auth.jwt() -> 'app_metadata'::text) ->> 'company_id'::text)));



  create policy "Método Seguro UI 1y3lpeg_0"
  on "storage"."objects"
  as permissive
  for insert
  to authenticated
with check (((storage.foldername(name))[1] = ((auth.jwt() -> 'app_metadata'::text) ->> 'company_id'::text)));



  create policy "Método Seguro UI 1y3lpeg_1"
  on "storage"."objects"
  as permissive
  for update
  to authenticated
using (((storage.foldername(name))[1] = ((auth.jwt() -> 'app_metadata'::text) ->> 'company_id'::text)));



  create policy "Método Seguro UI 1y3lpeg_2"
  on "storage"."objects"
  as permissive
  for select
  to authenticated
using (((storage.foldername(name))[1] = ((auth.jwt() -> 'app_metadata'::text) ->> 'company_id'::text)));



  create policy "Método Seguro UI 1y3lpeg_3"
  on "storage"."objects"
  as permissive
  for delete
  to authenticated
using (((storage.foldername(name))[1] = ((auth.jwt() -> 'app_metadata'::text) ->> 'company_id'::text)));



  create policy "Método Seguro UI 2 1x2ykb0_0"
  on "storage"."objects"
  as permissive
  for insert
  to authenticated
with check (((storage.foldername(name))[1] = ((auth.jwt() -> 'app_metadata'::text) ->> 'company_id'::text)));



  create policy "Método Seguro UI 2 1x2ykb0_1"
  on "storage"."objects"
  as permissive
  for update
  to authenticated
using (((storage.foldername(name))[1] = ((auth.jwt() -> 'app_metadata'::text) ->> 'company_id'::text)));



  create policy "Método Seguro UI 2 1x2ykb0_2"
  on "storage"."objects"
  as permissive
  for select
  to authenticated
using (((storage.foldername(name))[1] = ((auth.jwt() -> 'app_metadata'::text) ->> 'company_id'::text)));



  create policy "Método Seguro UI 2 1x2ykb0_3"
  on "storage"."objects"
  as permissive
  for delete
  to authenticated
using (((storage.foldername(name))[1] = ((auth.jwt() -> 'app_metadata'::text) ->> 'company_id'::text)));



  create policy "Método Seguro UI3 16wiy3a_0"
  on "storage"."objects"
  as permissive
  for select
  to authenticated
using (((storage.foldername(name))[1] = ((auth.jwt() -> 'app_metadata'::text) ->> 'company_id'::text)));



  create policy "Método Seguro UI3 16wiy3a_1"
  on "storage"."objects"
  as permissive
  for update
  to authenticated
using (((storage.foldername(name))[1] = ((auth.jwt() -> 'app_metadata'::text) ->> 'company_id'::text)));



  create policy "Método Seguro UI3 16wiy3a_2"
  on "storage"."objects"
  as permissive
  for insert
  to authenticated
with check (((storage.foldername(name))[1] = ((auth.jwt() -> 'app_metadata'::text) ->> 'company_id'::text)));



  create policy "Método Seguro UI3 16wiy3a_3"
  on "storage"."objects"
  as permissive
  for delete
  to authenticated
using (((storage.foldername(name))[1] = ((auth.jwt() -> 'app_metadata'::text) ->> 'company_id'::text)));



  create policy "Productos 16wiy3a_0"
  on "storage"."objects"
  as permissive
  for select
  to public
using ((bucket_id = 'product-images'::text));



  create policy "Productos 16wiy3a_1"
  on "storage"."objects"
  as permissive
  for insert
  to public
with check ((bucket_id = 'product-images'::text));



  create policy "Productos 16wiy3a_2"
  on "storage"."objects"
  as permissive
  for update
  to public
using ((bucket_id = 'product-images'::text));



  create policy "Productos 16wiy3a_3"
  on "storage"."objects"
  as permissive
  for delete
  to public
using ((bucket_id = 'product-images'::text));



