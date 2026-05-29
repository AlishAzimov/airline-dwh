------------------------------------------------------------------------------------------------------
-- Создание процедур слоя STAGE: загрузка, очистка и валидация данных из RAW перед передачей в ODS --
------------------------------------------------------------------------------------------------------


-- Функция определения batch_id

create or replace function stg.get_boarding_passes_batch_id(p_batch_id bigint default null)
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
        from raw.boarding_passes;
    end if;

    if v_batch_id is null then
        raise exception 'No batch_id found in raw.boarding_passes';
    end if;

    return v_batch_id;
end;
$$;


-- Процедура загрузки из RAW в STAGE

create or replace procedure stg.insert_boarding_passes_from_raw(p_batch_id bigint)
language plpgsql
as $$
begin
    if p_batch_id is null then
        raise exception 'p_batch_id cannot be null in stg.insert_boarding_passes_from_raw';
    end if;

    insert into stg.boarding_passes (
        ticket_no,
        flight_id,
        seat_no,
        boarding_no,
        boarding_time,
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
        nullif(trim(r.seat_no), '') as seat_no,
        r.boarding_no,
        r.boarding_time,
        r.load_date as raw_load_date,
        now() as stg_load_date,
        r.source_system,
        r.record_source,
        r.batch_id,
        r.operation_type
    from raw.boarding_passes r
    where r.batch_id = p_batch_id;
end;
$$;


-- Процедура проверки качества данных

create or replace procedure stg.validate_boarding_passes()
language plpgsql
as $$
begin
    update stg.boarding_passes
    set
        is_valid =
            case
                when ticket_no is null then false
                when trim(ticket_no) = '' then false
                when flight_id is null then false
                when seat_no is null then false
                when trim(seat_no) = '' then false
                when operation_type not in ('I', 'U', 'D') then false
                when boarding_no is not null and boarding_no <= 0 then false
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
                        when seat_no is null or trim(seat_no) = ''
                        then 'seat_no is empty'
                    end,
                    case
                        when operation_type not in ('I', 'U', 'D')
                        then 'operation_type is invalid'
                    end,
                    case
                        when boarding_no is not null and boarding_no <= 0
                        then 'boarding_no must be greater than 0'
                    end
                ),
                ''
            );
end;
$$;


-- Главная сборочная процедура

create or replace procedure stg.load_boarding_passes_from_raw(p_batch_id bigint default null)
language plpgsql
as $$
declare
    v_batch_id bigint;
    v_step_started_at timestamptz;
begin
    v_batch_id := stg.get_boarding_passes_batch_id(p_batch_id);

    v_step_started_at := clock_timestamp();

    truncate table stg.boarding_passes;

    raise notice 'truncate table stg.boarding_passes duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call stg.insert_boarding_passes_from_raw(v_batch_id);

    raise notice 'stg.insert_boarding_passes_from_raw duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call stg.validate_boarding_passes();

    raise notice 'stg.validate_boarding_passes duration: %',
        clock_timestamp() - v_step_started_at;


    raise notice 'stg.boarding_passes loaded. batch_id = %, rows = %, invalid rows = %',
        v_batch_id,
        (select count(*) from stg.boarding_passes),
        (select count(*) from stg.boarding_passes where is_valid = false);
end;
$$;