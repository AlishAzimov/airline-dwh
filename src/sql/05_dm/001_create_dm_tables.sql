-----------------------------------------------------------------------------------------------
-- Создание таблиц слоя DM: готовые витрины данных для BI-отчётов и Superset --
-----------------------------------------------------------------------------------------------

-- Детальная витрина продаж: 1 строка = 1 сегмент билета ticket_no + flight_id
create table if not exists dm.flight_sales_mart (
    ticket_no text not null,
    flight_id int4 not null,

    passenger_id text,
    route_no text,
    book_ref text,

    total_amount numeric(10, 2),
    price numeric(10, 2),
    fare_conditions text,
    outbound boolean,

    book_date timestamptz,

    status text,
    scheduled_departure timestamptz,
    scheduled_arrival timestamptz,
    actual_departure timestamptz,
    actual_arrival timestamptz,
    duration interval,

    departure_airport_name text,
    arrival_airport_name text,
    airplane_model text,

    source_max_batch_id bigint not null,
    mart_load_date timestamptz not null default now(), --время когда строка была загружена или пересчитана.

    constraint pk_dm_flight_sales_mart primary key (ticket_no, flight_id)
);




create table if not exists dm.flight_revenue_mart (
		
		flight_id int4 not null,
		passenger_count int4,
		total_revenue numeric(10, 2),
		economy_passenger_count int4,
		economy_revenue numeric(10, 2),
		comfort_passenger_count int4,
		comfort_revenue numeric(10, 2),
		business_passenger_count int4,
		business_revenue numeric(10, 2),
		avg_price numeric(10, 2),
		max_price numeric(10, 2),
		min_price numeric(10, 2),
		status text,
		duration interval,
		departure_airport_name text,
		arrival_airport_name text,
	    airplane_model text,
	    
	    constraint pk_dm_flight_revenue_mart primary key (flight_id)
)






select * from dm.flight_sales_mart order by source_max_batch_id desc limit 30;


select 
flight_id,
count(passenger_id) as passenger_count,
sum(price) as total_revenue,
count(passenger_id) filter (where fare_conditions = 'Economy') as economy_passenger_count,
coalesce(sum(price) filter (where fare_conditions = 'Economy'), 0) as economy_revenue,
count(passenger_id) filter (where fare_conditions = 'Comfort') as comfort_passenger_count,
coalesce(sum(price) filter (where fare_conditions = 'Comfort'),0) as comfort_revenue,
count(passenger_id) filter (where fare_conditions = 'Business') as business_passenger_count,
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
group by flight_id















