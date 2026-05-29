
--------------------------------------------------------------------------------------------------------
-- Создание процедур слоя ODS: применение данных из STAGE и поддержание актуального состояния таблиц --
--------------------------------------------------------------------------------------------------------

-- Процедура I/U

create or replace procedure ods.upsert_seats_from_stage()
language plpgsql
as $$
begin
    insert into ods.seats (
        airplane_code,
        seat_no,
        fare_conditions,
        source_system,
        record_source,
        created_batch_id,
        updated_batch_id,
        last_changed_at,
        is_deleted,
        last_operation_type
    )
    select
        s.airplane_code,
        s.seat_no,
        s.fare_conditions,
        s.source_system,
        s.record_source,
        s.batch_id as created_batch_id,
        s.batch_id as updated_batch_id,
        now() as last_changed_at,
        false as is_deleted,
        s.operation_type as last_operation_type
    from stg.seats s
    where s.is_valid = true
      and s.operation_type in ('I', 'U')
    on conflict (airplane_code, seat_no) do update
    set
        fare_conditions = excluded.fare_conditions,
        source_system = excluded.source_system,
        record_source = excluded.record_source,
        updated_batch_id = excluded.updated_batch_id,
        last_changed_at = now(),
        is_deleted = false,
        last_operation_type = excluded.last_operation_type;
end;
$$;


-- Процедура D

create or replace procedure ods.delete_seats_from_stage()
language plpgsql
as $$
begin
    update ods.seats o
    set
        updated_batch_id = s.batch_id,
        last_changed_at = now(),
        is_deleted = true,
        last_operation_type = s.operation_type
    from stg.seats s
    where o.airplane_code = s.airplane_code
      and o.seat_no = s.seat_no
      and s.is_valid = true
      and s.operation_type = 'D';
end;
$$;


-- Главная сборочная процедура

create or replace procedure ods.apply_seats_from_stage()
language plpgsql
as $$
declare
    v_step_started_at timestamptz;
begin
    v_step_started_at := clock_timestamp();

    call ods.upsert_seats_from_stage();

    raise notice 'ods.upsert_seats_from_stage duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call ods.delete_seats_from_stage();

    raise notice 'ods.delete_seats_from_stage duration: %',
        clock_timestamp() - v_step_started_at;


    raise notice 'ods.seats applied. rows = %, active rows = %, deleted rows = %',
        (select count(*) from ods.seats),
        (select count(*) from ods.seats where is_deleted = false),
        (select count(*) from ods.seats where is_deleted = true);
end;
$$;