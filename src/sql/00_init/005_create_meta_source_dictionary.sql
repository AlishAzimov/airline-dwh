
-- Таблица-словарь источника

create table if not exists meta.source_dictionary (
    dictionary_id bigserial primary key,
    source_system text not null,
    source_schema text not null,
    object_name text not null,
    object_type text not null,
    column_name text,
    data_type text,
    is_nullable text,
    description text,
    created_at timestamptz not null default now()
);

truncate table meta.source_dictionary;

insert into meta.source_dictionary (
    source_system,
    source_schema,
    object_name,
    object_type,
    column_name,
    data_type,
    is_nullable,
    description
)
values
-- airplanes_data
('postgres_demo', 'bookings', 'airplanes_data', 'table', null, null, null, 'Самолёты с переводами моделей'),
('postgres_demo', 'bookings', 'airplanes_data', 'table', 'airplane_code', 'char(3)', 'not null', 'Код самолёта, ИАТА'),
('postgres_demo', 'bookings', 'airplanes_data', 'table', 'model', 'jsonb', 'not null', 'Модель самолёта на разных языках'),
('postgres_demo', 'bookings', 'airplanes_data', 'table', 'range', 'integer', 'not null', 'Максимальная дальность полёта, км'),
('postgres_demo', 'bookings', 'airplanes_data', 'table', 'speed', 'integer', 'not null', 'Крейсерская скорость, км/ч'),

-- airports_data
('postgres_demo', 'bookings', 'airports_data', 'table', null, null, null, 'Аэропорты с переводами названий, городов и стран'),
('postgres_demo', 'bookings', 'airports_data', 'table', 'airport_code', 'char(3)', 'not null', 'Код аэропорта, ИАТА'),
('postgres_demo', 'bookings', 'airports_data', 'table', 'airport_name', 'jsonb', 'not null', 'Название аэропорта на разных языках'),
('postgres_demo', 'bookings', 'airports_data', 'table', 'city', 'jsonb', 'not null', 'Город на разных языках'),
('postgres_demo', 'bookings', 'airports_data', 'table', 'country', 'jsonb', 'not null', 'Страна на разных языках'),
('postgres_demo', 'bookings', 'airports_data', 'table', 'coordinates', 'point', 'not null', 'Координаты аэропорта'),
('postgres_demo', 'bookings', 'airports_data', 'table', 'timezone', 'text', 'not null', 'Часовой пояс аэропорта'),

-- boarding_passes
('postgres_demo', 'bookings', 'boarding_passes', 'table', null, null, null, 'Посадочные талоны'),
('postgres_demo', 'bookings', 'boarding_passes', 'table', 'ticket_no', 'text', 'not null', 'Номер билета'),
('postgres_demo', 'bookings', 'boarding_passes', 'table', 'flight_id', 'integer', 'not null', 'Идентификатор рейса'),
('postgres_demo', 'bookings', 'boarding_passes', 'table', 'seat_no', 'text', 'not null', 'Номер места'),
('postgres_demo', 'bookings', 'boarding_passes', 'table', 'boarding_no', 'integer', null, 'Номер посадочного талона'),
('postgres_demo', 'bookings', 'boarding_passes', 'table', 'boarding_time', 'timestamptz', null, 'Время посадки'),

-- bookings
('postgres_demo', 'bookings', 'bookings', 'table', null, null, null, 'Бронирования'),
('postgres_demo', 'bookings', 'bookings', 'table', 'book_ref', 'char(6)', 'not null', 'Номер бронирования'),
('postgres_demo', 'bookings', 'bookings', 'table', 'book_date', 'timestamptz', 'not null', 'Дата бронирования'),
('postgres_demo', 'bookings', 'bookings', 'table', 'total_amount', 'numeric(10,2)', 'not null', 'Полная сумма бронирования'),

-- flights
('postgres_demo', 'bookings', 'flights', 'table', null, null, null, 'Рейсы'),
('postgres_demo', 'bookings', 'flights', 'table', 'flight_id', 'integer', 'not null', 'Идентификатор рейса'),
('postgres_demo', 'bookings', 'flights', 'table', 'route_no', 'text', 'not null', 'Номер маршрута'),
('postgres_demo', 'bookings', 'flights', 'table', 'status', 'text', 'not null', 'Статус рейса'),
('postgres_demo', 'bookings', 'flights', 'table', 'scheduled_departure', 'timestamptz', 'not null', 'Время вылета по расписанию'),
('postgres_demo', 'bookings', 'flights', 'table', 'scheduled_arrival', 'timestamptz', 'not null', 'Время прилёта по расписанию'),
('postgres_demo', 'bookings', 'flights', 'table', 'actual_departure', 'timestamptz', null, 'Фактическое время вылета'),
('postgres_demo', 'bookings', 'flights', 'table', 'actual_arrival', 'timestamptz', null, 'Фактическое время прилёта'),

-- routes
('postgres_demo', 'bookings', 'routes', 'table', null, null, null, 'Маршруты'),
('postgres_demo', 'bookings', 'routes', 'table', 'route_no', 'text', 'not null', 'Номер маршрута'),
('postgres_demo', 'bookings', 'routes', 'table', 'validity', 'tstzrange', 'not null', 'Период действия маршрута'),
('postgres_demo', 'bookings', 'routes', 'table', 'departure_airport', 'char(3)', 'not null', 'Аэропорт отправления'),
('postgres_demo', 'bookings', 'routes', 'table', 'arrival_airport', 'char(3)', 'not null', 'Аэропорт прибытия'),
('postgres_demo', 'bookings', 'routes', 'table', 'airplane_code', 'char(3)', 'not null', 'Код самолёта, ИАТА'),
('postgres_demo', 'bookings', 'routes', 'table', 'days_of_week', 'integer[]', 'not null', 'Дни недели выполнения рейсов'),
('postgres_demo', 'bookings', 'routes', 'table', 'scheduled_time', 'time', 'not null', 'Местное время вылета по расписанию'),
('postgres_demo', 'bookings', 'routes', 'table', 'duration', 'interval', 'not null', 'Планируемая длительность полёта'),

-- seats
('postgres_demo', 'bookings', 'seats', 'table', null, null, null, 'Места в самолётах'),
('postgres_demo', 'bookings', 'seats', 'table', 'airplane_code', 'char(3)', 'not null', 'Код самолёта, ИАТА'),
('postgres_demo', 'bookings', 'seats', 'table', 'seat_no', 'text', 'not null', 'Номер места'),
('postgres_demo', 'bookings', 'seats', 'table', 'fare_conditions', 'text', 'not null', 'Класс обслуживания'),

-- segments
('postgres_demo', 'bookings', 'segments', 'table', null, null, null, 'Перелёты по билетам'),
('postgres_demo', 'bookings', 'segments', 'table', 'ticket_no', 'text', 'not null', 'Номер билета'),
('postgres_demo', 'bookings', 'segments', 'table', 'flight_id', 'integer', 'not null', 'Идентификатор рейса'),
('postgres_demo', 'bookings', 'segments', 'table', 'fare_conditions', 'text', 'not null', 'Класс обслуживания'),
('postgres_demo', 'bookings', 'segments', 'table', 'price', 'numeric(10,2)', 'not null', 'Стоимость перелёта'),

-- tickets
('postgres_demo', 'bookings', 'tickets', 'table', null, null, null, 'Билеты'),
('postgres_demo', 'bookings', 'tickets', 'table', 'ticket_no', 'text', 'not null', 'Номер билета'),
('postgres_demo', 'bookings', 'tickets', 'table', 'book_ref', 'char(6)', 'not null', 'Номер бронирования'),
('postgres_demo', 'bookings', 'tickets', 'table', 'passenger_id', 'text', 'not null', 'Номер документа пассажира'),
('postgres_demo', 'bookings', 'tickets', 'table', 'passenger_name', 'text', 'not null', 'Полное имя пассажира'),
('postgres_demo', 'bookings', 'tickets', 'table', 'outbound', 'boolean', 'not null', 'Признак прямого билета');