--------------------------------------------------------------------------
-- Первичное заполнение raw.flights данными из источника в RAW-слой --
--------------------------------------------------------------------------

create or replace procedure raw.load_flights_initial()
language plpgsql
as $$
declare
	v_batch_id bigint;

begin

-- Создаем запись о запуске загрузки и получаем batch_id

 v_batch_id := meta.start_batch('raw.load_flights_initial');

-- Загружаем данные из source_fdw.flights в raw.flights
	insert
	into
	raw.flights(
		flight_id,
		route_no,
		status,
		scheduled_departure,
		scheduled_arrival,
		actual_departure,
		actual_arrival,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		f.flight_id,
		f.route_no,
		f.status,
		f.scheduled_departure,
		f.scheduled_arrival,
		f.actual_departure,
		f.actual_arrival,
		'demo.bookings.flights',
		'postgres_demo',
		v_batch_id,
		'I',
		md5(
    		concat_ws('|',
	        coalesce(f.flight_id::text, ''),
	        coalesce(f.route_no, ''),
	        coalesce(f.status, ''),
	        coalesce(f.scheduled_departure::text, ''),
			coalesce(f.scheduled_arrival::text, ''),
			coalesce(f.actual_departure::text, ''),
			coalesce(f.actual_arrival::text, '')
    			)
			)
	from
		source_fdw.flights f;

-- Фиксируем успешное завершение загрузки

	call meta.finish_batch(v_batch_id);

-- Обрабокта ошибки
exception
	when others then
		call meta.fail_batch(v_batch_id, sqlerrm);
	raise;
end;
$$;

--------------------------------------------------------------------------
-- Первичное заполнение raw.flights_snapshot данными из источника --
--------------------------------------------------------------------------

create or replace procedure raw.init_flights_snapshot()
language plpgsql
as $$
declare	
	v_snapshot_count bigint;

begin
	
select
	count(*)
into
	v_snapshot_count
from
	raw.flights_snapshot;

	if v_snapshot_count = 0 then
		insert
		into
			raw.flights_snapshot(
			flight_id,
			route_no,
			status,
			scheduled_departure,
			scheduled_arrival,
			actual_departure,
			actual_arrival,
			raw_row_hash)
		select
			f.flight_id,
			f.route_no,
			f.status,
			f.scheduled_departure,
			f.scheduled_arrival,
			f.actual_departure,
			f.actual_arrival,
			md5(
    		concat_ws('|',
	        coalesce(f.flight_id::text, ''),
	        coalesce(f.route_no, ''),
	        coalesce(f.status, ''),
	        coalesce(f.scheduled_departure::text, ''),
			coalesce(f.scheduled_arrival::text, ''),
			coalesce(f.actual_departure::text, ''),
			coalesce(f.actual_arrival::text, '')
    			)
			)
	from
			source_fdw.flights f;

	else 
		 raise notice 'raw.flights_snapshot is not empty. Initialization skipped.';
	end if;

end;
$$;

--------------------------------------------------------------------------
-- Delta-загрузка flights в RAW через snapshot CDC imitation --
--------------------------------------------------------------------------

-- Подготовка временного снимка данных source_fdw.flights для расчёта delta

create or replace procedure raw.prepare_flights_delta_source()
language plpgsql
as $$
begin
	
	drop table if exists tmp_source_flights;
	
	create temp table tmp_source_flights
	on commit drop
	as
		select
			f.flight_id,
			f.route_no,
			f.status,
			f.scheduled_departure,
			f.scheduled_arrival,
			f.actual_departure,
			f.actual_arrival,
			md5(
    		concat_ws('|',
	        coalesce(f.flight_id::text, ''),
	        coalesce(f.route_no, ''),
	        coalesce(f.status, ''),
	        coalesce(f.scheduled_departure::text, ''),
			coalesce(f.scheduled_arrival::text, ''),
			coalesce(f.actual_departure::text, ''),
			coalesce(f.actual_arrival::text, '')
    			)
			) as raw_row_hash
		from source_fdw.flights f;
	
--create index idx_tmp_source_flights_book_ref
--on tmp_source_flights(book_ref);
--
--analyze tmp_source_flights;

end;
$$;


-- Поиск новых строк: I

create or replace procedure raw.insert_flights_delta_i(p_batch_id bigint)
language plpgsql
as $$
begin 
	insert
	into
	raw.flights(
		flight_id,
		route_no,
		status,
		scheduled_departure,
		scheduled_arrival,
		actual_departure,
		actual_arrival,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		src.flight_id,
		src.route_no,
		src.status,
		src.scheduled_departure,
		src.scheduled_arrival,
		src.actual_departure,
		src.actual_arrival,
		'demo.bookings.flights',
		'postgres_demo',
		p_batch_id,
		'I',
		src.raw_row_hash
	
	from
		tmp_source_flights src
    left join raw.flights_snapshot sp on src.flight_id = sp.flight_id
    where sp.flight_id is null;

end;
$$;


-- Изменённые строки: U

create or replace procedure raw.insert_flights_delta_u(p_batch_id bigint)
language plpgsql
as $$
begin 
	insert
	into
		raw.flights(
		flight_id,
		route_no,
		status,
		scheduled_departure,
		scheduled_arrival,
		actual_departure,
		actual_arrival,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		src.flight_id,
		src.route_no,
		src.status,
		src.scheduled_departure,
		src.scheduled_arrival,
		src.actual_departure,
		src.actual_arrival,
		'demo.bookings.flights',
		'postgres_demo',
		p_batch_id,
		'U',
		src.raw_row_hash
	from
		tmp_source_flights src
    join raw.flights_snapshot sp on src.flight_id = sp.flight_id 
    where src.raw_row_hash!=sp.raw_row_hash;

end;
$$;


-- Удаленные строки: D

create or replace procedure raw.insert_flights_delta_d(p_batch_id bigint)
language plpgsql
as $$
begin 

	insert
	into
		raw.flights(
		flight_id,
		route_no,
		status,
		scheduled_departure,
		scheduled_arrival,
		actual_departure,
		actual_arrival,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		sp.flight_id,
		sp.route_no,
		sp.status,
		sp.scheduled_departure,
		sp.scheduled_arrival,
		sp.actual_departure,
		sp.actual_arrival,
		'demo.bookings.flights',
		'postgres_demo',
		p_batch_id,
		'D',
		sp.raw_row_hash
	from
		raw.flights_snapshot sp
    left join tmp_source_flights src on sp.flight_id = src.flight_id
    where src.flight_id is null;
end;
$$;


-- Обнавление flights_snapshot

--create or replace procedure raw.refresh_flights_snapshot()
--language plpgsql
--as $$
--begin
--	
--	truncate table raw.flights_snapshot;
--	
--	insert
--	into
--		raw.flights_snapshot(
--		ticket_no,
--		book_ref,
--		passenger_id,
--		passenger_name,
--		outbound,
--		raw_row_hash)
--	select
--		src.ticket_no,
--		src.book_ref,
--		src.passenger_id,
--		src.passenger_name,
--		src.outbound,
--		src.raw_row_hash
--	from tmp_source_flights src;
--	
--end;
--$$;

create or replace procedure raw.refresh_flights_snapshot()
language plpgsql
as $$
begin
	
	drop table raw.flights_snapshot;
	

create table raw.flights_snapshot as

	select
		src.flight_id,
		src.route_no,
		src.status,
		src.scheduled_departure,
		src.scheduled_arrival,
		src.actual_departure,
		src.actual_arrival,
		src.raw_row_hash,
		now() as last_seen_at
	from tmp_source_flights src;
	
end;
$$;


--Главная сборочная процедура, которая последовательно запускает все delta-процедуры для flights и фиксирует время выполнения каждого этапа --

create or replace procedure raw.load_flights_delta()
language plpgsql
as $$
declare
    v_batch_id bigint;
    v_step_started_at timestamptz;
begin
    v_batch_id := meta.start_batch('raw.load_flights_delta');

    v_step_started_at := clock_timestamp();
    call raw.prepare_flights_delta_source();
    raise notice 'prepare_flights_delta_source duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.insert_flights_delta_i(v_batch_id);
    raise notice 'insert_flights_delta_i duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.insert_flights_delta_u(v_batch_id);
    raise notice 'insert_flights_delta_u duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.insert_flights_delta_d(v_batch_id);
    raise notice 'insert_flights_delta_d duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.refresh_flights_snapshot();
    raise notice 'refresh_flights_snapshot duration: %',
        clock_timestamp() - v_step_started_at;

    call meta.finish_batch(v_batch_id);

exception
    when others then
        call meta.fail_batch(v_batch_id, sqlerrm);
        raise;
end;
$$;





----------------------
-- test

call raw.load_flights_initial();

select * from raw.flights order by flight_id desc limit 15

call raw.init_flights_snapshot()

select * from raw.flights_snapshot order by flight_id desc limit 10

insert into 
	source_fdw.flights(
	 	flight_id,
		route_no,
		status,
		scheduled_departure,
		scheduled_arrival,
		actual_departure,
		actual_arrival)
overriding system value
values (135580,'PG0011', 'Departed', now() - interval '10 hours', now(),now() - interval '10 hours', now());


update source_fdw.flights
set 
	status='Boarding'
where flight_id=135563

delete from source_fdw.flights
where flight_id=135567

select * from source_fdw.flights order by ticket_no desc limit 15


call raw.load_flights_delta()