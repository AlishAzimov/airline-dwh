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



-- Агрегированная витрина выручки по рейсам: 1 строка = 1 рейс
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


-- Витрина пассажиропотока аэропортов по дням: 1 строка = 1 день + 1 аэропорт

create table if not exists dm.airport_traffic_daily (
    traffic_date date not null,
    airport_name text not null,
    departures_count int4,
    arrivals_count int4,
    departure_passenger_count int4,
    arrival_passenger_count int4,
    total_passenger_count int4,
    departure_revenue numeric(10, 2),
    arrival_revenue numeric(10, 2),
    total_revenue numeric(10, 2),

    constraint pk_dm_airport_traffic_daily primary key (traffic_date, airport_name)
);
















