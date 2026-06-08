--------------------------------------------------------------------------------------------------------
-- Создание процедур слоя DM: загрузка агрегированной витрины пассажиропотока аэропортов по дням --
--------------------------------------------------------------------------------------------------------


-- Процедура загрузки витрины: агрегирует вылеты и прилёты из dm.flight_sales_mart

create or replace procedure dm.insert_airport_traffic_daily_from_flight_sales_mart()
language plpgsql
as $$
begin

    insert into dm.airport_traffic_daily (
        traffic_date,
        airport_name,
        departures_count,
        arrivals_count,
        departure_passenger_count,
        arrival_passenger_count,
        total_passenger_count,
        departure_revenue,
        arrival_revenue,
        total_revenue
    )

    with airport_events as (

        -- Вылеты
        select
            coalesce(actual_departure, scheduled_departure)::date as traffic_date,
            departure_airport_name as airport_name,

            count(distinct flight_id) as departures_count,
            0::int4 as arrivals_count,

            count(distinct passenger_id) as departure_passenger_count,
            0::int4 as arrival_passenger_count,

            sum(price) as departure_revenue,
            0::numeric(10, 2) as arrival_revenue
        from dm.flight_sales_mart
        where departure_airport_name is not null
          and coalesce(actual_departure, scheduled_departure) is not null
        group by
            coalesce(actual_departure, scheduled_departure)::date,
            departure_airport_name

        union all

        -- Прилёты
        select
            coalesce(actual_arrival, scheduled_arrival)::date as traffic_date,
            arrival_airport_name as airport_name,

            0::int4 as departures_count,
            count(distinct flight_id) as arrivals_count,

            0::int4 as departure_passenger_count,
            count(distinct passenger_id) as arrival_passenger_count,

            0::numeric(10, 2) as departure_revenue,
            sum(price) as arrival_revenue
        from dm.flight_sales_mart
        where arrival_airport_name is not null
          and coalesce(actual_arrival, scheduled_arrival) is not null
        group by
            coalesce(actual_arrival, scheduled_arrival)::date,
            arrival_airport_name
    )

    select
        traffic_date,
        airport_name,

        sum(departures_count) as departures_count,
        sum(arrivals_count) as arrivals_count,

        sum(departure_passenger_count) as departure_passenger_count,
        sum(arrival_passenger_count) as arrival_passenger_count,
        (
            sum(departure_passenger_count)
            + sum(arrival_passenger_count)
        ) as total_passenger_count,

        coalesce(sum(departure_revenue), 0) as departure_revenue,
        coalesce(sum(arrival_revenue), 0) as arrival_revenue,
        coalesce(sum(departure_revenue), 0)
        + coalesce(sum(arrival_revenue), 0) as total_revenue

    from airport_events
    group by
        traffic_date,
        airport_name;

end;
$$;


-- Главная сборочная процедура

create or replace procedure dm.load_airport_traffic_daily_from_flight_sales_mart()
language plpgsql
as $$
declare
    v_step_started_at timestamptz;
begin

    v_step_started_at := clock_timestamp();

    truncate table dm.airport_traffic_daily;

    raise notice 'truncate table dm.airport_traffic_daily duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call dm.insert_airport_traffic_daily_from_flight_sales_mart();

    raise notice 'dm.insert_airport_traffic_daily_from_flight_sales_mart duration: %',
        clock_timestamp() - v_step_started_at;


    raise notice 'dm.airport_traffic_daily loaded. rows = %',
        (select count(*) from dm.airport_traffic_daily);

end;
$$;