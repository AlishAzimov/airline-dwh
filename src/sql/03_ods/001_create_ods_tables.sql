
-----------------------------------------------------------------------------------------------
-- Создание таблиц слоя ODS: данные источника сохраняются в формате AS IS и технические поля --
-----------------------------------------------------------------------------------------------


CREATE table if not exists ods.airplanes (
    airplane_code text not null,
    model_en text,
    model_ru text,
    "range" int4,
    speed int4,
    -- технические поля
    source_system text not null,      -- исходная система, откуда пришла строка
    record_source text not null,      -- источник записи: таблица, файл, API и т.д.
    created_batch_id bigint not null, -- batch, в котором строка впервые появилась в ODS
    updated_batch_id bigint not null, -- последний batch, который изменил строку в ODS
    last_changed_at timestamptz not null default now(), -- дата последнего изменения строки в ODS
    is_deleted boolean not null default false, -- актуальна строка или удалена
    last_operation_type text not null, -- последняя операция: I, U или D
    
    constraint pk_ods_airplanes primary key (airplane_code)
);


CREATE table if not exists ods.airports (
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
    created_batch_id bigint not null, -- batch, в котором строка впервые появилась в ODS
    updated_batch_id bigint not null, -- последний batch, который изменил строку в ODS
    last_changed_at timestamptz not null default now(), -- дата последнего изменения строки в ODS
    is_deleted boolean not null default false, -- актуальна строка или удалена
    last_operation_type text not null, -- последняя операция: I, U или D
    
    constraint pk_ods_airports primary key (airport_code)
);

CREATE table if not exists ods.boarding_passes (
	ticket_no text ,
	flight_id int4 ,
	seat_no text ,
	boarding_no int4 ,
	boarding_time timestamptz ,
    -- технические поля
    source_system text not null,      -- исходная система, откуда пришла строка
    record_source text not null,      -- источник записи: таблица, файл, API и т.д.
    created_batch_id bigint not null, -- batch, в котором строка впервые появилась в ODS
    updated_batch_id bigint not null, -- последний batch, который изменил строку в ODS
    last_changed_at timestamptz not null default now(), -- дата последнего изменения строки в ODS
    is_deleted boolean not null default false, -- актуальна строка или удалена
    last_operation_type text not null, -- последняя операция: I, U или D
	
    constraint pk_ods_boarding_passes primary key (ticket_no, flight_id)
);

CREATE table if not exists ods.bookings (
	book_ref text ,
	book_date timestamptz ,
	total_amount numeric(10, 2),
    -- технические поля
    source_system text not null,      -- исходная система, откуда пришла строка
    record_source text not null,      -- источник записи: таблица, файл, API и т.д.
    created_batch_id bigint not null, -- batch, в котором строка впервые появилась в ODS
    updated_batch_id bigint not null, -- последний batch, который изменил строку в ODS
    last_changed_at timestamptz not null default now(), -- дата последнего изменения строки в ODS
    is_deleted boolean not null default false, -- актуальна строка или удалена
    last_operation_type text not null, -- последняя операция: I, U или D
    
   	constraint pk_ods_bookings primary key (book_ref)

);

CREATE table if not exists ods.flights (
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
    created_batch_id bigint not null, -- batch, в котором строка впервые появилась в ODS
    updated_batch_id bigint not null, -- последний batch, который изменил строку в ODS
    last_changed_at timestamptz not null default now(), -- дата последнего изменения строки в ODS
    is_deleted boolean not null default false, -- актуальна строка или удалена
    last_operation_type text not null, -- последняя операция: I, U или D
	
	constraint pk_ods_flights primary key (flight_id)
);

CREATE table if not exists ods.routes (
	route_no text,
	validity tstzrange,
	departure_airport text,
	arrival_airport text,
	airplane_code text,
	days_of_week integer [],
	scheduled_time time,
	duration interval,
	-- технические поля для аудита, lineage и имитации CDC
	load_date timestamptz not null default now(), -- дата и время загрузки записи в DWH
	record_source text not null, -- источник записи: таблица, файл, API и т.д.
	source_system text not null, -- исходная система, откуда пришли данные
	batch_id bigint, -- идентификатор пакета загрузки
	operation_type text not null default 'I', -- тип операции: I - insert, U - update, D - delete
	ods_row_hash text -- хеш строки для проверки изменений
);

CREATE table if not exists ods.seats (
	airplane_code text,
	seat_no text,
	fare_conditions text,
	-- технические поля для аудита, lineage и имитации CDC
	load_date timestamptz not null default now(), -- дата и время загрузки записи в DWH
	record_source text not null, -- источник записи: таблица, файл, API и т.д.
	source_system text not null, -- исходная система, откуда пришли данные
	batch_id bigint, -- идентификатор пакета загрузки
	operation_type text not null default 'I', -- тип операции: I - insert, U - update, D - delete
	ods_row_hash text -- хеш строки для проверки изменений
);

CREATE table if not exists ods.segments (
	ticket_no text,
	flight_id int4,
	fare_conditions text,
	price numeric(10, 2),
	-- технические поля для аудита, lineage и имитации CDC
	load_date timestamptz not null default now(), -- дата и время загрузки записи в DWH
	record_source text not null, -- источник записи: таблица, файл, API и т.д.
	source_system text not null, -- исходная система, откуда пришли данные
	batch_id bigint, -- идентификатор пакета загрузки
	operation_type text not null default 'I', -- тип операции: I - insert, U - update, D - delete
	ods_row_hash text -- хеш строки для проверки изменений
);

CREATE table if not exists ods.tickets (
	ticket_no text,
	book_ref text,
	passenger_id text,
	passenger_name text,
	outbound bool,	
	-- технические поля для аудита, lineage и имитации CDC
	load_date timestamptz not null default now(), -- дата и время загрузки записи в DWH
	record_source text not null, -- источник записи: таблица, файл, API и т.д.
	source_system text not null, -- исходная система, откуда пришли данные
	batch_id bigint, -- идентификатор пакета загрузки
	operation_type text not null default 'I', -- тип операции: I - insert, U - update, D - delete
	ods_row_hash text -- хеш строки для проверки изменений
);

	


