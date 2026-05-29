
--------------------------------------------------------------------------------------------------------
-- Создание процедур слоя ODS: применение данных из STAGE и поддержание актуального состояния таблиц --
--------------------------------------------------------------------------------------------------------


-- Процедура I/U

create or replace procedure ods.upsert_bookings_from_stage()
language plpgsql
as $$
begin
    insert into ods.bookings (
        book_ref,
        book_date,
        total_amount,
        source_system,
        record_source,
        created_batch_id,
        updated_batch_id,
        last_changed_at,
        is_deleted,
        last_operation_type
    )
    select
        s.book_ref,
        s.book_date,
        s.total_amount,
        s.source_system,
        s.record_source,
        s.batch_id as created_batch_id,
        s.batch_id as updated_batch_id,
        now() as last_changed_at,
        false as is_deleted,
        s.operation_type as last_operation_type
    from stg.bookings s
    where s.is_valid = true
      and s.operation_type in ('I', 'U')
    on conflict (book_ref) do update
    set
        book_date = excluded.book_date,
        total_amount = excluded.total_amount,
        source_system = excluded.source_system,
        record_source = excluded.record_source,
        updated_batch_id = excluded.updated_batch_id,
        last_changed_at = now(),
        is_deleted = false,
        last_operation_type = excluded.last_operation_type;
end;
$$;


-- Процедура D

create or replace procedure ods.delete_bookings_from_stage()
language plpgsql
as $$
begin
    update ods.bookings o
    set
        updated_batch_id = s.batch_id,
        last_changed_at = now(),
        is_deleted = true,
        last_operation_type = s.operation_type
    from stg.bookings s
    where o.book_ref = s.book_ref
      and s.is_valid = true
      and s.operation_type = 'D';
end;
$$;


-- Главная сборочная процедура

create or replace procedure ods.apply_bookings_from_stage()
language plpgsql
as $$
declare
    v_step_started_at timestamptz;
begin
    v_step_started_at := clock_timestamp();

    call ods.upsert_bookings_from_stage();

    raise notice 'ods.upsert_bookings_from_stage duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call ods.delete_bookings_from_stage();

    raise notice 'ods.delete_bookings_from_stage duration: %',
        clock_timestamp() - v_step_started_at;


    raise notice 'ods.bookings applied. rows = %, active rows = %, deleted rows = %',
        (select count(*) from ods.bookings),
        (select count(*) from ods.bookings where is_deleted = false),
        (select count(*) from ods.bookings where is_deleted = true);
end;
$$;
