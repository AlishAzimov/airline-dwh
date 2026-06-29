--------------------------------------------------------------------------------------------------------
-- Создание процедур слоя DDS: загрузка SCD1-измерения маршрутов из ODS в DDS
--------------------------------------------------------------------------------------------------------

create or replace procedure dds.upsert_dim_routes_from_ods()
language plpgsql
as $$
declare
    v_last_loaded_batch_id bigint;
begin

    select coalesce(max(batch_id), 0)
    into v_last_loaded_batch_id
    from dds.dim_routes;

    insert into dds.dim_routes (
        route_sk,
        route_no,
        validity,
        departure_airport_sk,
        arrival_airport_sk,
        airplane_sk,
        days_of_week,
        scheduled_time,
        duration,
        source_system,
        record_source,
        batch_id,
        last_changed_at,
        is_deleted
    )
    select distinct on (o.route_no, o.validity)
        md5(o.route_no || '|' || lower(o.validity)::text || '|' || upper(o.validity)::text)::uuid as route_sk,
        o.route_no,
        o.validity,
        dep.airport_sk as departure_airport_sk,
        arr.airport_sk as arrival_airport_sk,
        a.airplane_sk as airplane_sk,
        o.days_of_week,
        o.scheduled_time,
        o.duration,
        o.source_system,
        o.record_source,
        o.updated_batch_id as batch_id,
        now() as last_changed_at,
        o.is_deleted
	from ods.routes o
	join dds.dim_airports dep
	    on dep.airport_code = o.departure_airport
	   and dep.is_current = true
	join dds.dim_airports arr
	    on arr.airport_code = o.arrival_airport
	   and arr.is_current = true
	join dds.dim_airplanes a
	    on a.airplane_code = o.airplane_code
	   and a.is_current = true
    where o.updated_batch_id > v_last_loaded_batch_id
    order by o.route_no, o.validity, o.updated_batch_id desc

    on conflict (route_no, validity) do update
    set
        departure_airport_sk = excluded.departure_airport_sk,
        arrival_airport_sk = excluded.arrival_airport_sk,
        airplane_sk = excluded.airplane_sk,
        days_of_week = excluded.days_of_week,
        scheduled_time = excluded.scheduled_time,
        duration = excluded.duration,
        source_system = excluded.source_system,
        record_source = excluded.record_source,
        batch_id = excluded.batch_id,
        last_changed_at = now(),
        is_deleted = excluded.is_deleted;

end;
$$;


-- Главная сборочная процедура

create or replace procedure dds.load_dim_routes_from_ods()
language plpgsql
as $$
declare
    v_step_started_at timestamptz;
begin
    v_step_started_at := clock_timestamp();

    call dds.upsert_dim_routes_from_ods();

    raise notice 'dds.upsert_dim_routes_from_ods duration: %',
        clock_timestamp() - v_step_started_at;

    raise notice 'dds.dim_routes loaded. rows = %, deleted rows = %',
        (select count(*) from dds.dim_routes),
        (select count(*) from dds.dim_routes where is_deleted = true);
end;
$$;