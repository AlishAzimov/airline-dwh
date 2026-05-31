------------------------------------------------------------------------------------------------------
-- Создание процедур слоя STAGE: загрузка, очистка и валидация данных из RAW перед передачей в ODS --
------------------------------------------------------------------------------------------------------

-- Функция определения batch_id

create or replace function stg.get_segments_batch_id(p_batch_id bigint default null)
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
        from raw.segments;
    end if;

    if v_batch_id is null then
        raise exception 'No batch_id found in raw.segments';
    end if;

    return v_batch_id;
end;
$$;


-- Процедура загрузки из RAW в STAGE

create or replace procedure stg.insert_segments_from_raw(p_batch_id bigint)
language plpgsql
as $$
begin
    if p_batch_id is null then
        raise exception 'p_batch_id cannot be null in stg.insert_segments_from_raw';
    end if;

    insert into stg.segments (
        ticket_no,
        flight_id,
        fare_conditions,
        price,
        raw_load_date,
        stg_load_date,
        source_system,
        record_source,
        batch_id,
        operation_type
    )
    select
        nullif(trim(r.ticket_no), '') as ticket_no,
        r.flight_id,
        nullif(trim(r.fare_conditions), '') as fare_conditions,
        r.price,
        r.load_date as raw_load_date,
        now() as stg_load_date,
        r.source_system,
        r.record_source,
        r.batch_id,
        r.operation_type
    from raw.segments r
    where r.batch_id = p_batch_id;
end;
$$;


-- Процедура проверки качества данных

create or replace procedure stg.validate_segments()
language plpgsql
as $$
begin
    update stg.segments
    set
        is_valid =
            case
                when ticket_no is null then false
                when trim(ticket_no) = '' then false
                when flight_id is null then false
                when fare_conditions is null then false
                when trim(fare_conditions) = '' then false
                when fare_conditions not in ('Economy', 'Comfort', 'Business') then false
                when price is null then false
                when price < 0 then false
                when operation_type not in ('I', 'U', 'D') then false
                else true
            end,

        validation_error =
            nullif(
                concat_ws(
                    '; ',
                    case
                        when ticket_no is null or trim(ticket_no) = ''
                        then 'ticket_no is empty'
                    end,
                    case
                        when flight_id is null
                        then 'flight_id is null'
                    end,
                    case
                        when fare_conditions is null or trim(fare_conditions) = ''
                        then 'fare_conditions is empty'
                    end,
                    case
                        when fare_conditions is not null
                             and trim(fare_conditions) <> ''
                             and fare_conditions not in ('Economy', 'Comfort', 'Business')
                        then 'fare_conditions is invalid'
                    end,
                    case
                        when price is null
                        then 'price is null'
                    end,
                    case
                        when price < 0
                        then 'price must be greater than or equal to 0'
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

create or replace procedure stg.load_segments_from_raw(p_batch_id bigint default null)
language plpgsql
as $$
declare
    v_batch_id bigint;
    v_step_started_at timestamptz;
begin
    v_batch_id := stg.get_segments_batch_id(p_batch_id);

    v_step_started_at := clock_timestamp();

    truncate table stg.segments;

    raise notice 'truncate table stg.segments duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call stg.insert_segments_from_raw(v_batch_id);

    raise notice 'stg.insert_segments_from_raw duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call stg.validate_segments();

    raise notice 'stg.validate_segments duration: %',
        clock_timestamp() - v_step_started_at;


    raise notice 'stg.segments loaded. batch_id = %, rows = %, invalid rows = %',
        v_batch_id,
        (select count(*) from stg.segments),
        (select count(*) from stg.segments where is_valid = false);
end;
$$;