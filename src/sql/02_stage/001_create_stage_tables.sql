
-----------------------------------------------------------------------------------------------
-- Создание таблиц слоя STAGE: данные источника сохраняются в формате AS IS и технические поля --
-----------------------------------------------------------------------------------------------


CREATE table if not exists stg.airplanes (
	airplane_code text not null,
	model_en text,
	model_ru text,
	"range" int4,
	speed int4,
	-- технические поля
	raw_load_date timestamptz not null, --дата и время, когда событие попало в RAW-слой
	stg_load_date timestamptz not null default now(), --дата и время, когда строка была загружена в STAG
	source_system text not null, -- исходная система, откуда пришли данные
	record_source text not null, -- источник записи: таблица, файл, API и т.д.
	batch_id bigint not null, -- идентификатор пакета загрузки
	operation_type text not null, -- тип операции: I - insert, U - update, D - delete
	is_valid boolean not null default true, --результат базовой проверки качества данных в STAGE
	validation_error text --текст ошибки, если строка не прошла проверку
);

CREATE table if not exists stg.airports (
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
	raw_load_date timestamptz not null, --дата и время, когда событие попало в RAW-слой
	stg_load_date timestamptz not null default now(), --дата и время, когда строка была загружена в STAG
	source_system text not null, -- исходная система, откуда пришли данные
	record_source text not null, -- источник записи: таблица, файл, API и т.д.
	batch_id bigint not null, -- идентификатор пакета загрузки
	operation_type text not null, -- тип операции: I - insert, U - update, D - delete
	is_valid boolean not null default true, --результат базовой проверки качества данных в STAGE
	validation_error text --текст ошибки, если строка не прошла проверку
);

CREATE table if not exists stg.boarding_passes (
	ticket_no text ,
	flight_id int4 ,
	seat_no text ,
	boarding_no int4 ,
	boarding_time timestamptz ,
	-- технические поля
	raw_load_date timestamptz not null, --дата и время, когда событие попало в RAW-слой
	stg_load_date timestamptz not null default now(), --дата и время, когда строка была загружена в STAG
	source_system text not null, -- исходная система, откуда пришли данные
	record_source text not null, -- источник записи: таблица, файл, API и т.д.
	batch_id bigint not null, -- идентификатор пакета загрузки
	operation_type text not null, -- тип операции: I - insert, U - update, D - delete
	is_valid boolean not null default true, --результат базовой проверки качества данных в STAGE
	validation_error text --текст ошибки, если строка не прошла проверку
);

CREATE table if not exists stg.bookings (
	book_ref text ,
	book_date timestamptz ,
	total_amount numeric(10, 2),
	-- технические поля
	raw_load_date timestamptz not null, --дата и время, когда событие попало в RAW-слой
	stg_load_date timestamptz not null default now(), --дата и время, когда строка была загружена в STAG
	source_system text not null, -- исходная система, откуда пришли данные
	record_source text not null, -- источник записи: таблица, файл, API и т.д.
	batch_id bigint not null, -- идентификатор пакета загрузки
	operation_type text not null, -- тип операции: I - insert, U - update, D - delete
	is_valid boolean not null default true, --результат базовой проверки качества данных в STAGE
	validation_error text --текст ошибки, если строка не прошла проверку

);

CREATE table if not exists stg.flights (
	flight_id int4,
	route_no text ,
	status text,
	scheduled_departure timestamptz,
	scheduled_arrival timestamptz,
	actual_departure timestamptz,
	actual_arrival timestamptz,
	-- технические поля
	raw_load_date timestamptz not null, --дата и время, когда событие попало в RAW-слой
	stg_load_date timestamptz not null default now(), --дата и время, когда строка была загружена в STAG
	source_system text not null, -- исходная система, откуда пришли данные
	record_source text not null, -- источник записи: таблица, файл, API и т.д.
	batch_id bigint not null, -- идентификатор пакета загрузки
	operation_type text not null, -- тип операции: I - insert, U - update, D - delete
	is_valid boolean not null default true, --результат базовой проверки качества данных в STAGE
	validation_error text --текст ошибки, если строка не прошла проверку
);

CREATE table if not exists stg.routes (
	route_no text,
	validity tstzrange,
	departure_airport text,
	arrival_airport text,
	airplane_code text,
	days_of_week integer [],
	scheduled_time time,
	duration interval,
	-- технические поля
	raw_load_date timestamptz not null, --дата и время, когда событие попало в RAW-слой
	stg_load_date timestamptz not null default now(), --дата и время, когда строка была загружена в STAG
	source_system text not null, -- исходная система, откуда пришли данные
	record_source text not null, -- источник записи: таблица, файл, API и т.д.
	batch_id bigint not null, -- идентификатор пакета загрузки
	operation_type text not null, -- тип операции: I - insert, U - update, D - delete
	is_valid boolean not null default true, --результат базовой проверки качества данных в STAGE
	validation_error text --текст ошибки, если строка не прошла проверку
);

CREATE table if not exists stg.seats (
	airplane_code text,
	seat_no text,
	fare_conditions text,
	-- технические поля
	raw_load_date timestamptz not null, --дата и время, когда событие попало в RAW-слой
	stg_load_date timestamptz not null default now(), --дата и время, когда строка была загружена в STAG
	source_system text not null, -- исходная система, откуда пришли данные
	record_source text not null, -- источник записи: таблица, файл, API и т.д.
	batch_id bigint not null, -- идентификатор пакета загрузки
	operation_type text not null, -- тип операции: I - insert, U - update, D - delete
	is_valid boolean not null default true, --результат базовой проверки качества данных в STAGE
	validation_error text --текст ошибки, если строка не прошла проверку
);

CREATE table if not exists stg.segments (
	ticket_no text,
	flight_id int4,
	fare_conditions text,
	price numeric(10, 2),
	-- технические поля
	raw_load_date timestamptz not null, --дата и время, когда событие попало в RAW-слой
	stg_load_date timestamptz not null default now(), --дата и время, когда строка была загружена в STAG
	source_system text not null, -- исходная система, откуда пришли данные
	record_source text not null, -- источник записи: таблица, файл, API и т.д.
	batch_id bigint not null, -- идентификатор пакета загрузки
	operation_type text not null, -- тип операции: I - insert, U - update, D - delete
	is_valid boolean not null default true, --результат базовой проверки качества данных в STAGE
	validation_error text --текст ошибки, если строка не прошла проверку
);

CREATE table if not exists stg.tickets (
	ticket_no text,
	book_ref text,
	passenger_id text,
	passenger_name text,
	outbound bool,	
	-- технические поля
	raw_load_date timestamptz not null, --дата и время, когда событие попало в RAW-слой
	stg_load_date timestamptz not null default now(), --дата и время, когда строка была загружена в STAG
	source_system text not null, -- исходная система, откуда пришли данные
	record_source text not null, -- источник записи: таблица, файл, API и т.д.
	batch_id bigint not null, -- идентификатор пакета загрузки
	operation_type text not null, -- тип операции: I - insert, U - update, D - delete
	is_valid boolean not null default true, --результат базовой проверки качества данных в STAGE
	validation_error text --текст ошибки, если строка не прошла проверку
);

	


