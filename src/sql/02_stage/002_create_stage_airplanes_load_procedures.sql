------------------------------------------------------------------------------------------------------
-- Создание процедур слоя STAGE: загрузка, очистка и валидация данных из RAW перед передачей в ODS --
------------------------------------------------------------------------------------------------------


-- Функция определения batch_id

create or replace function stg.get_airplanes_batch_id(p_batch_id bigint default null)
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
        from raw.airplanes_data;
    end if;

    if v_batch_id is null then
        raise exception 'No batch_id found in raw.airplanes_data';
    end if;

    return v_batch_id;
end;
$$;


-- Процедура загрузки из RAW в STAGE

create or replace procedure stg.insert_airplanes_from_raw(p_batch_id bigint)
language plpgsql
as $$
begin
    if p_batch_id is null then
        raise exception 'p_batch_id cannot be null in stg.insert_airplanes_from_raw';
    end if;

    insert into stg.airplanes (
        airplane_code,
        model_en,
        model_ru,
        "range",
        speed,
        raw_load_date,
        stg_load_date,
        source_system,
        record_source,
        batch_id,
        operation_type
    )
    select
        upper(trim(r.airplane_code::text)) as airplane_code,
        nullif(trim(r.model ->> 'en'), '') as model_en,
        nullif(trim(r.model ->> 'ru'), '') as model_ru,
        r."range",
        r.speed,
        r.load_date as raw_load_date,
        now() as stg_load_date,
        r.source_system,
        r.record_source,
        r.batch_id,
        r.operation_type
    from raw.airplanes_data r
    where r.batch_id = p_batch_id;
end;
$$;


-- Процедура проверки качества данных

create or replace procedure stg.validate_airplanes()
language plpgsql
as $$
begin
    update stg.airplanes
    set
        is_valid =
            case
                when airplane_code is null then false
                when trim(airplane_code) = '' then false
                when operation_type not in ('I', 'U', 'D') then false
                when model_en is null then false
                when model_ru is null then false
                when ("range" is null or "range" <= 0) then false
                when (speed is null or speed <= 0) then false
                else true
            end,

        validation_error =
            nullif(
                concat_ws(
                    '; ',
                    case
                        when airplane_code is null or trim(airplane_code) = ''
                        then 'airplane_code is empty'
                    end,
                    case
                        when operation_type not in ('I', 'U', 'D')
                        then 'operation_type is invalid'
                    end,
                    case
                        when model_en is null
                        then 'model_en is null'
                    end,
                    case
                        when model_ru is null
                        then 'model_ru is null'
                    end,
                    case
                        when ("range" is null or "range" <= 0)
                        then 'range must be greater than 0'
                    end,
                    case
                        when (speed is null or speed <= 0)
                        then 'speed must be greater than 0'
                    end
                ),
                ''
            );
end;
$$;


-- Главная сборочная процедура

create or replace procedure stg.load_airplanes_from_raw(p_batch_id bigint default null)
language plpgsql
as $$
declare
    v_batch_id bigint;
    v_step_started_at timestamptz;
begin
    v_batch_id := stg.get_airplanes_batch_id(p_batch_id);

    v_step_started_at := clock_timestamp();

    truncate table stg.airplanes;

    raise notice 'truncate table stg.airplanes duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call stg.insert_airplanes_from_raw(v_batch_id);

    raise notice 'stg.insert_airplanes_from_raw duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call stg.validate_airplanes();

    raise notice 'stg.validate_airplanes duration: %',
        clock_timestamp() - v_step_started_at;


    raise notice 'stg.airplanes loaded. batch_id = %, rows = %, invalid rows = %',
        v_batch_id,
        (select count(*) from stg.airplanes),
        (select count(*) from stg.airplanes where is_valid = false);
end;
$$;