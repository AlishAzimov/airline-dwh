--------------------------------------------------------------------------------------------------------
-- Создание процедур слоя DDS: загрузка Фактов рейсов из ODS в DDS --
--------------------------------------------------------------------------------------------------------


-- Процедура I/U/D: вставка новых и обновление рейсов
create or replace procedure dds.upsert_fact_flights_from_ods()
language plpgsql
as $$

declare
    v_last_loaded_batch_id bigint;

begin

    select coalesce(max(batch_id), 0)
    into v_last_loaded_batch_id
    from dds.fact_flights;

insert into dds.fact_flights(
 		flight_sk,
		route_sk,
		flight_id,
		status,
		scheduled_departure,
		scheduled_arrival,
		actual_departure,
		actual_arrival,
	    source_system,     
	    record_source,     
	    batch_id , 
	    last_changed_at, 
	    is_deleted
		)
	select 
		md5(o.flight_id::text || '|' || o.source_system)::uuid as flight_sk,
		r.route_sk as route_sk,
		o.flight_id,
		o.status,
		o.scheduled_departure,
		o.scheduled_arrival,
		o.actual_departure,
		o.actual_arrival,
	    o.source_system, 
	    o.record_source,    
	    o.updated_batch_id as batch_id, 
	    now() as last_changed_at, 
	    o.is_deleted 
	from ods.flights o
		join dds.dim_routes r 
			on o.route_no=r.route_no
			and o.scheduled_departure <@ r.validity	
	where o.updated_batch_id > v_last_loaded_batch_id
	
	on conflict (flight_id) do update
    set
		route_sk = excluded.route_sk,
		status = excluded.status,
		scheduled_departure = excluded.scheduled_departure,
		scheduled_arrival = excluded.scheduled_arrival,
		actual_departure = excluded.actual_departure,
		actual_arrival = excluded.actual_arrival,
	    source_system = excluded.source_system,     
	    record_source = excluded.record_source,     
	    batch_id = excluded.batch_id, 
	    last_changed_at= now(), 
	    is_deleted = excluded.is_deleted;

end;
$$;

-- Главная сборочная процедура

create or replace procedure dds.load_fact_flights_from_ods()
language plpgsql
as $$
declare
    v_step_started_at timestamptz;
begin
    v_step_started_at := clock_timestamp();

    call dds.upsert_fact_flights_from_ods();

    raise notice 'dds.upsert_fact_flights_from_ods duration: %',
        clock_timestamp() - v_step_started_at;

    raise notice 'dds.fact_flights loaded. rows = %, active rows = %, deleted rows = %',
        (select count(*) from dds.fact_flights),
        (select count(*) from dds.fact_flights where is_deleted = false),
        (select count(*) from dds.fact_flights where is_deleted = true);
end;
$$;