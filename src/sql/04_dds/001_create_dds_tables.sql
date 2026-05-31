
-----------------------------------------------------------------------------------------------
-- Создание таблиц слоя DDS: измерения и факты для аналитической модели данных --
-----------------------------------------------------------------------------------------------

-- SCD2-измерение самолётов: хранит историю изменений по airplane_code
CREATE table if not exists dds.dim_airplanes (
    airplane_sk bigint generated always as identity, -- surrogate key
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
  	airport_sk bigint generated always as identity, -- surrogate key
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
    

-- SCD2-измерение маошрутов: хранит историю изменений по route_no и validity
CREATE table if not exists dds.dim_routes (
	routes_sk bigint generated always as identity, -- surrogate key	
	route_no text,
	validity tstzrange,
	departure_airport text,
	arrival_airport text,
	airplane_code text,
	days_of_week integer [],
	scheduled_time time,
	duration interval,
  	-- технические поля
    source_system text not null,      -- исходная система, откуда пришла строка
    record_source text not null,      -- источник записи: таблица, файл, API и т.д.
    valid_from timestamptz not null default now(), -- с какого момента версия актуальна
    valid_to timestamptz not null default '9999-12-31'::timestamptz, -- до какого момента версия актуальна
	is_current boolean not null default true, -- текущая ли версия
    batch_id bigint not null, -- batch, который создал или последний раз изменил статус версии
    
    constraint pk_dds_routes primary key (routes_sk),
    constraint chk_dds_routes_valid_period check (valid_to > valid_from) -- чек правильного заполнение дат
);

create unique index if not exists uq_dds_dim_routes_current
on dds.dim_routes (route_no, validity)
where is_current = true;    
    

    
CREATE table if not exists dds.boarding_passes (
	ticket_no text ,
	flight_id int4 ,
	seat_no text ,
	boarding_no int4 ,
	boarding_time timestamptz ,
    -- технические поля
    source_system text not null,      -- исходная система, откуда пришла строка
    record_source text not null,      -- источник записи: таблица, файл, API и т.д.
    created_batch_id bigint not null, -- batch, в котором строка впервые появилась в dds
    updated_batch_id bigint not null, -- последний batch, который изменил строку в dds
    last_changed_at timestamptz not null default now(), -- дата последнего изменения строки в dds
    is_deleted boolean not null default false, -- актуальна строка или удалена
    last_operation_type text not null, -- последняя операция: I, U или D
	
    constraint pk_dds_boarding_passes primary key (ticket_no, flight_id)
);

CREATE table if not exists dds.bookings (
	book_ref text ,
	book_date timestamptz ,
	total_amount numeric(10, 2),
    -- технические поля
    source_system text not null,      -- исходная система, откуда пришла строка
    record_source text not null,      -- источник записи: таблица, файл, API и т.д.
    created_batch_id bigint not null, -- batch, в котором строка впервые появилась в dds
    updated_batch_id bigint not null, -- последний batch, который изменил строку в dds
    last_changed_at timestamptz not null default now(), -- дата последнего изменения строки в dds
    is_deleted boolean not null default false, -- актуальна строка или удалена
    last_operation_type text not null, -- последняя операция: I, U или D
    
   	constraint pk_dds_bookings primary key (book_ref)

);

CREATE table if not exists dds.flights (
	flight_id int4,
	route_no text ,
	status text,
	scheduled_departure timestamptz,
	scheduled_arrival timestamptz,
	actual_departure timestamptz,
	actual_arrival timestamptz,
    -- технические поля
    source_system text not null,      -- исходная система, откуда пришла строка
    record_source text not null,      -- источник записи: таблица, файл, API и т.д.
    created_batch_id bigint not null, -- batch, в котором строка впервые появилась в dds
    updated_batch_id bigint not null, -- последний batch, который изменил строку в dds
    last_changed_at timestamptz not null default now(), -- дата последнего изменения строки в dds
    is_deleted boolean not null default false, -- актуальна строка или удалена
    last_operation_type text not null, -- последняя операция: I, U или D
	
	constraint pk_dds_flights primary key (flight_id)
);


CREATE table if not exists dds.seats (
	airplane_code text,
	seat_no text,
	fare_conditions text,
    -- технические поля
    source_system text not null,      -- исходная система, откуда пришла строка
    record_source text not null,      -- источник записи: таблица, файл, API и т.д.
    created_batch_id bigint not null, -- batch, в котором строка впервые появилась в dds
    updated_batch_id bigint not null, -- последний batch, который изменил строку в dds
    last_changed_at timestamptz not null default now(), -- дата последнего изменения строки в dds
    is_deleted boolean not null default false, -- актуальна строка или удалена
    last_operation_type text not null, -- последняя операция: I, U или D
    
    constraint pk_dds_seats primary key (airplane_code, seat_no)
);

CREATE table if not exists dds.segments (
	ticket_no text,
	flight_id int4,
	fare_conditions text,
	price numeric(10, 2),
    -- технические поля
    source_system text not null,      -- исходная система, откуда пришла строка
    record_source text not null,      -- источник записи: таблица, файл, API и т.д.
    created_batch_id bigint not null, -- batch, в котором строка впервые появилась в dds
    updated_batch_id bigint not null, -- последний batch, который изменил строку в dds
    last_changed_at timestamptz not null default now(), -- дата последнего изменения строки в dds
    is_deleted boolean not null default false, -- актуальна строка или удалена
    last_operation_type text not null, -- последняя операция: I, U или D
    
    constraint pk_dds_segments primary key (ticket_no, flight_id)
    );

CREATE table if not exists dds.tickets (
	ticket_no text,
	book_ref text,
	passenger_id text,
	passenger_name text,
	outbound bool,	
  	-- технические поля
    source_system text not null,      -- исходная система, откуда пришла строка
    record_source text not null,      -- источник записи: таблица, файл, API и т.д.
    created_batch_id bigint not null, -- batch, в котором строка впервые появилась в dds
    updated_batch_id bigint not null, -- последний batch, который изменил строку в dds
    last_changed_at timestamptz not null default now(), -- дата последнего изменения строки в dds
    is_deleted boolean not null default false, -- актуальна строка или удалена
    last_operation_type text not null, -- последняя операция: I, U или D
    
    constraint pk_dds_tickets primary key (ticket_no)
);

	


