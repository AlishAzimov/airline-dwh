
--------------------------------------------------------------------------------------------------------
-- Создание процедур слоя ODS: применение данных из STAGE и поддержание актуального состояния таблиц --
--------------------------------------------------------------------------------------------------------


-- Процедура I/U

create or replace procedure ods.upsert_boarding_passes_from_stage()
language plpgsql
as $$
begin
    insert into ods.boarding_passes (
        ticket_no,
        flight_id,
        seat_no,
        boarding_no,
        boarding_time,
        source_system,
        record_source,
        created_batch_id,
        updated_batch_id,
        last_changed_at,
        is_deleted,
        last_operation_type
    )
    select
        s.ticket_no,
        s.flight_id,
        s.seat_no,
        s.boarding_no,
        s.boarding_time,
        s.source_system,
        s.record_source,
        s.batch_id as created_batch_id,
        s.batch_id as updated_batch_id,
        now() as last_changed_at,
        false as is_deleted,
        s.operation_type as last_operation_type
    from stg.boarding_passes s
    where s.is_valid = true
      and s.operation_type in ('I', 'U')
    on conflict (ticket_no, flight_id) do update
    set
        seat_no = excluded.seat_no,
        boarding_no = excluded.boarding_no,
        boarding_time = excluded.boarding_time,
        source_system = excluded.source_system,
        record_source = excluded.record_source,
        updated_batch_id = excluded.updated_batch_id,
        last_changed_at = now(),
        is_deleted = false,
        last_operation_type = excluded.last_operation_type;
end;
$$;


-- Процедура D

create or replace procedure ods.delete_boarding_passes_from_stage()
language plpgsql
as $$
begin
    update ods.boarding_passes o
    set
        updated_batch_id = s.batch_id,
        last_changed_at = now(),
        is_deleted = true,
        last_operation_type = s.operation_type
    from stg.boarding_passes s
    where o.ticket_no = s.ticket_no
      and o.flight_id = s.flight_id
      and s.is_valid = true
      and s.operation_type = 'D';
end;
$$;


-- Главная сборочная процедура

create or replace procedure ods.apply_boarding_passes_from_stage()
language plpgsql
as $$
declare
    v_step_started_at timestamptz;
begin
    v_step_started_at := clock_timestamp();

    call ods.upsert_boarding_passes_from_stage();

    raise notice 'ods.upsert_boarding_passes_from_stage duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call ods.delete_boarding_passes_from_stage();

    raise notice 'ods.delete_boarding_passes_from_stage duration: %',
        clock_timestamp() - v_step_started_at;


    raise notice 'ods.boarding_passes applied. rows = %, active rows = %, deleted rows = %',
        (select count(*) from ods.boarding_passes),
        (select count(*) from ods.boarding_passes where is_deleted = false),
        (select count(*) from ods.boarding_passes where is_deleted = true);
end;
$$;
