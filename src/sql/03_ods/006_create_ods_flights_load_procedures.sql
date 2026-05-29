
--------------------------------------------------------------------------------------------------------
-- Создание процедур слоя ODS: применение данных из STAGE и поддержание актуального состояния таблиц --
--------------------------------------------------------------------------------------------------------

-- Процедура I/U

create or replace procedure ods.upsert_flights_from_stage()
language plpgsql
as $$
begin
    insert into ods.flights (
        flight_id,
        route_no,
        status,
        scheduled_departure,
        scheduled_arrival,
        actual_departure,
        actual_arrival,
        source_system,
        record_source,
        created_batch_id,
        updated_batch_id,
        last_changed_at,
        is_deleted,
        last_operation_type
    )
    select
        s.flight_id,
        s.route_no,
        s.status,
        s.scheduled_departure,
        s.scheduled_arrival,
        s.actual_departure,
        s.actual_arrival,
        s.source_system,
        s.record_source,
        s.batch_id as created_batch_id,
        s.batch_id as updated_batch_id,
        now() as last_changed_at,
        false as is_deleted,
        s.operation_type as last_operation_type
    from stg.flights s
    where s.is_valid = true
      and s.operation_type in ('I', 'U')
    on conflict (flight_id) do update
    set
        route_no = excluded.route_no,
        status = excluded.status,
        scheduled_departure = excluded.scheduled_departure,
        scheduled_arrival = excluded.scheduled_arrival,
        actual_departure = excluded.actual_departure,
        actual_arrival = excluded.actual_arrival,
        source_system = excluded.source_system,
        record_source = excluded.record_source,
        updated_batch_id = excluded.updated_batch_id,
        last_changed_at = now(),
        is_deleted = false,
        last_operation_type = excluded.last_operation_type;
end;
$$;


-- Процедура D

create or replace procedure ods.delete_flights_from_stage()
language plpgsql
as $$
begin
    update ods.flights o
    set
        updated_batch_id = s.batch_id,
        last_changed_at = now(),
        is_deleted = true,
        last_operation_type = s.operation_type
    from stg.flights s
    where o.flight_id = s.flight_id
      and s.is_valid = true
      and s.operation_type = 'D';
end;
$$;


-- Главная сборочная процедура

create or replace procedure ods.apply_flights_from_stage()
language plpgsql
as $$
declare
    v_step_started_at timestamptz;
begin
    v_step_started_at := clock_timestamp();

    call ods.upsert_flights_from_stage();

    raise notice 'ods.upsert_flights_from_stage duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call ods.delete_flights_from_stage();

    raise notice 'ods.delete_flights_from_stage duration: %',
        clock_timestamp() - v_step_started_at;


    raise notice 'ods.flights applied. rows = %, active rows = %, deleted rows = %',
        (select count(*) from ods.flights),
        (select count(*) from ods.flights where is_deleted = false),
        (select count(*) from ods.flights where is_deleted = true);
end;
$$;