--------------------------------------------------------------------------------------------------------
-- Создание процедур слоя DDS: загрузка SCD1-измерения мест из ODS в DDS --
--------------------------------------------------------------------------------------------------------


-- Процедура I/U/D: вставка новых и обновление существующих мест

create or replace procedure dds.upsert_dim_seats_from_ods()
language plpgsql
as $$

declare
    v_last_loaded_batch_id bigint;

begin

    select coalesce(max(batch_id), 0)
    into v_last_loaded_batch_id
    from dds.dim_seats;
	
    insert into dds.dim_seats (
		seat_sk,
        airplane_code,
        seat_no,
        airplane_sk,
        fare_conditions,
        source_system,
        record_source,
        batch_id,
        last_changed_at,
        is_deleted
    )
    select
		md5(o.airplane_code || '|' || o.seat_no)::uuid,
        o.airplane_code,
        o.seat_no,
        a.airplane_sk,
        o.fare_conditions,
        o.source_system,
        o.record_source,
        o.updated_batch_id as batch_id,
        now() as last_changed_at,
        o.is_deleted
    from ods.seats o
    join dds.dim_airplanes a
        on a.airplane_code = o.airplane_code
       and a.is_current = true
	where o.updated_batch_id > v_last_loaded_batch_id

    on conflict (airplane_code, seat_no) do update
    set
        airplane_sk = excluded.airplane_sk,
        fare_conditions = excluded.fare_conditions,
        source_system = excluded.source_system,
        record_source = excluded.record_source,
        batch_id = excluded.batch_id,
        last_changed_at = now(),
        is_deleted =  excluded.is_deleted
	where dds.dim_seats.batch_id != excluded.batch_id;
end;
$$;



-- Главная сборочная процедур

create or replace procedure dds.load_dim_seats_from_ods()
language plpgsql
as $$
declare
    v_step_started_at timestamptz;
begin
    v_step_started_at := clock_timestamp();

    call dds.upsert_dim_seats_from_ods();

    raise notice 'dds.upsert_dim_seats_from_ods duration: %',
        clock_timestamp() - v_step_started_at;

    raise notice 'dds.dim_seats loaded. rows = %, active rows = %, deleted rows = %',
        (select count(*) from dds.dim_seats),
        (select count(*) from dds.dim_seats where is_deleted = false),
        (select count(*) from dds.dim_seats where is_deleted = true);
end;
$$;