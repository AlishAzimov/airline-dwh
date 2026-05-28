
-- PK, FK, UNIQUE, CHECK, EXCLUDE

create table if not exists meta.source_constraints (
    constraint_id bigserial primary key,
    source_system text not null,
    source_schema text not null,
    table_name text not null,
    constraint_name text,
    constraint_type text not null,
    columns text not null,
    referenced_table text,
    referenced_columns text,
    rule_expression text,
    description text,
    created_at timestamptz not null default now()
);

truncate table meta.source_constraints;

insert into meta.source_constraints (
    source_system,
    source_schema,
    table_name,
    constraint_name,
    constraint_type,
    columns,
    referenced_table,
    referenced_columns,
    rule_expression,
    description
)
values
-- airplanes_data
('postgres_demo', 'bookings', 'airplanes_data', 'airplanes_data_pkey', 'PRIMARY KEY', 'airplane_code', null, null, null, 'Уникальный ключ самолёта'),
('postgres_demo', 'bookings', 'airplanes_data', 'airplanes_data_range_check', 'CHECK', 'range', null, null, 'range > 0', 'Дальность полёта должна быть больше нуля'),
('postgres_demo', 'bookings', 'airplanes_data', 'airplanes_data_speed_check', 'CHECK', 'speed', null, null, 'speed > 0', 'Крейсерская скорость должна быть больше нуля'),

-- airports_data
('postgres_demo', 'bookings', 'airports_data', 'airports_data_pkey', 'PRIMARY KEY', 'airport_code', null, null, null, 'Уникальный ключ аэропорта'),

-- boarding_passes
('postgres_demo', 'bookings', 'boarding_passes', 'boarding_passes_pkey', 'PRIMARY KEY', 'ticket_no, flight_id', null, null, null, 'Уникальный ключ посадочного талона'),
('postgres_demo', 'bookings', 'boarding_passes', 'boarding_passes_flight_boarding_no_key', 'UNIQUE', 'flight_id, boarding_no', null, null, null, 'Номер посадочного талона уникален в рамках рейса'),
('postgres_demo', 'bookings', 'boarding_passes', 'boarding_passes_flight_seat_no_key', 'UNIQUE', 'flight_id, seat_no', null, null, null, 'Одно место не может быть выдано двум пассажирам на одном рейсе'),
('postgres_demo', 'bookings', 'boarding_passes', 'boarding_passes_ticket_flight_fkey', 'FOREIGN KEY', 'ticket_no, flight_id', 'segments', 'ticket_no, flight_id', null, 'Посадочный талон связан с перелётом билета'),

-- bookings
('postgres_demo', 'bookings', 'bookings', 'bookings_pkey', 'PRIMARY KEY', 'book_ref', null, null, null, 'Уникальный ключ бронирования'),

-- flights
('postgres_demo', 'bookings', 'flights', 'flights_pkey', 'PRIMARY KEY', 'flight_id', null, null, null, 'Уникальный ключ рейса'),
('postgres_demo', 'bookings', 'flights', 'flights_route_departure_key', 'UNIQUE', 'route_no, scheduled_departure', null, null, null, 'Естественный ключ рейса: маршрут и плановая дата вылета'),
('postgres_demo', 'bookings', 'flights', 'flights_scheduled_arrival_check', 'CHECK', 'scheduled_arrival, scheduled_departure', null, null, 'scheduled_arrival > scheduled_departure', 'Плановое время прилёта должно быть позже планового времени вылета'),
('postgres_demo', 'bookings', 'flights', 'flights_actual_arrival_check', 'CHECK', 'actual_arrival, actual_departure', null, null, 'actual_arrival is null or actual_arrival > actual_departure', 'Фактическое время прилёта должно быть позже фактического времени вылета'),
('postgres_demo', 'bookings', 'flights', 'flights_status_check', 'CHECK', 'status', null, null, 'status in (Scheduled, On Time, Delayed, Boarding, Departed, Arrived, Cancelled)', 'Статус рейса должен входить в допустимый список'),

-- routes
('postgres_demo', 'bookings', 'routes', 'routes_temporal_exclude', 'EXCLUDE', 'route_no, validity', null, null, 'route_no with =, validity with &&', 'Для одного route_no интервалы validity не должны пересекаться'),
('postgres_demo', 'bookings', 'routes', 'routes_airplane_code_fkey', 'FOREIGN KEY', 'airplane_code', 'airplanes_data', 'airplane_code', null, 'Маршрут связан с самолётом'),
('postgres_demo', 'bookings', 'routes', 'routes_departure_airport_fkey', 'FOREIGN KEY', 'departure_airport', 'airports_data', 'airport_code', null, 'Маршрут связан с аэропортом отправления'),
('postgres_demo', 'bookings', 'routes', 'routes_arrival_airport_fkey', 'FOREIGN KEY', 'arrival_airport', 'airports_data', 'airport_code', null, 'Маршрут связан с аэропортом прибытия'),

-- seats
('postgres_demo', 'bookings', 'seats', 'seats_pkey', 'PRIMARY KEY', 'airplane_code, seat_no', null, null, null, 'Уникальный ключ места в самолёте'),
('postgres_demo', 'bookings', 'seats', 'seats_fare_conditions_check', 'CHECK', 'fare_conditions', null, null, 'fare_conditions in (Economy, Comfort, Business)', 'Класс обслуживания должен входить в допустимый список'),
('postgres_demo', 'bookings', 'seats', 'seats_airplane_code_fkey', 'FOREIGN KEY', 'airplane_code', 'airplanes_data', 'airplane_code', null, 'Место связано с самолётом'),

-- segments
('postgres_demo', 'bookings', 'segments', 'segments_pkey', 'PRIMARY KEY', 'ticket_no, flight_id', null, null, null, 'Уникальный ключ перелёта в билете'),
('postgres_demo', 'bookings', 'segments', 'segments_price_check', 'CHECK', 'price', null, null, 'price >= 0', 'Стоимость перелёта не может быть отрицательной'),
('postgres_demo', 'bookings', 'segments', 'segments_fare_conditions_check', 'CHECK', 'fare_conditions', null, null, 'fare_conditions in (Economy, Comfort, Business)', 'Класс обслуживания должен входить в допустимый список'),
('postgres_demo', 'bookings', 'segments', 'segments_ticket_no_fkey', 'FOREIGN KEY', 'ticket_no', 'tickets', 'ticket_no', null, 'Перелёт связан с билетом'),
('postgres_demo', 'bookings', 'segments', 'segments_flight_id_fkey', 'FOREIGN KEY', 'flight_id', 'flights', 'flight_id', null, 'Перелёт связан с рейсом'),

-- tickets
('postgres_demo', 'bookings', 'tickets', 'tickets_pkey', 'PRIMARY KEY', 'ticket_no', null, null, null, 'Уникальный ключ билета'),
('postgres_demo', 'bookings', 'tickets', 'tickets_book_ref_passenger_outbound_key', 'UNIQUE', 'book_ref, passenger_id, outbound', null, null, null, 'Один пассажир не может иметь два одинаковых билета одного направления в рамках одного бронирования'),
('postgres_demo', 'bookings', 'tickets', 'tickets_book_ref_fkey', 'FOREIGN KEY', 'book_ref', 'bookings', 'book_ref', null, 'Билет связан с бронированием');


--------------------------

-- обычные индексы

create table if not exists meta.source_indexes (
    index_id bigserial primary key,
    source_system text not null,
    source_schema text not null,
    table_name text not null,
    index_name text not null,
    index_type text,
    columns text not null,
    is_unique boolean not null default false,
    description text,
    created_at timestamptz not null default now()
);

truncate table meta.source_indexes;

insert into meta.source_indexes (
    source_system,
    source_schema,
    table_name,
    index_name,
    index_type,
    columns,
    is_unique,
    description
)
values
-- airplanes_data
('postgres_demo', 'bookings', 'airplanes_data', 'airplanes_data_pkey_idx', 'btree', 'airplane_code', true, 'Индекс первичного ключа самолётов'),

-- airports_data
('postgres_demo', 'bookings', 'airports_data', 'airports_data_pkey_idx', 'btree', 'airport_code', true, 'Индекс первичного ключа аэропортов'),

-- boarding_passes
('postgres_demo', 'bookings', 'boarding_passes', 'boarding_passes_pkey_idx', 'btree', 'ticket_no, flight_id', true, 'Индекс первичного ключа посадочных талонов'),
('postgres_demo', 'bookings', 'boarding_passes', 'boarding_passes_flight_boarding_no_idx', 'btree', 'flight_id, boarding_no', true, 'Уникальный индекс номера посадочного талона в рамках рейса'),
('postgres_demo', 'bookings', 'boarding_passes', 'boarding_passes_flight_seat_no_idx', 'btree', 'flight_id, seat_no', true, 'Уникальный индекс места в рамках рейса'),

-- bookings
('postgres_demo', 'bookings', 'bookings', 'bookings_pkey_idx', 'btree', 'book_ref', true, 'Индекс первичного ключа бронирований'),

-- flights
('postgres_demo', 'bookings', 'flights', 'flights_pkey_idx', 'btree', 'flight_id', true, 'Индекс первичного ключа рейсов'),
('postgres_demo', 'bookings', 'flights', 'flights_route_departure_idx', 'btree', 'route_no, scheduled_departure', true, 'Уникальный индекс естественного ключа рейса'),

-- routes
('postgres_demo', 'bookings', 'routes', 'routes_departure_airport_lower_validity_idx', 'btree', 'departure_airport, lower(validity)', false, 'Индекс для поиска маршрутов по аэропорту отправления и началу периода действия'),
('postgres_demo', 'bookings', 'routes', 'routes_temporal_exclude_idx', 'gist', 'route_no, validity', true, 'GiST-индекс для ограничения пересечения интервалов validity по route_no'),

-- seats
('postgres_demo', 'bookings', 'seats', 'seats_pkey_idx', 'btree', 'airplane_code, seat_no', true, 'Индекс первичного ключа мест'),

-- segments
('postgres_demo', 'bookings', 'segments', 'segments_pkey_idx', 'btree', 'ticket_no, flight_id', true, 'Индекс первичного ключа перелётов'),
('postgres_demo', 'bookings', 'segments', 'segments_flight_id_idx', 'btree', 'flight_id', false, 'Индекс для поиска перелётов по рейсу'),

-- tickets
('postgres_demo', 'bookings', 'tickets', 'tickets_pkey_idx', 'btree', 'ticket_no', true, 'Индекс первичного ключа билетов'),
('postgres_demo', 'bookings', 'tickets', 'tickets_book_ref_passenger_outbound_idx', 'btree', 'book_ref, passenger_id, outbound', true, 'Уникальный индекс пассажира и направления внутри бронирования');


