

--------------------------------------------------------------------------------------------
-- RAW CDC snapshot: хранит последнее состояние таблиц в source для определения I/U/D --
--------------------------------------------------------------------------------------------

--bookings

CREATE table if not exists raw.bookings_snapshot (
	book_ref text primary key,
	book_date timestamptz ,
	total_amount numeric(10, 2),
	-- технические поля
	raw_row_hash text not null, -- хеш строки для проверки изменений
	last_seen_at timestamptz not null default now() -- дата последнего фиксирование строки в source
);
	
	
--tickets

CREATE table if not exists raw.tickets_snapshot (
	ticket_no text primary key,
	book_ref text,
	passenger_id text,
	passenger_name text,
	outbound bool,
	-- технические поля
	raw_row_hash text not null, -- хеш строки для проверки изменений
	last_seen_at timestamptz not null default now() -- дата последнего фиксирование строки в source
);
	
--segments	

CREATE table if not exists raw.segments_snapshot (
	ticket_no text not null,
	flight_id int4 not null,
	fare_conditions text,
	price numeric(10, 2),
	-- технические поля
	raw_row_hash text not null, -- хеш строки для проверки изменений
	last_seen_at timestamptz not null default now(), -- дата последнего фиксирование строки в source
	-- Создание парных превичных ключей
	constraint pk_raw_segments_snapshot primary key (ticket_no, flight_id)
);



--boarding_passes

CREATE table if not exists raw.boarding_passes_snapshot (
	ticket_no text not null,
	flight_id int4 not null,
	seat_no text,
	boarding_no int4 ,
	boarding_time timestamptz,
	-- технические поля
	raw_row_hash text not null, -- хеш строки для проверки изменений
	last_seen_at timestamptz not null default now(), -- дата последнего фиксирование строки в source
	-- Создание парных превичных ключей
	constraint pk_raw_boarding_passes_snapshot primary key (ticket_no, flight_id)
);


--flights

CREATE table if not exists raw.flights_snapshot (
	flight_id int4 primary key,
	route_no text,
	status text,
	scheduled_departure timestamptz,
	scheduled_arrival timestamptz,
	actual_departure timestamptz,
	actual_arrival timestamptz,
	-- технические поля
	raw_row_hash text not null, -- хеш строки для проверки изменений
	last_seen_at timestamptz not null default now() -- дата последнего фиксирование строки в source
);

--routes

CREATE table if not exists raw.routes_snapshot (
	route_no text,
	validity tstzrange,
	departure_airport text,
	arrival_airport text,
	airplane_code text,
	days_of_week integer [],
	scheduled_time time,
	duration interval,
		-- технические поля
	raw_row_hash text not null, -- хеш строки для проверки изменений
	last_seen_at timestamptz not null default now(), -- дата последнего фиксирование строки в source
	-- Создание парных превичных ключей
	constraint pk_raw_routes_snapshot primary key (route_no, validity)
);
	
	
	