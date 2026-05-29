------------------------------------------------------------------------------------------------------
-- Создание процедур слоя STAGE: загрузка, очистка и валидация данных из RAW перед передачей в ODS --
------------------------------------------------------------------------------------------------------


-- Функция определения batch_id

create or replace function stg.get_airports_batch_id(p_batch_id bigint default null)
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
        from raw.airports_data;
    end if;

    if v_batch_id is null then
        raise exception 'No batch_id found in raw.airplanes_data';
    end if;

    return v_batch_id;
end;
$$;


-- Процедура загрузки из RAW в STAGE

create or replace procedure stg.insert_airports_from_raw(p_batch_id bigint)
language plpgsql
as $$
begin
    if p_batch_id is null then
        raise exception 'p_batch_id cannot be null in stg.insert_airports_data_from_raw';
    end if;

    insert into stg.airports (
        airport_code,
        airport_name_en,
        airport_name_ru,
        city_en,
        city_ru,
        country_en,
        country_ru,
        coordinates,
        timezone,
        raw_load_date,
        stg_load_date,
        source_system,
        record_source,
        batch_id,
        operation_type
    )
    select
        upper(trim(r.airport_code::text)) as airport_code,
        nullif(trim(r.airport_name ->> 'en'), '') as airport_name_en,
        nullif(trim(r.airport_name ->> 'ru'), '') as airport_name_ru,
        nullif(trim(r.city ->> 'en'), '') as city_en,
        nullif(trim(r.city ->> 'ru'), '') as city_ru,
        nullif(trim(r.country ->> 'en'), '') as country_en,
        nullif(trim(r.country ->> 'ru'), '') as country_ru,
        r.coordinates,
        nullif(trim(r.timezone), '') as timezone,
        r.load_date as raw_load_date,
        now() as stg_load_date,
        r.source_system,
        r.record_source,
        r.batch_id,
        r.operation_type
    from raw.airports_data r
    where r.batch_id = p_batch_id;
end;
$$;


-- Процедура проверки качества данных

create or replace procedure stg.validate_airports()
language plpgsql
as $$
begin
    update stg.airports
    set
        is_valid =
            case
                when airport_code is null then false
                when trim(airport_code) = '' then false
                when operation_type not in ('I', 'U', 'D') then false
                when airport_name_en is null then false
                when airport_name_ru is null then false
                when city_en is null then false
                when city_ru is null then false
                when country_en is null then false
                when country_ru is null then false
                when coordinates is null then false
                when timezone is null then false
                when trim(timezone) = '' then false
                else true
            end,

        validation_error =
            nullif(
                concat_ws(
                    '; ',
                    case
                        when airport_code is null or trim(airport_code) = ''
                        then 'airport_code is empty'
                    end,
                    case
                        when operation_type not in ('I', 'U', 'D')
                        then 'operation_type is invalid'
                    end,
                    case
                        when airport_name_en is null
                        then 'airport_name_en is null'
                    end,
                    case
                        when airport_name_ru is null
                        then 'airport_name_ru is null'
                    end,
                    case
                        when city_en is null
                        then 'city_en is null'
                    end,
                    case
                        when city_ru is null
                        then 'city_ru is null'
                    end,
                    case
                        when country_en is null
                        then 'country_en is null'
                    end,
                    case
                        when country_ru is null
                        then 'country_ru is null'
                    end,
                    case
                        when coordinates is null
                        then 'coordinates is null'
                    end,
                    case
                        when timezone is null or trim(timezone) = ''
                        then 'timezone is empty'
                    end
                ),
                ''
            );
end;
$$;


-- Главная сборочная процедура

create or replace procedure stg.load_airports_from_raw(p_batch_id bigint default null)
language plpgsql
as $$
declare
    v_batch_id bigint;
    v_step_started_at timestamptz;
begin
    v_batch_id := stg.get_airports_batch_id(p_batch_id);

    v_step_started_at := clock_timestamp();

    truncate table stg.airports;

    raise notice 'truncate table stg.airports duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call stg.insert_airports_from_raw(v_batch_id);

    raise notice 'stg.insert_airports_from_raw duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call stg.validate_airports();

    raise notice 'stg.validate_airports duration: %',
        clock_timestamp() - v_step_started_at;


    raise notice 'stg.airports_data loaded. batch_id = %, rows = %, invalid rows = %',
        v_batch_id,
        (select count(*) from stg.airports),
        (select count(*) from stg.airports where is_valid = false);
end;
$$;