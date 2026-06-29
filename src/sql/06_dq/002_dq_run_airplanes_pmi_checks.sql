--------------------------------------------------------------------------------------------------------
-- Создание процедур слоя DQ: PMI-проверки качества данных по измерению самолётов dim_airplanes --
--------------------------------------------------------------------------------------------------------


-- RC-01: Проверка количества самолётов на стыке SOURCE -> RAW


create or replace procedure dq.run_rc_01_dim_airplanes_source_to_raw(p_run_id bigint)
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
        select count(distinct airplane_code) as cnt
        from source_fdw.airplanes_data
    ),
    raw_last as (
        select distinct on (airplane_code)
            airplane_code,
            operation_type
        from raw.airplanes_data
        order by airplane_code, batch_id desc, load_date desc
    ),
    raw_actual as (
        select count(distinct airplane_code) as cnt
        from raw_last
        where operation_type <> 'D'
    )
    select
        'RC-01' as check_id,
        'row_count' as check_type,
        'source' as layer_from,
        'raw' as layer_to,
        'dim_airplanes' as object_name,
        'Source FDW airplanes vs RAW actual airplanes: live-FDW check, assumes source is stable during PMI' as description,
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


-- RC-02: Проверка количества самолётов на стыке RAW -> ODS

create or replace procedure dq.run_rc_02_dim_airplanes_raw_to_ods(p_run_id bigint)
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
        select distinct on (airplane_code)
            airplane_code,
            operation_type
        from raw.airplanes_data
        order by airplane_code, batch_id desc, load_date desc
    ),
    raw_actual as (
        select count(distinct airplane_code) as cnt
        from raw_last
        where operation_type <> 'D'
    ),
    ods_actual as (
        select count(distinct airplane_code) as cnt
        from ods.airplanes
        where is_deleted = false
    )
    select
        'RC-02' as check_id,
        'row_count' as check_type,
        'raw' as layer_from,
        'ods' as layer_to,
        'dim_airplanes' as object_name,
        'RAW actual airplanes vs ODS active airplanes: checks that ODS correctly collapsed RAW I/U/D journal' as description,
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



-- RC-03: Проверка количества самолётов на стыке ODS -> DDS

create or replace procedure dq.run_rc_03_dim_airplanes_ods_to_dds(p_run_id bigint)
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
        select count(distinct airplane_code) as cnt
        from ods.airplanes
        where is_deleted = false
    ),
    dds_current as (
        select count(distinct airplane_code) as cnt
        from dds.dim_airplanes
        where is_current = true
          and airplane_code <> '-1'
    )
    select
        'RC-03' as check_id,
        'row_count' as check_type,
        'ods' as layer_from,
        'dds' as layer_to,
        'dim_airplanes' as object_name,
        'ODS active airplanes vs DDS current airplane versions: checks SCD2 current slice completeness' as description,
        ods_actual.cnt as src_value,
        dds_current.cnt as dwh_value,
        ods_actual.cnt - dds_current.cnt as diff,
        case
            when ods_actual.cnt = dds_current.cnt then 'PASS'
            else 'FAIL'
        end as status,
        p_run_id as run_id
    from ods_actual, dds_current;
end;
$$;



-- SCD2-01: Проверка отсутствия нескольких текущих версий по одному airplane_code--

create or replace procedure dq.run_scd2_01_dim_airplanes_one_current_version(p_run_id bigint)
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
            select airplane_code
            from dds.dim_airplanes
            where is_current = true
              and airplane_code <> '-1'
            group by airplane_code
            having count(*) > 1
        ) t
    )
    select
        'SCD2-01' as check_id,
        'scd2' as check_type,
        'dds' as layer_from,
        'dds' as layer_to,
        'dim_airplanes' as object_name,
        'DDS dim_airplanes SCD2 check: no more than one current version per airplane_code' as description,
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



-- SCD2-02: Проверка отсутствия пересечений периодов действия SCD2-версий

create or replace procedure dq.run_scd2_02_dim_airplanes_no_period_overlap(p_run_id bigint)
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
    with version_periods as (
        select
            airplane_code,
            valid_from,
            valid_to,
            lag(valid_to) over (
                partition by airplane_code
                order by valid_from, valid_to
            ) as prev_valid_to
        from dds.dim_airplanes
        where airplane_code <> '-1'
    ),
    violations as (
        select count(*) as cnt
        from version_periods
        where prev_valid_to is not null
          and prev_valid_to > valid_from
    )
    select
        'SCD2-02' as check_id,
        'scd2' as check_type,
        'dds' as layer_from,
        'dds' as layer_to,
        'dim_airplanes' as object_name,
        'DDS dim_airplanes SCD2 check: no overlapping validity periods by airplane_code' as description,
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


-- SCD2-03: Проверка наличия разрывов между периодами действия SCD2-версий

create or replace procedure dq.run_scd2_03_dim_airplanes_period_gaps(p_run_id bigint)
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
    with version_periods as (
        select
            airplane_code,
            valid_from,
            valid_to,
            lag(valid_to) over (
                partition by airplane_code
                order by valid_from, valid_to
            ) as prev_valid_to
        from dds.dim_airplanes
        where airplane_code <> '-1'
    ),
    violations as (
        select count(*) as cnt
        from version_periods
        where prev_valid_to is not null
          and prev_valid_to < valid_from
    )
    select
        'SCD2-03' as check_id,
        'scd2' as check_type,
        'dds' as layer_from,
        'dds' as layer_to,
        'dim_airplanes' as object_name,
        'DDS dim_airplanes SCD2 warning: validity period gaps between versions by airplane_code' as description,
        0 as src_value,
        violations.cnt as dwh_value,
        0 - violations.cnt as diff,
        case
            when violations.cnt = 0 then 'PASS'
            else 'WARN'
        end as status,
        p_run_id as run_id
    from violations;
end;
$$;

--------------------------------------------------------------------------------------------------------
-- Главная сборочная процедура PMI по dim_airplanes
--------------------------------------------------------------------------------------------------------

create or replace procedure dq.run_airplanes_pmi_checks(p_run_id bigint)
language plpgsql
as $$
declare
    v_step_started_at timestamptz;
begin
    v_step_started_at := clock_timestamp();

    call dq.run_rc_01_dim_airplanes_source_to_raw(p_run_id);

    raise notice 'dq.run_rc_01_dim_airplanes_source_to_raw duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call dq.run_rc_02_dim_airplanes_raw_to_ods(p_run_id);

    raise notice 'dq.run_rc_02_dim_airplanes_raw_to_ods duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call dq.run_rc_03_dim_airplanes_ods_to_dds(p_run_id);

    raise notice 'dq.run_rc_03_dim_airplanes_ods_to_dds duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call dq.run_scd2_01_dim_airplanes_one_current_version(p_run_id);

    raise notice 'dq.run_scd2_01_dim_airplanes_one_current_version duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call dq.run_scd2_02_dim_airplanes_no_period_overlap(p_run_id);

    raise notice 'dq.run_scd2_02_dim_airplanes_no_period_overlap duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call dq.run_scd2_03_dim_airplanes_period_gaps(p_run_id);

    raise notice 'dq.run_scd2_03_dim_airplanes_period_gaps duration: %',
        clock_timestamp() - v_step_started_at;


    raise notice 'PMI dim_airplanes checks completed. run_id = %, total = %, passed = %, failed = %, warnings = %',
        p_run_id,
        (select count(*) from dq.pmi_results where run_id = p_run_id and object_name = 'dim_airplanes'),
        (select count(*) from dq.pmi_results where run_id = p_run_id and object_name = 'dim_airplanes' and status = 'PASS'),
        (select count(*) from dq.pmi_results where run_id = p_run_id and object_name = 'dim_airplanes' and status = 'FAIL'),
        (select count(*) from dq.pmi_results where run_id = p_run_id and object_name = 'dim_airplanes' and status = 'WARN');
end;
$$;