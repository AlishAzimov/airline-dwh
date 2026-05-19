-- Создание слоев DWH для airline DWH

create schema if not exists raw;
create schema if not exists stg;
create schema if not exists ods;
create schema if not exists dds;
create schema if not exists dm;
create schema if not exists dq;
create schema if not exists meta;