
--------------------------------------------------------------------------------------------------------
-- Создание процедур слоя ODS: применение данных из STAGE и поддержание актуального состояния таблиц --
--------------------------------------------------------------------------------------------------------


-- Процедура I/U:

create or replace procedure ods.upsert_airplanes_from_stage()
language plpgsql
as $$
begin
    insert into ods.airplanes (
        airplane_code,
        model_en,
        model_ru,
        "range",
        speed,
        source_system,
        record_source,
        created_batch_id,
        updated_batch_id,
        last_changed_at,
        is_deleted,
        last_operation_type
    )
    select
        s.airplane_code,
        s.model_en,
        s.model_ru,
        s."range",
        s.speed,
        s.source_system,
        s.record_source,
        s.batch_id as created_batch_id,
        s.batch_id as updated_batch_id,
        now() as last_changed_at,
        false as is_deleted,
        s.operation_type as last_operation_type
    from stg.airplanes s
    where s.is_valid = true
      and s.operation_type in ('I', 'U')
    on conflict (airplane_code) do update
    set
        model_en = excluded.model_en,
        model_ru = excluded.model_ru,
        "range" = excluded."range",
        speed = excluded.speed,
        source_system = excluded.source_system,
        record_source = excluded.record_source,
        updated_batch_id = excluded.updated_batch_id,
        last_changed_at = now(),
        is_deleted = false,
        last_operation_type = excluded.last_operation_type;
end;
$$;




-- Процедура D

create or replace procedure ods.delete_airplanes_from_stage()
language plpgsql
as $$
begin
    update ods.airplanes o
    set
        updated_batch_id = s.batch_id,
        last_changed_at = now(),
        is_deleted = true,
        last_operation_type = s.operation_type
    from stg.airplanes s
    where o.airplane_code = s.airplane_code
      and s.is_valid = true
      and s.operation_type = 'D';
end;
$$;


-- Главная сборочная процедура
create or replace procedure ods.apply_airplanes_from_stage()
language plpgsql
as $$
declare
    v_step_started_at timestamptz;
begin
    v_step_started_at := clock_timestamp();
    call ods.upsert_airplanes_from_stage();
    raise notice 'ods.upsert_airplanes_from_stage duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call ods.delete_airplanes_from_stage();
    raise notice 'ods.delete_airplanes_from_stage duration: %',
        clock_timestamp() - v_step_started_at;

    raise notice 'ods.airplanes applied. rows = %, active rows = %, deleted rows = %',
        (select count(*) from ods.airplanes),
        (select count(*) from ods.airplanes where is_deleted = false),
        (select count(*) from ods.airplanes where is_deleted = true);
end;
$$;



