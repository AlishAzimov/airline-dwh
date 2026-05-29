
--------------------------------------------------------------------------------------------------------
-- Создание процедур слоя ODS: применение данных из STAGE и поддержание актуального состояния таблиц --
--------------------------------------------------------------------------------------------------------

-- Процедура I/U

create or replace procedure ods.upsert_routes_from_stage()
language plpgsql
as $$
begin
    insert into ods.routes (
        route_no,
        validity,
        departure_airport,
        arrival_airport,
        airplane_code,
        days_of_week,
        scheduled_time,
        duration,
        source_system,
        record_source,
        created_batch_id,
        updated_batch_id,
        last_changed_at,
        is_deleted,
        last_operation_type
    )
    select
        s.route_no,
        s.validity,
        s.departure_airport,
        s.arrival_airport,
        s.airplane_code,
        s.days_of_week,
        s.scheduled_time,
        s.duration,
        s.source_system,
        s.record_source,
        s.batch_id as created_batch_id,
        s.batch_id as updated_batch_id,
        now() as last_changed_at,
        false as is_deleted,
        s.operation_type as last_operation_type
    from stg.routes s
    where s.is_valid = true
      and s.operation_type in ('I', 'U')
    on conflict (route_no, validity) do update
    set
        departure_airport = excluded.departure_airport,
        arrival_airport = excluded.arrival_airport,
        airplane_code = excluded.airplane_code,
        days_of_week = excluded.days_of_week,
        scheduled_time = excluded.scheduled_time,
        duration = excluded.duration,
        source_system = excluded.source_system,
        record_source = excluded.record_source,
        updated_batch_id = excluded.updated_batch_id,
        last_changed_at = now(),
        is_deleted = false,
        last_operation_type = excluded.last_operation_type;
end;
$$;


-- Процедура D

create or replace procedure ods.delete_routes_from_stage()
language plpgsql
as $$
begin
    update ods.routes o
    set
        updated_batch_id = s.batch_id,
        last_changed_at = now(),
        is_deleted = true,
        last_operation_type = s.operation_type
    from stg.routes s
    where o.route_no = s.route_no
      and o.validity = s.validity
      and s.is_valid = true
      and s.operation_type = 'D';
end;
$$;


-- Главная сборочная процедура

create or replace procedure ods.apply_routes_from_stage()
language plpgsql
as $$
declare
    v_step_started_at timestamptz;
begin
    v_step_started_at := clock_timestamp();

    call ods.upsert_routes_from_stage();

    raise notice 'ods.upsert_routes_from_stage duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call ods.delete_routes_from_stage();

    raise notice 'ods.delete_routes_from_stage duration: %',
        clock_timestamp() - v_step_started_at;


    raise notice 'ods.routes applied. rows = %, active rows = %, deleted rows = %',
        (select count(*) from ods.routes),
        (select count(*) from ods.routes where is_deleted = false),
        (select count(*) from ods.routes where is_deleted = true);
end;
$$;