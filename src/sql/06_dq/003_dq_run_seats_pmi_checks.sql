--------------------------------------------------------------------------------------------------------
-- Создание процедур слоя DQ: PMI-проверки качества данных по измерению мест dim_seats --
--------------------------------------------------------------------------------------------------------


-- RC-04: Проверка количества мест на стыке SOURCE -> RAW

create or replace procedure dq.run_rc_04_dim_seats_source_to_raw(p_run_id bigint)
language plpgsql
as $$
begin
    insert into dq.pmi_results (
        check_id,
        check_type,
        layer_from,
        layer_to,
        object_name,
        description,
        src_value,
        dwh_value,
        diff,
        status,
        run_id
    )
    with src as (
        select count(distinct (airplane_code, seat_no)) as cnt
        from source_fdw.seats
    ),
    raw_last as (
        select distinct on (airplane_code, seat_no)
            airplane_code,
            seat_no,
            operation_type
        from raw.seats
        order by airplane_code, seat_no, batch_id desc, load_date desc
    ),
    raw_actual as (
        select count(distinct (airplane_code, seat_no)) as cnt
        from raw_last
        where operation_type <> 'D'
    )
    select
        'RC-04' as check_id,
        'row_count' as check_type,
        'source' as layer_from,
        'raw' as layer_to,
        'dim_seats' as object_name,
        'Source FDW seats vs RAW actual seats: live-FDW check, assumes source is stable during PMI' as description,
        src.cnt as src_value,
        raw_actual.cnt as dwh_value,
        src.cnt - raw_actual.cnt as diff,
        case
            when src.cnt = raw_actual.cnt then 'PASS'
            else 'FAIL'
        end as status,
        p_run_id as run_id
    from src, raw_actual;
end;
$$;


-- RC-05: Проверка количества мест на стыке RAW -> ODS

create or replace procedure dq.run_rc_05_dim_seats_raw_to_ods(p_run_id bigint)
language plpgsql
as $$
begin
    insert into dq.pmi_results (
        check_id,
        check_type,
        layer_from,
        layer_to,
        object_name,
        description,
        src_value,
        dwh_value,
        diff,
        status,
        run_id
    )
    with raw_last as (
        select distinct on (airplane_code, seat_no)
            airplane_code,
            seat_no,
            operation_type
        from raw.seats
        order by airplane_code, seat_no, batch_id desc, load_date desc
    ),
    raw_actual as (
        select count(distinct (airplane_code, seat_no)) as cnt
        from raw_last
        where operation_type <> 'D'
    ),
    ods_actual as (
        select count(distinct (airplane_code, seat_no)) as cnt
        from ods.seats
        where is_deleted = false
    )
    select
        'RC-05' as check_id,
        'row_count' as check_type,
        'raw' as layer_from,
        'ods' as layer_to,
        'dim_seats' as object_name,
        'RAW actual seats vs ODS active seats: checks that ODS correctly collapsed RAW I/U/D journal' as description,
        raw_actual.cnt as src_value,
        ods_actual.cnt as dwh_value,
        raw_actual.cnt - ods_actual.cnt as diff,
        case
            when raw_actual.cnt = ods_actual.cnt then 'PASS'
            else 'FAIL'
        end as status,
        p_run_id as run_id
    from raw_actual, ods_actual;
end;
$$;


-- RC-06: Проверка количества мест на стыке ODS -> DDS

create or replace procedure dq.run_rc_06_dim_seats_ods_to_dds(p_run_id bigint)
language plpgsql
as $$
begin
    insert into dq.pmi_results (
        check_id,
        check_type,
        layer_from,
        layer_to,
        object_name,
        description,
        src_value,
        dwh_value,
        diff,
        status,
        run_id
    )
    with ods_actual as (
        select count(distinct (airplane_code, seat_no)) as cnt
        from ods.seats
        where is_deleted = false
    ),
    dds_actual as (
        select count(distinct (airplane_code, seat_no)) as cnt
        from dds.dim_seats
        where is_deleted = false
          and not (
              coalesce(airplane_code, '') = '-1'
              and coalesce(seat_no, '') = '-1'
          )
    )
    select
        'RC-06' as check_id,
        'row_count' as check_type,
        'ods' as layer_from,
        'dds' as layer_to,
        'dim_seats' as object_name,
        'ODS active seats vs DDS active seats: checks SCD1 dimension completeness by airplane_code and seat_no, excluding technical stub row' as description,
        ods_actual.cnt as src_value,
        dds_actual.cnt as dwh_value,
        ods_actual.cnt - dds_actual.cnt as diff,
        case
            when ods_actual.cnt = dds_actual.cnt then 'PASS'
            else 'FAIL'
        end as status,
        p_run_id as run_id
    from ods_actual, dds_actual;
end;
$$;


-- DUP-01: Проверка отсутствия дублей в DDS dim_seats по бизнес-ключу

create or replace procedure dq.run_dup_01_dim_seats_no_duplicates(p_run_id bigint)
language plpgsql
as $$
begin
    insert into dq.pmi_results (
        check_id,
        check_type,
        layer_from,
        layer_to,
        object_name,
        description,
        src_value,
        dwh_value,
        diff,
        status,
        run_id
    )
    with violations as (
        select count(*) as cnt
        from (
            select
                airplane_code,
                seat_no
            from dds.dim_seats
            where is_deleted = false
              and not (
                  coalesce(airplane_code, '') = '-1'
                  and coalesce(seat_no, '') = '-1'
              )
            group by airplane_code, seat_no
            having count(*) > 1
                or airplane_code is null
                or seat_no is null
        ) t
    )
    select
        'DUP-01' as check_id,
        'duplicate' as check_type,
        'dds' as layer_from,
        'dds' as layer_to,
        'dim_seats' as object_name,
        'DDS dim_seats duplicate/key check: no duplicates and no null business keys by airplane_code and seat_no for active records' as description,
        0 as src_value,
        violations.cnt as dwh_value,
        0 - violations.cnt as diff,
        case
            when violations.cnt = 0 then 'PASS'
            else 'FAIL'
        end as status,
        p_run_id as run_id
    from violations;
end;
$$;


--------------------------------------------------------------------------------------------------------
-- Главная сборочная процедура PMI по dim_seats
--------------------------------------------------------------------------------------------------------

create or replace procedure dq.run_seats_pmi_checks(p_run_id bigint)
language plpgsql
as $$
declare
    v_step_started_at timestamptz;
begin
    v_step_started_at := clock_timestamp();

    call dq.run_rc_04_dim_seats_source_to_raw(p_run_id);

    raise notice 'dq.run_rc_04_dim_seats_source_to_raw duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call dq.run_rc_05_dim_seats_raw_to_ods(p_run_id);

    raise notice 'dq.run_rc_05_dim_seats_raw_to_ods duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call dq.run_rc_06_dim_seats_ods_to_dds(p_run_id);

    raise notice 'dq.run_rc_06_dim_seats_ods_to_dds duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call dq.run_dup_01_dim_seats_no_duplicates(p_run_id);

    raise notice 'dq.run_dup_01_dim_seats_no_duplicates duration: %',
        clock_timestamp() - v_step_started_at;


    raise notice 'PMI dim_seats checks completed. run_id = %, total = %, passed = %, failed = %, warnings = %',
        p_run_id,
        (select count(*) from dq.pmi_results where run_id = p_run_id and object_name = 'dim_seats'),
        (select count(*) from dq.pmi_results where run_id = p_run_id and object_name = 'dim_seats' and status = 'PASS'),
        (select count(*) from dq.pmi_results where run_id = p_run_id and object_name = 'dim_seats' and status = 'FAIL'),
        (select count(*) from dq.pmi_results where run_id = p_run_id and object_name = 'dim_seats' and status = 'WARN');
end;
$$;