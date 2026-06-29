--------------------------------------------------------------------------------------------------------
-- Создание процедур слоя DQ: PMI-проверки качества данных по факту бронирований fact_bookings --
--------------------------------------------------------------------------------------------------------


-- RC-07: Проверка количества бронирований на стыке SOURCE -> RAW

create or replace procedure dq.run_rc_07_fact_bookings_source_to_raw(p_run_id bigint)
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
        select count(distinct book_ref) as cnt
        from source_fdw.bookings
    ),
    raw_last as (
        select distinct on (book_ref)
            book_ref,
            operation_type
        from raw.bookings
        order by book_ref, batch_id desc, load_date desc
    ),
    raw_actual as (
        select count(distinct book_ref) as cnt
        from raw_last
        where operation_type <> 'D'
    )
    select
        'RC-07' as check_id,
        'row_count' as check_type,
        'source' as layer_from,
        'raw' as layer_to,
        'fact_bookings' as object_name,
        'Source FDW bookings vs RAW actual bookings: live-FDW check, assumes source is stable during PMI' as description,
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


-- RC-08: Проверка количества бронирований на стыке RAW -> ODS

create or replace procedure dq.run_rc_08_fact_bookings_raw_to_ods(p_run_id bigint)
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
        select distinct on (book_ref)
            book_ref,
            operation_type
        from raw.bookings
        order by book_ref, batch_id desc, load_date desc
    ),
    raw_actual as (
        select count(distinct book_ref) as cnt
        from raw_last
        where operation_type <> 'D'
    ),
    ods_actual as (
        select count(distinct book_ref) as cnt
        from ods.bookings
        where is_deleted = false
    )
    select
        'RC-08' as check_id,
        'row_count' as check_type,
        'raw' as layer_from,
        'ods' as layer_to,
        'fact_bookings' as object_name,
        'RAW actual bookings vs ODS active bookings: checks that ODS correctly collapsed RAW I/U/D journal' as description,
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


-- RC-09: Проверка количества бронирований на стыке ODS -> DDS

create or replace procedure dq.run_rc_09_fact_bookings_ods_to_dds(p_run_id bigint)
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
        select count(distinct book_ref) as cnt
        from ods.bookings
        where is_deleted = false
    ),
    dds_actual as (
        select count(distinct book_ref) as cnt
        from dds.fact_bookings
        where is_deleted = false
          and coalesce(book_ref, '') <> '-1'
    )
    select
        'RC-09' as check_id,
        'row_count' as check_type,
        'ods' as layer_from,
        'dds' as layer_to,
        'fact_bookings' as object_name,
        'ODS active bookings vs DDS active fact_bookings: checks fact completeness by book_ref, excluding technical stub row' as description,
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


-- DUP-02: Проверка отсутствия дублей в DDS fact_bookings по book_ref

create or replace procedure dq.run_dup_02_fact_bookings_no_duplicates(p_run_id bigint)
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
            select book_ref
            from dds.fact_bookings
            where is_deleted = false
              and coalesce(book_ref, '') <> '-1'
            group by book_ref
            having count(*) > 1
                or book_ref is null
        ) t
    )
    select
        'DUP-02' as check_id,
        'duplicate' as check_type,
        'dds' as layer_from,
        'dds' as layer_to,
        'fact_bookings' as object_name,
        'DDS fact_bookings duplicate/key check: no duplicates and no null book_ref for active records' as description,
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


-- AGG-01: Сверка суммы total_amount между ODS и DDS

create or replace procedure dq.run_agg_01_fact_bookings_total_amount(p_run_id bigint)
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
    with ods_sum as (
        select coalesce(sum(total_amount), 0) as total_amount_sum
        from ods.bookings
        where is_deleted = false
    ),
    dds_sum as (
        select coalesce(sum(total_amount), 0) as total_amount_sum
        from dds.fact_bookings
        where is_deleted = false
          and coalesce(book_ref, '') <> '-1'
    )
    select
        'AGG-01' as check_id,
        'aggregate' as check_type,
        'ods' as layer_from,
        'dds' as layer_to,
        'fact_bookings' as object_name,
        'ODS active bookings vs DDS active fact_bookings: total_amount sum reconciliation, excluding technical stub row' as description,
        ods_sum.total_amount_sum as src_value,
        dds_sum.total_amount_sum as dwh_value,
        ods_sum.total_amount_sum - dds_sum.total_amount_sum as diff,
        case
            when ods_sum.total_amount_sum = dds_sum.total_amount_sum then 'PASS'
            else 'FAIL'
        end as status,
        p_run_id as run_id
    from ods_sum, dds_sum;
end;
$$;


--------------------------------------------------------------------------------------------------------
-- Главная сборочная процедура PMI по fact_bookings
--------------------------------------------------------------------------------------------------------

create or replace procedure dq.run_bookings_pmi_checks(p_run_id bigint)
language plpgsql
as $$
declare
    v_step_started_at timestamptz;
begin
    v_step_started_at := clock_timestamp();

    call dq.run_rc_07_fact_bookings_source_to_raw(p_run_id);

    raise notice 'dq.run_rc_07_fact_bookings_source_to_raw duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call dq.run_rc_08_fact_bookings_raw_to_ods(p_run_id);

    raise notice 'dq.run_rc_08_fact_bookings_raw_to_ods duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call dq.run_rc_09_fact_bookings_ods_to_dds(p_run_id);

    raise notice 'dq.run_rc_09_fact_bookings_ods_to_dds duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call dq.run_dup_02_fact_bookings_no_duplicates(p_run_id);

    raise notice 'dq.run_dup_02_fact_bookings_no_duplicates duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call dq.run_agg_01_fact_bookings_total_amount(p_run_id);

    raise notice 'dq.run_agg_01_fact_bookings_total_amount duration: %',
        clock_timestamp() - v_step_started_at;


    raise notice 'PMI fact_bookings checks completed. run_id = %, total = %, passed = %, failed = %, warnings = %',
        p_run_id,
        (select count(*) from dq.pmi_results where run_id = p_run_id and object_name = 'fact_bookings'),
        (select count(*) from dq.pmi_results where run_id = p_run_id and object_name = 'fact_bookings' and status = 'PASS'),
        (select count(*) from dq.pmi_results where run_id = p_run_id and object_name = 'fact_bookings' and status = 'FAIL'),
        (select count(*) from dq.pmi_results where run_id = p_run_id and object_name = 'fact_bookings' and status = 'WARN');
end;
$$;