
--------------------------------------------------------------------------------------------------------
-- Создание процедур слоя ODS: применение данных из STAGE и поддержание актуального состояния таблиц --
--------------------------------------------------------------------------------------------------------


-- Процедура I/U

create or replace procedure ods.upsert_airports_from_stage()
language plpgsql
as $$
begin
    insert into ods.airports (
        airport_code,
        airport_name_en,
        airport_name_ru,
        city_en,
        city_ru,
        country_en,
        country_ru,
        coordinates,
        timezone,
        source_system,
        record_source,
        created_batch_id,
        updated_batch_id,
        last_changed_at,
        is_deleted,
        last_operation_type
    )
    select
        s.airport_code,
        s.airport_name_en,
        s.airport_name_ru,
        s.city_en,
        s.city_ru,
        s.country_en,
        s.country_ru,
        s.coordinates,
        s.timezone,
        s.source_system,
        s.record_source,
        s.batch_id as created_batch_id,
        s.batch_id as updated_batch_id,
        now() as last_changed_at,
        false as is_deleted,
        s.operation_type as last_operation_type
    from stg.airports s
    where s.is_valid = true
      and s.operation_type in ('I', 'U')
    on conflict (airport_code) do update
    set
        airport_name_en = excluded.airport_name_en,
        airport_name_ru = excluded.airport_name_ru,
        city_en = excluded.city_en,
        city_ru = excluded.city_ru,
        country_en = excluded.country_en,
        country_ru = excluded.country_ru,
        coordinates = excluded.coordinates,
        timezone = excluded.timezone,
        source_system = excluded.source_system,
        record_source = excluded.record_source,
        updated_batch_id = excluded.updated_batch_id,
        last_changed_at = now(),
        is_deleted = false,
        last_operation_type = excluded.last_operation_type;
end;
$$;


-- Процедура D

create or replace procedure ods.delete_airports_from_stage()
language plpgsql
as $$
begin
    update ods.airports o
    set
        updated_batch_id = s.batch_id,
        last_changed_at = now(),
        is_deleted = true,
        last_operation_type = s.operation_type
    from stg.airports s
    where o.airport_code = s.airport_code
      and s.is_valid = true
      and s.operation_type = 'D';
end;
$$;


-- Главная сборочная процедура

create or replace procedure ods.apply_airports_from_stage()
language plpgsql
as $$
declare 
    v_step_started_at timestamptz;
begin
    v_step_started_at := clock_timestamp();

    call ods.upsert_airports_from_stage();

    raise notice 'ods.upsert_airports_from_stage duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call ods.delete_airports_from_stage();

    raise notice 'ods.delete_airports_from_stage duration: %',
        clock_timestamp() - v_step_started_at;


    raise notice 'ods.airports applied. rows = %, active rows = %, deleted rows = %',
        (select count(*) from ods.airports),
        (select count(*) from ods.airports where is_deleted = false),
        (select count(*) from ods.airports where is_deleted = true);
end;
$$;

