------------------------------------------------------------------------------------------------------
-- Создание процедур слоя STAGE: загрузка, очистка и валидация данных из RAW перед передачей в ODS --
------------------------------------------------------------------------------------------------------

-- Функция определения batch_id

create or replace function stg.get_flights_batch_id(p_batch_id bigint default null)
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
        from raw.flights;
    end if;

    if v_batch_id is null then
        raise exception 'No batch_id found in raw.flights';
    end if;

    return v_batch_id;
end;
$$;


-- Процедура загрузки из RAW в STAGE

create or replace procedure stg.insert_flights_from_raw(p_batch_id bigint)
language plpgsql
as $$
begin
    if p_batch_id is null then
        raise exception 'p_batch_id cannot be null in stg.insert_flights_from_raw';
    end if;

    insert into stg.flights (
        flight_id,
        route_no,
        status,
        scheduled_departure,
        scheduled_arrival,
        actual_departure,
        actual_arrival,
        raw_load_date,
        stg_load_date,
        source_system,
        record_source,
        batch_id,
        operation_type
    )
    select
        r.flight_id,
        nullif(trim(r.route_no), '') as route_no,
        nullif(trim(r.status), '') as status,
        r.scheduled_departure,
        r.scheduled_arrival,
        r.actual_departure,
        r.actual_arrival,
        r.load_date as raw_load_date,
        now() as stg_load_date,
        r.source_system,
        r.record_source,
        r.batch_id,
        r.operation_type
    from raw.flights r
    where r.batch_id = p_batch_id;
end;
$$;


-- Процедура проверки качества данных

create or replace procedure stg.validate_flights()
language plpgsql
as $$
begin
    update stg.flights
    set
        is_valid =
            case
                when flight_id is null then false
                when route_no is null then false
                when trim(route_no) = '' then false
                when status is null then false
                when trim(status) = '' then false
                when status not in ('Scheduled', 'On Time', 'Delayed', 'Boarding', 'Departed', 'Arrived', 'Cancelled') then false
                when scheduled_departure is null then false
                when scheduled_arrival is null then false
                when scheduled_arrival <= scheduled_departure then false
                when actual_arrival is not null and actual_departure is null then false
                when actual_arrival is not null and actual_departure is not null and actual_arrival <= actual_departure then false
                when operation_type not in ('I', 'U', 'D') then false
                else true
            end,

        validation_error =
            nullif(
                concat_ws(
                    '; ',
                    case
                        when flight_id is null
                        then 'flight_id is null'
                    end,
                    case
                        when route_no is null or trim(route_no) = ''
                        then 'route_no is empty'
                    end,
                    case
                        when status is null or trim(status) = ''
                        then 'status is empty'
                    end,
                    case
                        when status is not null
                             and trim(status) <> ''
                             and status not in ('Scheduled', 'On Time', 'Delayed', 'Boarding', 'Departed', 'Arrived', 'Cancelled')
                        then 'status is invalid'
                    end,
                    case
                        when scheduled_departure is null
                        then 'scheduled_departure is null'
                    end,
                    case
                        when scheduled_arrival is null
                        then 'scheduled_arrival is null'
                    end,
                    case
                        when scheduled_departure is not null
                             and scheduled_arrival is not null
                             and scheduled_arrival <= scheduled_departure
                        then 'scheduled_arrival must be greater than scheduled_departure'
                    end,
                    case
                        when actual_arrival is not null and actual_departure is null
                        then 'actual_departure is null while actual_arrival is not null'
                    end,
                    case
                        when actual_arrival is not null
                             and actual_departure is not null
                             and actual_arrival <= actual_departure
                        then 'actual_arrival must be greater than actual_departure'
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

create or replace procedure stg.load_flights_from_raw(p_batch_id bigint default null)
language plpgsql
as $$
declare
    v_batch_id bigint;
    v_step_started_at timestamptz;
begin
    v_batch_id := stg.get_flights_batch_id(p_batch_id);

    v_step_started_at := clock_timestamp();

    truncate table stg.flights;

    raise notice 'truncate table stg.flights duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call stg.insert_flights_from_raw(v_batch_id);

    raise notice 'stg.insert_flights_from_raw duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call stg.validate_flights();

    raise notice 'stg.validate_flights duration: %',
        clock_timestamp() - v_step_started_at;


    raise notice 'stg.flights loaded. batch_id = %, rows = %, invalid rows = %',
        v_batch_id,
        (select count(*) from stg.flights),
        (select count(*) from stg.flights where is_valid = false);
end;
$$;