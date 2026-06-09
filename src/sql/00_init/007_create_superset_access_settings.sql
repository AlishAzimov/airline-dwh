--------------------------------------------------------------------------------------------------------
-- Настройка пользователя БД для Superset: доступ только на чтение к DM-витринам --
--------------------------------------------------------------------------------------------------------

create user superset_user with password 'superset_password';

grant connect on database postgres to superset_user;

grant usage on schema dm to superset_user;

grant select on all tables in schema dm to superset_user;

alter default privileges in schema dm
grant select on tables to superset_user;


