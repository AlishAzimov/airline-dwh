--------------------------------------------------------------------------------------------------------
-- Создание процедур слоя DDS: загрузка фактов сегментов из ODS в DDS --
--------------------------------------------------------------------------------------------------------


-- Процедура I/U/D: вставка новых и обновление существующих сегментов

create or replace procedure dds.upsert_fact_segments_from_ods()
language plpgsql
as $$
declare
    v_last_loaded_batch_id bigint;
begin

    select coalesce(max(batch_id), 0)
    into v_last_loaded_batch_id
    from dds.fact_segments;

    insert into dds.fact_segments (
        ticket_sk,
        flight_sk,
        ticket_no,
        flight_id,
        fare_conditions,
        price,
        source_system,
        record_source,
        batch_id,
        last_changed_at,
        is_deleted
    )
    select
        ft.ticket_sk,
        ff.flight_sk,      
        o.ticket_no,
        o.flight_id,
        o.fare_conditions,
        o.price,
        o.source_system,
        o.record_source,
        o.updated_batch_id as batch_id,
        now() as last_changed_at,
        o.is_deleted
    from ods.segments o
    left join dds.fact_tickets ft
        on o.ticket_no = ft.ticket_no
    left join dds.fact_flights ff
        on o.flight_id = ff.flight_id
    where o.updated_batch_id > v_last_loaded_batch_id

    on conflict (ticket_no, flight_id) do update
    set
        ticket_sk = excluded.ticket_sk,
        flight_sk = excluded.flight_sk,
        fare_conditions = excluded.fare_conditions,
        price = excluded.price,
        source_system = excluded.source_system,
        record_source = excluded.record_source,
        batch_id = excluded.batch_id,
        last_changed_at = now(),
        is_deleted = excluded.is_deleted;

end;
$$;


-- Главная сборочная процедура

create or replace procedure dds.load_fact_segments_from_ods()
language plpgsql
as $$
declare
    v_step_started_at timestamptz;
begin
    v_step_started_at := clock_timestamp();

    call dds.upsert_fact_segments_from_ods();

    raise notice 'dds.upsert_fact_segments_from_ods duration: %',
        clock_timestamp() - v_step_started_at;

    raise notice 'dds.fact_segments loaded. rows = %, active rows = %, deleted rows = %',
        (select count(*) from dds.fact_segments),
        (select count(*) from dds.fact_segments where is_deleted = false),
        (select count(*) from dds.fact_segments where is_deleted = true);
end;
$$;