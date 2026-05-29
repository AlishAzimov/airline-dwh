------------------------------------------------------------------------------------------------------
-- Создание процедур слоя STAGE: загрузка, очистка и валидация данных из RAW перед передачей в ODS --
------------------------------------------------------------------------------------------------------

-- Функция определения batch_id

create or replace function stg.get_routes_batch_id(p_batch_id bigint default null)
returns bigint
language plpgsql
as $$
declare
    v_batch_id bigint;
begin
    v_batch_id := p_batch_id;

    if v_batch_id is null then
        select max(batch_id)
        into v_batch_id
        from raw.routes;
    end if;

    if v_batch_id is null then
        raise exception 'No batch_id found in raw.routes';
    end if;

    return v_batch_id;
end;
$$;


-- Процедура загрузки из RAW в STAGE

create or replace procedure stg.insert_routes_from_raw(p_batch_id bigint)
language plpgsql
as $$
begin
    if p_batch_id is null then
        raise exception 'p_batch_id cannot be null in stg.insert_routes_from_raw';
    end if;

    insert into stg.routes (
        route_no,
        validity,
        departure_airport,
        arrival_airport,
        airplane_code,
        days_of_week,
        scheduled_time,
        duration,
        raw_load_date,
        stg_load_date,
        source_system,
        record_source,
        batch_id,
        operation_type
    )
    select
        nullif(trim(r.route_no), '') as route_no,
        r.validity,
        upper(nullif(trim(r.departure_airport::text), '')) as departure_airport,
        upper(nullif(trim(r.arrival_airport::text), '')) as arrival_airport,
        upper(nullif(trim(r.airplane_code::text), '')) as airplane_code,
        r.days_of_week,
        r.scheduled_time,
        r.duration,
        r.load_date as raw_load_date,
        now() as stg_load_date,
        r.source_system,
        r.record_source,
        r.batch_id,
        r.operation_type
    from raw.routes r
    where r.batch_id = p_batch_id;
end;
$$;


-- Процедура проверки качества данных

create or replace procedure stg.validate_routes()
language plpgsql
as $$
begin
    update stg.routes
    set
        is_valid =
            case
                when route_no is null then false
                when trim(route_no) = '' then false
                when validity is null then false
                when departure_airport is null then false
                when trim(departure_airport) = '' then false
                when arrival_airport is null then false
                when trim(arrival_airport) = '' then false
                when departure_airport = arrival_airport then false
                when airplane_code is null then false
                when trim(airplane_code) = '' then false
                when days_of_week is null then false
                when scheduled_time is null then false
                when duration is null then false
                when duration <= interval '0 seconds' then false
                when operation_type not in ('I', 'U', 'D') then false
                else true
            end,

        validation_error =
            nullif(
                concat_ws(
                    '; ',
                    case
                        when route_no is null or trim(route_no) = ''
                        then 'route_no is empty'
                    end,
                    case
                        when validity is null
                        then 'validity is null'
                    end,
                    case
                        when departure_airport is null or trim(departure_airport) = ''
                        then 'departure_airport is empty'
                    end,
                    case
                        when arrival_airport is null or trim(arrival_airport) = ''
                        then 'arrival_airport is empty'
                    end,
                    case
                        when departure_airport is not null
                             and arrival_airport is not null
                             and departure_airport = arrival_airport
                        then 'departure_airport equals arrival_airport'
                    end,
                    case
                        when airplane_code is null or trim(airplane_code) = ''
                        then 'airplane_code is empty'
                    end,
                    case
                        when days_of_week is null
                        then 'days_of_week is null'
                    end,
                    case
                        when scheduled_time is null
                        then 'scheduled_time is null'
                    end,
                    case
                        when duration is null
                        then 'duration is null'
                    end,
                    case
                        when duration is not null
                             and duration <= interval '0 seconds'
                        then 'duration must be greater than 0'
                    end,
                    case
                        when operation_type not in ('I', 'U', 'D')
                        then 'operation_type is invalid'
                    end
                ),
                ''
            );
end;
$$;


-- Главная сборочная процедура

create or replace procedure stg.load_routes_from_raw(p_batch_id bigint default null)
language plpgsql
as $$
declare
    v_batch_id bigint;
    v_step_started_at timestamptz;
begin
    v_batch_id := stg.get_routes_batch_id(p_batch_id);

    v_step_started_at := clock_timestamp();

    truncate table stg.routes;

    raise notice 'truncate table stg.routes duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call stg.insert_routes_from_raw(v_batch_id);

    raise notice 'stg.insert_routes_from_raw duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call stg.validate_routes();

    raise notice 'stg.validate_routes duration: %',
        clock_timestamp() - v_step_started_at;


    raise notice 'stg.routes loaded. batch_id = %, rows = %, invalid rows = %',
        v_batch_id,
        (select count(*) from stg.routes),
        (select count(*) from stg.routes where is_valid = false);
end;
$$;