--------------------------------------------------------------------------------------------------------
-- Создание процедур слоя DDS: загрузка SCD2-измерения аэропортов из ODS в DDS --
--------------------------------------------------------------------------------------------------------


-- Процедура закрытия текущих версий, если данные изменились

create or replace procedure dds.close_changed_dim_airports(p_effective_at timestamptz)
language plpgsql
as $$
begin
    update dds.dim_airports d
    set
        valid_to = p_effective_at,
        is_current = false,
        batch_id = o.updated_batch_id
    from ods.airports o
    where d.airport_code = o.airport_code
      and d.is_current = true
      and (
             o.is_deleted = true
          or coalesce(d.airport_name_en, '') != coalesce(o.airport_name_en, '')
          or coalesce(d.airport_name_ru, '') != coalesce(o.airport_name_ru, '')
          or coalesce(d.city_en, '') != coalesce(o.city_en, '')
          or coalesce(d.city_ru, '') != coalesce(o.city_ru, '')
          or coalesce(d.country_en, '') != coalesce(o.country_en, '')
          or coalesce(d.country_ru, '') != coalesce(o.country_ru, '')
          or coalesce(d.coordinates::text, '') != coalesce(o.coordinates::text, '')
          or coalesce(d.timezone, '') != coalesce(o.timezone, '')
      );
end;
$$;


-- Процедура вставки новых текущих версий

create or replace procedure dds.insert_new_dim_airports(p_effective_at timestamptz)
language plpgsql
as $$
begin
    insert into dds.dim_airports (
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
        valid_from,
        batch_id
    )
    select
        o.airport_code,
        o.airport_name_en,
        o.airport_name_ru,
        o.city_en,
        o.city_ru,
        o.country_en,
        o.country_ru,
        o.coordinates,
        o.timezone,
        o.source_system,
        o.record_source,
        p_effective_at as valid_from,
        o.updated_batch_id as batch_id
    from ods.airports o
    left join dds.dim_airports d
        on d.airport_code = o.airport_code
       and d.is_current = true
    where o.is_deleted = false
      and d.airport_sk is null;
end;
$$;


-- Главная сборочная процедура

create or replace procedure dds.load_dim_airports_from_ods()
language plpgsql
as $$
declare
    v_effective_at timestamptz := now();
    v_step_started_at timestamptz;
begin
    v_step_started_at := clock_timestamp();

    call dds.close_changed_dim_airports(v_effective_at);

    raise notice 'dds.close_changed_dim_airports duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call dds.insert_new_dim_airports(v_effective_at);

    raise notice 'dds.insert_new_dim_airports duration: %',
        clock_timestamp() - v_step_started_at;


    raise notice 'dds.dim_airports loaded. rows = %, current rows = %, historical rows = %',
        (select count(*) from dds.dim_airports),
        (select count(*) from dds.dim_airports where is_current = true),
        (select count(*) from dds.dim_airports where is_current = false);
end;
$$;