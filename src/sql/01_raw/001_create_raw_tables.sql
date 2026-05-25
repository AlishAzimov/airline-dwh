
-----------------------------------------------------------------------------------------------
-- Создание таблиц слоя RAW: данные источника сохраняются в формате AS IS и технические поля --
-----------------------------------------------------------------------------------------------


CREATE table if not exists raw.airplanes_data (
	airplane_code text,
	model jsonb,
	"range" int4,
	speed int4,
	-- технические поля для аудита, lineage и имитации CDC
	load_date timestamptz not null default now(), -- дата и время загрузки записи в DWH
	record_source text not null, -- источник записи: таблица, файл, API и т.д.
	source_system text not null, -- исходная система, откуда пришли данные
	batch_id bigint, -- идентификатор пакета загрузки
	operation_type text not null default 'I', -- тип операции: I - insert, U - update, D - delete
	raw_row_hash text -- хеш строки для проверки изменений
);

CREATE table if not exists raw.airports_data (
	airport_code text ,
	airport_name jsonb ,
	city jsonb ,
	country jsonb ,
	coordinates point ,
	timezone text ,
	-- технические поля для аудита, lineage и имитации CDC
	load_date timestamptz not null default now(), -- дата и время загрузки записи в DWH
	record_source text not null, -- источник записи: таблица, файл, API и т.д.
	source_system text not null, -- исходная система, откуда пришли данные
	batch_id bigint, -- идентификатор пакета загрузки
	operation_type text not null default 'I', -- тип операции: I - insert, U - update, D - delete
	raw_row_hash text -- хеш строки для проверки изменений
);

CREATE table if not exists raw.boarding_passes (
	ticket_no text ,
	flight_id int4 ,
	seat_no text ,
	boarding_no int4 ,
	boarding_time timestamptz ,
	-- технические поля для аудита, lineage и имитации CDC
	load_date timestamptz not null default now(), -- дата и время загрузки записи в DWH
	record_source text not null, -- источник записи: таблица, файл, API и т.д.
	source_system text not null, -- исходная система, откуда пришли данные
	batch_id bigint, -- идентификатор пакета загрузки
	operation_type text not null default 'I', -- тип операции: I - insert, U - update, D - delete
	raw_row_hash text -- хеш строки для проверки изменений
);

CREATE table if not exists raw.bookings (
	book_ref text ,
	book_date timestamptz ,
	total_amount numeric(10, 2),
	-- технические поля для аудита, lineage и имитации CDC
	load_date timestamptz not null default now(), -- дата и время загрузки записи в DWH
	record_source text not null, -- источник записи: таблица, файл, API и т.д.
	source_system text not null, -- исходная система, откуда пришли данные
	batch_id bigint, -- идентификатор пакета загрузки
	operation_type text not null default 'I', -- тип операции: I - insert, U - update, D - delete
	raw_row_hash text -- хеш строки для проверки изменений

);

CREATE table if not exists raw.flights (
	flight_id int4,
	route_no text ,
	status text,
	scheduled_departure timestamptz,
	scheduled_arrival timestamptz,
	actual_departure timestamptz,
	actual_arrival timestamptz,
	-- технические поля для аудита, lineage и имитации CDC
	load_date timestamptz not null default now(), -- дата и время загрузки записи в DWH
	record_source text not null, -- источник записи: таблица, файл, API и т.д.
	source_system text not null, -- исходная система, откуда пришли данные
	batch_id bigint, -- идентификатор пакета загрузки
	operation_type text not null default 'I', -- тип операции: I - insert, U - update, D - delete
	raw_row_hash text -- хеш строки для проверки изменений
);

CREATE table if not exists raw.routes (
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
	raw_row_hash text -- хеш строки для проверки изменений
);

CREATE table if not exists raw.seats (
	airplane_code text,
	seat_no text,
	fare_conditions text,
	-- технические поля для аудита, lineage и имитации CDC
	load_date timestamptz not null default now(), -- дата и время загрузки записи в DWH
	record_source text not null, -- источник записи: таблица, файл, API и т.д.
	source_system text not null, -- исходная система, откуда пришли данные
	batch_id bigint, -- идентификатор пакета загрузки
	operation_type text not null default 'I', -- тип операции: I - insert, U - update, D - delete
	raw_row_hash text -- хеш строки для проверки изменений
);

CREATE table if not exists raw.segments (
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
	raw_row_hash text -- хеш строки для проверки изменений
);

CREATE table if not exists raw.tickets (
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
	raw_row_hash text -- хеш строки для проверки изменений
);

	


