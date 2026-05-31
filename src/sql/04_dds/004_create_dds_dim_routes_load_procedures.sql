--------------------------------------------------------------------------------------------------------
-- Создание процедур слоя DDS: загрузка SCD2-измерения маршрутов из ODS в DDS --
--------------------------------------------------------------------------------------------------------


-- Процедура закрытия текущих версий, если данные изменились

create or replace procedure dds.close_changed_dim_routes(p_effective_at timestamptz)
language plpgsql
as $$
begin
    update dds.dim_routes d
    set
        valid_to = p_effective_at,
        is_current = false,
        batch_id = o.updated_batch_id
    from ods.routes o
    left join dds.dim_airports dep
        on dep.airport_code = o.departure_airport
       and dep.is_current = true
    left join dds.dim_airports arr
        on arr.airport_code = o.arrival_airport
       and arr.is_current = true
    left join dds.dim_airplanes a
        on a.airplane_code = o.airplane_code
       and a.is_current = true
    where d.route_no = o.route_no
      and d.validity = o.validity
      and d.is_current = true
      and (
             o.is_deleted = true
          or coalesce(d.departure_airport, '') != coalesce(o.departure_airport, '')
          or coalesce(d.arrival_airport, '') != coalesce(o.arrival_airport, '')
          or coalesce(d.airplane_code, '') != coalesce(o.airplane_code, '')
          or coalesce(d.departure_airport_sk, -1) != coalesce(dep.airport_sk, -1)
          or coalesce(d.arrival_airport_sk, -1) != coalesce(arr.airport_sk, -1)
          or coalesce(d.airplane_sk, -1) != coalesce(a.airplane_sk, -1)
          or coalesce(d.days_of_week, array[]::integer[]) != coalesce(o.days_of_week, array[]::integer[])
          or coalesce(d.scheduled_time::text, '') != coalesce(o.scheduled_time::text, '')
          or coalesce(d.duration::text, '') != coalesce(o.duration::text, '')
      );
end;
$$;


-- Процедура вставки новых текущих версий

create or replace procedure dds.insert_new_dim_routes(p_effective_at timestamptz)
language plpgsql
as $$
begin
    insert into dds.dim_routes (
        route_no,
        validity,
        departure_airport,
        arrival_airport,
        airplane_code,
        departure_airport_sk,
        arrival_airport_sk,
        airplane_sk,
        days_of_week,
        scheduled_time,
        duration,
        source_system,
        record_source,
        valid_from,
        batch_id
    )
    select
        o.route_no,
        o.validity,
        o.departure_airport,
        o.arrival_airport,
        o.airplane_code,
        dep.airport_sk as departure_airport_sk,
        arr.airport_sk as arrival_airport_sk,
        a.airplane_sk,
        o.days_of_week,
        o.scheduled_time,
        o.duration,
        o.source_system,
        o.record_source,
        p_effective_at as valid_from,
        o.updated_batch_id as batch_id
    from ods.routes o
    left join dds.dim_airports dep
        on dep.airport_code = o.departure_airport
       and dep.is_current = true
    left join dds.dim_airports arr
        on arr.airport_code = o.arrival_airport
       and arr.is_current = true
    left join dds.dim_airplanes a
        on a.airplane_code = o.airplane_code
       and a.is_current = true
    left join dds.dim_routes d
        on d.route_no = o.route_no
       and d.validity = o.validity
       and d.is_current = true
    where o.is_deleted = false
      and d.route_sk is null;
end;
$$;


-- Главная сборочная процедура

create or replace procedure dds.load_dim_routes_from_ods()
language plpgsql
as $$
declare
    v_effective_at timestamptz := now();
    v_step_started_at timestamptz;
begin
    v_step_started_at := clock_timestamp();

    call dds.close_changed_dim_routes(v_effective_at);

    raise notice 'dds.close_changed_dim_routes duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call dds.insert_new_dim_routes(v_effective_at);

    raise notice 'dds.insert_new_dim_routes duration: %',
        clock_timestamp() - v_step_started_at;


    raise notice 'dds.dim_routes loaded. rows = %, current rows = %, historical rows = %',
        (select count(*) from dds.dim_routes),
        (select count(*) from dds.dim_routes where is_current = true),
        (select count(*) from dds.dim_routes where is_current = false);
end;
$$;