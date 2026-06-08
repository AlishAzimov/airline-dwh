
--------------------------------------------------------------------------------------------------------
-- Создание процедур слоя DM: загрузка витрины продаж рейсов из DDS в DM --
--------------------------------------------------------------------------------------------------------

-- Процедура I/U: вставка новых и обновление существующих строк витрины продаж
create or replace procedure dm.upsert_flight_sales_mart_from_dds()
language plpgsql
as $$
declare 
    v_last_loaded_batch_id bigint;
begin
	
    select coalesce(max(source_max_batch_id), 0)
    into v_last_loaded_batch_id
    from dm.flight_sales_mart;

    insert into dm.flight_sales_mart (
        ticket_no,
        flight_id,
        passenger_id,
        route_no,
        book_ref,
        total_amount,
        price,
        fare_conditions,
        outbound,
        book_date,
        status,
        scheduled_departure,
        scheduled_arrival,
        actual_departure,
        actual_arrival,
        duration,
        departure_airport_name,
        arrival_airport_name,
        airplane_model,
        source_max_batch_id,
        mart_load_date
    )
    with flight_sales_src as (
        select 
			s.ticket_no,
			s.flight_id,
			t.passenger_id,
			f.route_no,
			b.book_ref,
			b.total_amount,
			s.price,
			s.fare_conditions,
			t.outbound,
			b.book_date,
			f.status,
			f.scheduled_departure,
			f.scheduled_arrival,
			f.actual_departure,
			f.actual_arrival,
			r.duration, 
			dep.airport_name_ru as departure_airport_name,
			arr.airport_name_ru as arrival_airport_name,
			a.model_ru as airplane_model,
			greatest(
			    coalesce(s.batch_id, 0),
			    coalesce(t.batch_id, 0),
			    coalesce(b.batch_id, 0),
			    coalesce(f.batch_id, 0),
			    coalesce(r.batch_id, 0),
			    coalesce(dep.batch_id, 0),
			    coalesce(arr.batch_id, 0),
			    coalesce(a.batch_id, 0)
			) as source_max_batch_id
        from dds.fact_segments s
        left join dds.fact_tickets t 
            on s.ticket_sk = t.ticket_sk
        left join dds.fact_bookings b 
            on t.bookings_sk = b.bookings_sk  
        left join dds.fact_flights f 
            on s.flight_sk = f.flight_sk 
        left join dds.dim_routes r 
            on f.route_sk = r.route_sk 
        left join dds.dim_airports dep 
            on r.departure_airport_sk = dep.airport_sk
        left join dds.dim_airports arr 
            on r.arrival_airport_sk = arr.airport_sk
        left join dds.dim_airplanes a 
            on r.airplane_sk = a.airplane_sk
        where s.is_deleted = false
		  and coalesce(t.is_deleted, false) = false
		  and coalesce(b.is_deleted, false) = false
		  and coalesce(f.is_deleted, false) = false
    )
    select
        ticket_no,
        flight_id,
        passenger_id,
        route_no,
        book_ref,
        total_amount,
        price,
        fare_conditions,
        outbound,
        book_date,
        status,
        scheduled_departure,
        scheduled_arrival,
        actual_departure,
        actual_arrival,
        duration,
        departure_airport_name,
        arrival_airport_name,
        airplane_model,
        source_max_batch_id,
        now() as mart_load_date
    from flight_sales_src
    where source_max_batch_id > v_last_loaded_batch_id

    on conflict (ticket_no, flight_id) do update
    set
        passenger_id = excluded.passenger_id,
        route_no = excluded.route_no,
        book_ref = excluded.book_ref,
        total_amount = excluded.total_amount,
        price = excluded.price,
        fare_conditions = excluded.fare_conditions,
        outbound = excluded.outbound,
        book_date = excluded.book_date,
        status = excluded.status,
        scheduled_departure = excluded.scheduled_departure,
        scheduled_arrival = excluded.scheduled_arrival,
        actual_departure = excluded.actual_departure,
        actual_arrival = excluded.actual_arrival,
        duration = excluded.duration,
        departure_airport_name = excluded.departure_airport_name,
        arrival_airport_name = excluded.arrival_airport_name,
        airplane_model = excluded.airplane_model,
        source_max_batch_id = excluded.source_max_batch_id,
        mart_load_date = now();

end;
$$;


-- Главная сборочная процедура

create or replace procedure dm.load_flight_sales_mart_from_dds()
language plpgsql
as $$
declare
    v_step_started_at timestamptz;
begin
    v_step_started_at := clock_timestamp();

    call dm.upsert_flight_sales_mart_from_dds();

    raise notice 'dm.upsert_flight_sales_mart_from_dds duration: %',
        clock_timestamp() - v_step_started_at;

    raise notice ' dm.upsert_flight_sales_mart_from_dds rows =% ',
        (select count(*) from dm.flight_sales_mart);
end;
$$;

