
--------------------------------------------------------------------------------------------------------
-- Создание процедур слоя DM: загрузка агрегированной витрины выручки по рейсам --
--------------------------------------------------------------------------------------------------------

-- Процедура загрузки витрины: агрегирует данные из dm.flight_sales_mart по flight_id
create or replace procedure dm.upsert_flight_revenue_mart_from_flight_sales_mart()
language plpgsql
as $$
BEGIN
	insert INTO dm.flight_revenue_mart( 
		flight_id,
		passenger_count,
		total_revenue,
		economy_passenger_count,
		economy_revenue,
		comfort_passenger_count,
		comfort_revenue,
		business_passenger_count,
		business_revenue,
		avg_price,
		max_price,
		min_price,
		status,
		duration,
		departure_airport_name,
		arrival_airport_name,
	    airplane_model)
	    
	select 
		flight_id,
		count(distinct passenger_id) as passenger_count,
		sum(price) as total_revenue,
		count(distinct passenger_id) filter (where fare_conditions = 'Economy') as economy_passenger_count,
		coalesce(sum(price) filter (where fare_conditions = 'Economy'), 0) as economy_revenue,
		count(distinct passenger_id) filter (where fare_conditions = 'Comfort') as comfort_passenger_count,
		coalesce(sum(price) filter (where fare_conditions = 'Comfort'),0) as comfort_revenue,
		count(distinct passenger_id) filter (where fare_conditions = 'Business') as business_passenger_count,
		coalesce(sum(price) filter (where fare_conditions = 'Business'),0) as business_revenue,
		round(avg(price),2) as avg_price,
		max(price) as max_price,
		min(price) as min_price,
		max(status) as status, 
		max(duration) as duration,
		max(departure_airport_name) as departure_airport_name,
		max(arrival_airport_name) as arrival_airport_name,
		max(airplane_model) as airplane_model
	from dm.flight_sales_mart
	group by flight_id;
			
END;
$$;



-- Главная сборочная процедура

create or replace procedure dm.load_flight_sales_mart_from_dds()
language plpgsql
as $$
declare
    v_step_started_at timestamptz;
BEGIN
	
 	v_step_started_at := clock_timestamp();

    truncate table dm.flight_revenue_mart;

    raise notice 'truncate table dm.flight_revenue_mart duration: %',
        clock_timestamp() - v_step_started_at;
	
    v_step_started_at := clock_timestamp();

    call dm.upsert_flight_revenue_mart_from_flight_sales_mart();

    raise notice 'dm.upsert_flight_revenue_mart_from_flight_sales_mart duration: %',
        clock_timestamp() - v_step_started_at;

    raise notice 'dm.upsert_flight_revenue_mart_from_flight_sales_mart rows =% ',
        (select count(*) from dm.flight_revenue_mart);
end;
$$;

