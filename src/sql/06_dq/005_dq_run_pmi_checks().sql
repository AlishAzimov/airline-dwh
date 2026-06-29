--------------------------------------------------------------------------------------------------------
-- Главная сборочная процедура слоя DQ: запуск полного PMI pipeline по всем проверяемым объектам --
--------------------------------------------------------------------------------------------------------

create or replace procedure dq.run_pmi_checks()
language plpgsql
as $$
declare
    v_run_id bigint;
    v_step_started_at timestamptz;
    v_pipeline_started_at timestamptz;
begin
    v_pipeline_started_at := clock_timestamp();

    -- Создаём единый run_id для всего PMI-прогона
    v_run_id := nextval('dq.pmi_run_seq');

    raise notice 'PMI pipeline started. run_id = %', v_run_id;


    ----------------------------------------------------------------------------------------------------
    -- Блок 1: PMI-проверки по dim_airplanes
    ----------------------------------------------------------------------------------------------------

    v_step_started_at := clock_timestamp();

    call dq.run_airplanes_pmi_checks(v_run_id);

    raise notice 'dq.run_airplanes_pmi_checks duration: %',
        clock_timestamp() - v_step_started_at;


    ----------------------------------------------------------------------------------------------------
    -- Блок 2: PMI-проверки по dim_seats
    ----------------------------------------------------------------------------------------------------

    v_step_started_at := clock_timestamp();

    call dq.run_seats_pmi_checks(v_run_id);

    raise notice 'dq.run_seats_pmi_checks duration: %',
        clock_timestamp() - v_step_started_at;


    ----------------------------------------------------------------------------------------------------
    -- Блок 3: PMI-проверки по fact_bookings
    ----------------------------------------------------------------------------------------------------

    v_step_started_at := clock_timestamp();

    call dq.run_bookings_pmi_checks(v_run_id);

    raise notice 'dq.run_bookings_pmi_checks duration: %',
        clock_timestamp() - v_step_started_at;


    ----------------------------------------------------------------------------------------------------
    -- Итог по всему PMI-прогону
    ----------------------------------------------------------------------------------------------------

    raise notice 'PMI pipeline completed. run_id = %, total checks = %, passed = %, failed = %, warnings = %, duration = %',
        v_run_id,
        (select count(*) from dq.pmi_results where run_id = v_run_id),
        (select count(*) from dq.pmi_results where run_id = v_run_id and status = 'PASS'),
        (select count(*) from dq.pmi_results where run_id = v_run_id and status = 'FAIL'),
        (select count(*) from dq.pmi_results where run_id = v_run_id and status = 'WARN'),
        clock_timestamp() - v_pipeline_started_at;
end;
$$;