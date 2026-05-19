-- FDW-подключение к SOURCE-базе demo
-- Нужно для загрузки данных из demo.bookings в RAW-слой airline_dwh

create extension if not exists postgres_fdw;

create schema if not exists source_fdw;

create server if not exists demo_source_server
foreign data wrapper postgres_fdw
options (
    host 'localhost',
    port '5432',
    dbname 'demo'
);

-- Создание пользователя и правв для пользователя в SOURCE базе
--
--create user dwh with password '*******';
--
--grant connect on database demo to dwh;
--
--grant usage on schema bookings to dwh;
--
--grant select on all tables in schema bookings to dwh;

drop user mapping if exists for current_user server demo_source_server;

create user mapping if not exists for current_user
server demo_source_server
options (
    user 'dwh',
    password '******'
);

import foreign schema bookings
limit to (
    bookings,
    tickets,
    segments,
    boarding_passes,
    flights,
    routes,
    airports_data,
    airplanes_data,
    seats
)
from server demo_source_server
into source_fdw;


--select *
--from source_fdw.tickets t
--limit 5;
