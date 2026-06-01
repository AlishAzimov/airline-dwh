--------------------------------------------------------------------------------------------------------
-- Создание процедур слоя DDS: загрузка SCD1-измерения мест из ODS в DDS --
--------------------------------------------------------------------------------------------------------


-- Процедура I/U: вставка новых и обновление существующих мест

create or replace procedure dds.upsert_dim_seats_from_ods()
language plpgsql
as $$
begin
    insert into dds.dim_seats (
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
        o.airplane_code,
        o.seat_no,
        a.airplane_sk,
        o.fare_conditions,
        o.source_system,
        o.record_source,
        o.updated_batch_id as batch_id,
        now() as last_changed_at,
        false as is_deleted
    from ods.seats o
    left join dds.dim_airplanes a
        on a.airplane_code = o.airplane_code
       and a.is_current = true
    where o.is_deleted = false
    on conflict (airplane_code, seat_no) do update
    set
        airplane_sk = excluded.airplane_sk,
        fare_conditions = excluded.fare_conditions,
        source_system = excluded.source_system,
        record_source = excluded.record_source,
        batch_id = excluded.batch_id,
        last_changed_at = now(),
        is_deleted = false
	where coalesce(dds.dim_seats.airplane_sk, -1) != coalesce(excluded.airplane_sk, -1)
	   or coalesce(dds.dim_seats.fare_conditions, '') != coalesce(excluded.fare_conditions, '')
	   or coalesce(dds.dim_seats.source_system, '') != coalesce(excluded.source_system, '')
	   or coalesce(dds.dim_seats.record_source, '') != coalesce(excluded.record_source, '')
	   or coalesce(dds.dim_seats.is_deleted, false) != false;
end;
$$;


-- Процедура D: логическое удаление мест

create or replace procedure dds.delete_dim_seats_from_ods()
language plpgsql
as $$
begin
    update dds.dim_seats d
    set
        batch_id = o.updated_batch_id,
        last_changed_at = now(),
        is_deleted = true
    from ods.seats o
    where d.airplane_code = o.airplane_code
      and d.seat_no = o.seat_no
      and o.is_deleted = true;
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


    v_step_started_at := clock_timestamp();

    call dds.delete_dim_seats_from_ods();

    raise notice 'dds.delete_dim_seats_from_ods duration: %',
        clock_timestamp() - v_step_started_at;


    raise notice 'dds.dim_seats loaded. rows = %, active rows = %, deleted rows = %',
        (select count(*) from dds.dim_seats),
        (select count(*) from dds.dim_seats where is_deleted = false),
        (select count(*) from dds.dim_seats where is_deleted = true);
end;
$$;