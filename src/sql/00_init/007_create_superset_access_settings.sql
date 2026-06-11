--------------------------------------------------------------------------------------------------------
-- Настройка пользователя БД для Superset: доступ только на чтение к DM-витринам --
--------------------------------------------------------------------------------------------------------

create user superset_user with password '1654890102';

grant connect on database postgres to superset_user;

grant usage on schema dm to superset_user;

grant select on all tables in schema dm to superset_user;

alter default privileges in schema dm
grant select on tables to superset_user;




create index if not exists ix_dm_flight_sales_mart_fare_ticket
on dm.flight_sales_mart (fare_conditions, ticket_no);

create index if not exists ix_dm_flight_sales_mart_book_date
on dm.flight_sales_mart (book_date);

create index if not exists ix_dm_flight_sales_mart_route_no
on dm.flight_sales_mart (route_no);

analyze dm.flight_sales_mart;
