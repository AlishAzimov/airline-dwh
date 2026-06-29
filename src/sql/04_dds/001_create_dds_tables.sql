
-----------------------------------------------------------------------------------------------
-- Создание таблиц слоя DDS: измерения и факты для аналитической модели данных --
-----------------------------------------------------------------------------------------------

-- SCD2-измерение самолётов: хранит историю изменений по airplane_code
CREATE table if not exists dds.dim_airplanes (
    airplane_sk uuid not null, -- surrogate key, считается в процедуре
	airplane_code text not null,
    model_en text,
    model_ru text,
    "range" int4,
    speed int4,
    -- технические поля
    source_system text not null,      -- исходная система, откуда пришла строка
    record_source text not null,      -- источник записи: таблица, файл, API и т.д.
    valid_from timestamptz not null default now(), -- с какого момента версия актуальна
    valid_to timestamptz not null default '9999-12-31'::timestamptz, -- до какого момента версия актуальна
	is_current boolean not null default true, -- текущая ли версия
    batch_id bigint not null, -- batch, который создал или последний раз изменил статус версии
    
    constraint pk_dds_airplanes primary key (airplane_sk),
    constraint chk_dds_airplanes_valid_period check (valid_to > valid_from) -- чек правильного заполнение дат
    );


-- SCD2: запрещает наличие нескольких активных версий одного airplane_code
create unique index if not exists uq_dds_dim_airplanes_current
on dds.dim_airplanes (airplane_code)
where is_current = true;



-- SCD2-измерение аэропортов: хранит историю изменений по airport_code 
CREATE table if not exists dds.dim_airports (
  	airport_sk uuid not null, -- surrogate key, считается в процедуре
    airport_code text not null,
    airport_name_en text,
    airport_name_ru text,
    city_en text,
    city_ru text,
   	country_en text,
    country_ru text,
    coordinates point,
    timezone text,
     -- технические поля
    source_system text not null,      -- исходная система, откуда пришла строка
    record_source text not null,      -- источник записи: таблица, файл, API и т.д.
    valid_from timestamptz not null default now(), -- с какого момента версия актуальна
    valid_to timestamptz not null default '9999-12-31'::timestamptz, -- до какого момента версия актуальна
	is_current boolean not null default true, -- текущая ли версия
    batch_id bigint not null, -- batch, который создал или последний раз изменил статус версии
    
    constraint pk_dds_airports primary key (airport_sk),
    constraint chk_dds_airports_valid_period check (valid_to > valid_from) -- чек правильного заполнение дат
    );

-- SCD2: запрещает наличие нескольких активных версий одного airport_code
create unique index if not exists uq_dds_dim_airport_current
on dds.dim_airports (airport_code)
where is_current = true;    

-- SCD1-измерение маошрутов
CREATE table if not exists dds.dim_routes (
	route_sk uuid not null, -- surrogate key, считается в процедуре	
	route_no text not null,
	validity tstzrange not null,

   	-- surrogate key из DDS
    departure_airport_sk uuid not null,
    arrival_airport_sk uuid not null,
    airplane_sk uuid not null,
	
	days_of_week integer [],
	scheduled_time time,
	duration interval,
  	-- технические поля
    source_system text not null,      -- исходная система, откуда пришла строка
    record_source text not null,      -- источник записи: таблица, файл, API и т.д.
    batch_id bigint not null, -- batch, который создал или последний раз изменил статус версии
    last_changed_at timestamptz not null default now(),
 	is_deleted boolean not null default false,
    
    constraint pk_dds_routes primary key (route_sk),
    
    constraint uq_dds_dim_seats_source_key unique (route_no, validity),
 
 	constraint fk_dds_routes_departure_airport
        foreign key (departure_airport_sk)
        references dds.dim_airports (airport_sk),
        
    constraint fk_dds_routes_arrival_airport
        foreign key (arrival_airport_sk)
        references dds.dim_airports (airport_sk),
       
    constraint fk_dds_routes_airplane
        foreign key (airplane_sk)
        references dds.dim_airplanes (airplane_sk)
);
   


-- SCD1-измерение мест: хранит актуальное состояние мест по airplane_code и seat_no

create table if not exists dds.dim_seats (
    seat_sk uuid not null, -- surrogate key, считается в процедуре

    -- source keys из ODS
    seat_no text not null,
    airplane_code text,

    -- surrogate key из DDS
    airplane_sk uuid,

    fare_conditions text,
    
    -- технические поля
    source_system text not null,      -- исходная система, откуда пришла строка
    record_source text not null,      -- источник записи: таблица, файл, API и т.д.
 	batch_id bigint not null, -- batch, который создал или последний раз обновил строку
    last_changed_at timestamptz not null default now(),
    is_deleted boolean not null default false,

    constraint pk_dds_dim_seats primary key (seat_sk),

    constraint uq_dds_dim_routes_source_key unique (seat_no, airplane_code),

    constraint fk_dds_dim_seats_airplane
        foreign key (airplane_sk)
        references dds.dim_airplanes (airplane_sk)
);


-- SCD1-измерение Пассажиры, берем из таблицы tickets 
create table if not exists dds.dim_passenger (
    passenger_sk uuid not null, -- surrogate key, считается в процедуре

    passenger_id text not null,
	passenger_name text,
    
    -- технические поля
    source_system text not null,      -- исходная система, откуда пришла строка
    record_source text not null,      -- источник записи: таблица, файл, API и т.д.
 	batch_id bigint not null, -- batch, который создал или последний раз обновил строку
    last_changed_at timestamptz not null default now(),

    constraint pk_dds_dim_passenger primary key (passenger_sk),
    constraint uq_dds_dim_passenger_passenger_id unique (passenger_id)

);


-- Факт рейсов: хранит актуальное состояние рейсов из таблицы flights
CREATE table if not exists dds.fact_flights (
    flight_sk uuid not null, -- surrogate key, считается в процедуре
    route_sk uuid not null, -- surrogate key из DDS
	flight_id int4 not null,
	status text,
	scheduled_departure timestamptz,
	scheduled_arrival timestamptz,
	actual_departure timestamptz,
	actual_arrival timestamptz,
    -- технические поля
    source_system text not null,      -- исходная система, откуда пришла строка
    record_source text not null,      -- источник записи: таблица, файл, API и т.д.
    batch_id bigint not null, -- batch, который создал или последний раз обновил строку
    last_changed_at timestamptz not null default now(), -- дата последнего изменения строки в dds
    is_deleted boolean not null default false, -- актуальна строка или удалена
	
	constraint pk_dds_fact_flights primary key (flight_sk),
	constraint uq_dds_fact_flights_source_key unique (flight_id),
	constraint fk_dds_fact_flights_routes foreign key (route_sk) references dds.dim_routes(route_sk),
	
	--check 
	constraint chk_dds_fact_flights_sch check (scheduled_departure < scheduled_arrival),  
	constraint chk_dds_fact_flights_act check (actual_arrival is null or (actual_departure is not null and actual_departure < actual_arrival))  
);


CREATE table if not exists dds.fact_bookings (
	bookings_sk uuid not null, -- surrogate key, считается в процедуре
	book_ref text,
	book_date timestamptz ,
	total_amount numeric(10, 2),
    -- технические поля
    source_system text not null,      -- исходная система, откуда пришла строка
    record_source text not null,      -- источник записи: таблица, файл, API и т.д.
    batch_id bigint not null, -- batch, который создал или последний раз обновил строку
    last_changed_at timestamptz not null default now(), -- дата последнего изменения строки в dds
    is_deleted boolean not null default false, -- актуальна строка или удалена
	
   	constraint pk_dds_fact_bookings primary key (bookings_sk),
  	constraint uq_dds_fact_bookings_source_key unique (book_ref)
);

CREATE table if not exists dds.fact_tickets (
	ticket_sk uuid not null, -- surrogate key, считается в процедуре
	bookings_sk uuid not null, -- surrogate key из DDS
	passenger_sk uuid not null, -- surrogate key из DDS
	
	ticket_no text,
	outbound bool,	
    -- технические поля
    source_system text not null,      -- исходная система, откуда пришла строка
    record_source text not null,      -- источник записи: таблица, файл, API и т.д.
    batch_id bigint not null, -- batch, который создал или последний раз обновил строку
    last_changed_at timestamptz not null default now(), -- дата последнего изменения строки в dds
    is_deleted boolean not null default false, -- актуальна строка или удалена
    
    constraint pk_dds_fact_tickets primary key (ticket_sk),
    constraint fk_dds_fact_tickets_bookings foreign key (bookings_sk) references dds.fact_bookings(bookings_sk),
    constraint fk_dds_fact_tickets_passenger foreign key (passenger_sk) references dds.dim_passenger(passenger_sk),
  	constraint uq_dds_fact_tickets_source_key unique (ticket_no)
    
);

create table if not exists dds.fact_segments (
    segment_sk uuid not null, -- surrogate key, считается в процедуре
    ticket_sk uuid not null,-- surrogate keys из DDS
    flight_sk uuid not null,-- surrogate keys из DDS

    fare_conditions text,
    price numeric(10, 2),
    -- технические поля
    source_system text not null,      -- исходная система, откуда пришла строка
    record_source text not null,      -- источник записи: таблица, файл, API и т.д.
    batch_id bigint not null,         -- batch, который создал или последний раз обновил строку
    last_changed_at timestamptz not null default now(), -- дата последнего изменения строки в DDS
    is_deleted boolean not null default false, -- актуальна строка или удалена

    constraint pk_dds_fact_segments primary key (segment_sk),

    constraint uq_dds_fact_segments_source_key unique (ticket_sk, flight_sk),

    constraint fk_dds_fact_segments_ticket foreign key (ticket_sk) references dds.fact_tickets (ticket_sk),

    constraint fk_dds_fact_segments_flight foreign key (flight_sk) references dds.fact_flights (flight_sk)
);



    
CREATE table if not exists dds.fact_boarding_passes (
	boarding_pass_sk uuid not null, -- surrogate key, считается в процедуре
    ticket_sk uuid not null,-- surrogate keys из DDS
    flight_sk uuid not null,-- surrogate keys из DDS

	seat_no text,
	boarding_no int4,
	boarding_time timestamptz,
	-- технические поля
    source_system text not null,      -- исходная система, откуда пришла строка
    record_source text not null,      -- источник записи: таблица, файл, API и т.д.
    batch_id bigint not null,         -- batch, который создал или последний раз обновил строку
    last_changed_at timestamptz not null default now(), -- дата последнего изменения строки в DDS
    is_deleted boolean not null default false, -- актуальна строка или удалена
    
    constraint pk_dds_fact_boarding_passes primary key (boarding_pass_sk),
    constraint uq_dds_fact_boarding_passes unique (ticket_sk, flight_sk),
    constraint fk_dds_fact_boarding_passes_ticket foreign key (ticket_sk) references dds.fact_tickets (ticket_sk),
    constraint fk_dds_fact_boarding_passes_flight foreign key (flight_sk) references dds.fact_flights (flight_sk)

);

	


