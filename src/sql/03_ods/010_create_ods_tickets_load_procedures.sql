
--------------------------------------------------------------------------------------------------------
-- Создание процедур слоя ODS: применение данных из STAGE и поддержание актуального состояния таблиц --
--------------------------------------------------------------------------------------------------------

-- Процедура I/U

create or replace procedure ods.upsert_tickets_from_stage()
language plpgsql
as $$
begin
    insert into ods.tickets (
        ticket_no,
        book_ref,
        passenger_id,
        passenger_name,
        outbound,
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
        s.book_ref,
        s.passenger_id,
        s.passenger_name,
        s.outbound,
        s.source_system,
        s.record_source,
        s.batch_id as created_batch_id,
        s.batch_id as updated_batch_id,
        now() as last_changed_at,
        false as is_deleted,
        s.operation_type as last_operation_type
    from stg.tickets s
    where s.is_valid = true
      and s.operation_type in ('I', 'U')
    on conflict (ticket_no) do update
    set
        book_ref = excluded.book_ref,
        passenger_id = excluded.passenger_id,
        passenger_name = excluded.passenger_name,
        outbound = excluded.outbound,
        source_system = excluded.source_system,
        record_source = excluded.record_source,
        updated_batch_id = excluded.updated_batch_id,
        last_changed_at = now(),
        is_deleted = false,
        last_operation_type = excluded.last_operation_type;
end;
$$;


-- Процедура D

create or replace procedure ods.delete_tickets_from_stage()
language plpgsql
as $$
begin
    update ods.tickets o
    set
        updated_batch_id = s.batch_id,
        last_changed_at = now(),
        is_deleted = true,
        last_operation_type = s.operation_type
    from stg.tickets s
    where o.ticket_no = s.ticket_no
      and s.is_valid = true
      and s.operation_type = 'D';
end;
$$;


-- Главная сборочная процедура

create or replace procedure ods.apply_tickets_from_stage()
language plpgsql
as $$
declare
    v_step_started_at timestamptz;
begin
    v_step_started_at := clock_timestamp();

    call ods.upsert_tickets_from_stage();

    raise notice 'ods.upsert_tickets_from_stage duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call ods.delete_tickets_from_stage();

    raise notice 'ods.delete_tickets_from_stage duration: %',
        clock_timestamp() - v_step_started_at;


    raise notice 'ods.tickets applied. rows = %, active rows = %, deleted rows = %',
        (select count(*) from ods.tickets),
        (select count(*) from ods.tickets where is_deleted = false),
        (select count(*) from ods.tickets where is_deleted = true);
end;
$$;