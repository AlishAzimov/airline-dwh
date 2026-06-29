
--------------------------------------------------------------------------------------------------------
-- Создание процедур слоя DDS: загрузка SCD2-измерения самолётов из ODS в DDS --
--------------------------------------------------------------------------------------------------------


-- Процедура закрытия текущих версий, если данные изменились

create or replace procedure dds.close_changed_dim_airplanes(p_effective_at timestamptz)
language plpgsql
as $$
begin
    update dds.dim_airplanes d
    set
       	valid_to = p_effective_at,
        is_current = false,
		batch_id= o.updated_batch_id
    from ods.airplanes o
    where d.airplane_code = o.airplane_code
      and d.is_current = true
      and (
			o.is_deleted = true
          or coalesce(d.model_en, '') != coalesce(o.model_en, '')
          or coalesce(d.model_ru, '') != coalesce(o.model_ru, '')
          or coalesce(d."range", -1) != coalesce(o."range", -1)
          or coalesce(d.speed, -1) != coalesce(o.speed, -1)
      );
end;
$$;




-- Процедура вставки новых текущих версий

create or replace procedure dds.insert_new_dim_airplanes(p_effective_at timestamptz)
language plpgsql
as $$
begin
    insert into dds.dim_airplanes (
		airplane_sk,
        airplane_code,
        model_en,
        model_ru,
        "range",
        speed,
        source_system,
        record_source,
		valid_from,
        batch_id
    )
    select
		md5(o.airplane_code || '|' || to_char(p_effective_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US'))::uuid,
        o.airplane_code,
        o.model_en,
        o.model_ru,
        o."range",
        o.speed,
        o.source_system,
        o.record_source,
		p_effective_at as valid_from,
        o.updated_batch_id as batch_id
    from ods.airplanes o
    left join dds.dim_airplanes d
        on d.airplane_code = o.airplane_code
       and d.is_current = true
    where o.is_deleted = false
      and d.airplane_sk is null;
end;
$$;



-- Главная сборочная процедура

create or replace procedure dds.load_dim_airplanes_from_ods()
language plpgsql
as $$
declare
	v_effective_at timestamptz := now();
    v_step_started_at timestamptz;
begin
    v_step_started_at := clock_timestamp();

    call dds.close_changed_dim_airplanes(v_effective_at);

    raise notice 'dds.close_changed_dim_airplanes duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call dds.insert_new_dim_airplanes(v_effective_at);

    raise notice 'dds.insert_new_dim_airplanes duration: %',
        clock_timestamp() - v_step_started_at;


    raise notice 'dds.dim_airplanes loaded. rows = %, current rows = %, historical rows = %',
        (select count(*) from dds.dim_airplanes),
        (select count(*) from dds.dim_airplanes where is_current = true),
        (select count(*) from dds.dim_airplanes where is_current = false);
end;
$$;



