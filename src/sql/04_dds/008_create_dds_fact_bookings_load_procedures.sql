--------------------------------------------------------------------------------------------------------
-- Создание процедур слоя DDS: загрузка фактов бронирований из ODS в DDS --
--------------------------------------------------------------------------------------------------------


-- Процедура I/U/D: вставка новых и обновление существующих бронирований

create or replace procedure dds.upsert_fact_bookings_from_ods()
language plpgsql
as $$
begin

    insert into dds.fact_bookings (
        book_ref,
        book_date,
        total_amount,
        source_system,
        record_source,
        batch_id,
        last_changed_at,
        is_deleted
    )
    select
        o.book_ref,
        o.book_date,
        o.total_amount,
        o.source_system,
        o.record_source,
        o.updated_batch_id as batch_id,
        now() as last_changed_at,
        o.is_deleted
    from ods.bookings o

    on conflict (book_ref) do update
    set
        book_date = excluded.book_date,
        total_amount = excluded.total_amount,
        source_system = excluded.source_system,
        record_source = excluded.record_source,
        batch_id = excluded.batch_id,
        last_changed_at = now(),
        is_deleted = excluded.is_deleted
    where dds.fact_bookings.batch_id != excluded.batch_id;

end;
$$;


-- Главная сборочная процедура

create or replace procedure dds.load_fact_bookings_from_ods()
language plpgsql
as $$
declare
    v_step_started_at timestamptz;
begin
    v_step_started_at := clock_timestamp();

    call dds.upsert_fact_bookings_from_ods();

    raise notice 'dds.upsert_fact_bookings_from_ods duration: %',
        clock_timestamp() - v_step_started_at;

    raise notice 'dds.fact_bookings loaded. rows = %, active rows = %, deleted rows = %',
        (select count(*) from dds.fact_bookings),
        (select count(*) from dds.fact_bookings where is_deleted = false),
        (select count(*) from dds.fact_bookings where is_deleted = true);
end;
$$;