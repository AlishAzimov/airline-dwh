--------------------------------------------------------------------------
-- Первичное заполнение raw.routes данными из источника в RAW-слой --
--------------------------------------------------------------------------

create or replace procedure raw.load_routes_initial()
language plpgsql
as $$
declare
	v_batch_id bigint;

begin

-- Создаем запись о запуске загрузки и получаем batch_id

 v_batch_id := meta.start_batch('raw.load_routes_initial');

-- Загружаем данные из source_fdw.routes в raw.routes
	insert
	into
	raw.routes(
		route_no,
		validity,
		departure_airport,
		arrival_airport,
		airplane_code,
		days_of_week,
		scheduled_time,
		duration,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		r.route_no,
		r.validity,
		r.departure_airport,
		r.arrival_airport,
		r.airplane_code,
		r.days_of_week,
		r.scheduled_time,
		r.duration,
		'demo.bookings.routes',
		'postgres_demo',
		v_batch_id,
		'I',
		md5(
    		concat_ws('|',
	        coalesce(r.route_no, ''),
	        coalesce(r.validity::text, ''),
	        coalesce(r.departure_airport, ''),
	        coalesce(r.arrival_airport, ''),
			coalesce(r.airplane_code, ''),
			coalesce(r.days_of_week::text, ''),
			coalesce(r.scheduled_time::text, ''),
			coalesce(r.duration::text, '')
    			)
			)
	from
		source_fdw.routes r;

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
-- Первичное заполнение raw.routes_snapshot данными из источника --
--------------------------------------------------------------------------

create or replace procedure raw.init_routes_snapshot()
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
	raw.routes_snapshot;

	if v_snapshot_count = 0 then
		insert
		into
			raw.routes_snapshot(
			route_no,
			validity,
			departure_airport,
			arrival_airport,
			airplane_code,
			days_of_week,
			scheduled_time,
			duration,
			raw_row_hash)
		select
			r.route_no,
			r.validity,
			r.departure_airport,
			r.arrival_airport,
			r.airplane_code,
			r.days_of_week,
			r.scheduled_time,
			r.duration,
			md5(
    		concat_ws('|',
	        coalesce(r.route_no, ''),
	        coalesce(r.validity::text, ''),
	        coalesce(r.departure_airport, ''),
	        coalesce(r.arrival_airport, ''),
			coalesce(r.airplane_code, ''),
			coalesce(r.days_of_week::text, ''),
			coalesce(r.scheduled_time::text, ''),
			coalesce(r.duration::text, '')
    			)
			)
	from
			source_fdw.routes r;

	else 
		 raise notice 'raw.routes_snapshot is not empty. Initialization skipped.';
	end if;

end;
$$;

--------------------------------------------------------------------------
-- Delta-загрузка routes в RAW через snapshot CDC imitation --
--------------------------------------------------------------------------

-- Подготовка временного снимка данных source_fdw.routes для расчёта delta

create or replace procedure raw.prepare_routes_delta_source()
language plpgsql
as $$
begin
	
	drop table if exists tmp_source_routes;
	
	create temp table tmp_source_routes
	on commit drop
	as
		select
			r.route_no,
			r.validity,
			r.departure_airport,
			r.arrival_airport,
			r.airplane_code,
			r.days_of_week,
			r.scheduled_time,
			r.duration,
			md5(
    		concat_ws('|',
	        coalesce(r.route_no, ''),
	        coalesce(r.validity::text, ''),
	        coalesce(r.departure_airport, ''),
	        coalesce(r.arrival_airport, ''),
			coalesce(r.airplane_code, ''),
			coalesce(r.days_of_week::text, ''),
			coalesce(r.scheduled_time::text, ''),
			coalesce(r.duration::text, '')
    			)
			) as raw_row_hash
	from
			source_fdw.routes r;
	
--create index idx_tmp_source_routes_book_ref
--on tmp_source_routes(book_ref);
--
--analyze tmp_source_routes;

end;
$$;


-- Поиск новых строк: I

create or replace procedure raw.insert_routes_delta_i(p_batch_id bigint)
language plpgsql
as $$
begin 
	insert
	into
	raw.routes(
		route_no,
		validity,
		departure_airport,
		arrival_airport,
		airplane_code,
		days_of_week,
		scheduled_time,
		duration,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		src.route_no,
		src.validity,
		src.departure_airport,
		src.arrival_airport,
		src.airplane_code,
		src.days_of_week,
		src.scheduled_time,
		src.duration,
		'demo.bookings.routes',
		'postgres_demo',
		p_batch_id,
		'I',
		src.raw_row_hash
	
	from
		tmp_source_routes src
    left join raw.routes_snapshot sp on src.route_no = sp.route_no and src.validity=sp.validity

    where sp.route_no is null
	and sp.validity is null;

end;
$$;


-- Изменённые строки: U

create or replace procedure raw.insert_routes_delta_u(p_batch_id bigint)
language plpgsql
as $$
begin 
	insert
	into
	raw.routes(
		route_no,
		validity,
		departure_airport,
		arrival_airport,
		airplane_code,
		days_of_week,
		scheduled_time,
		duration,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		src.route_no,
		src.validity,
		src.departure_airport,
		src.arrival_airport,
		src.airplane_code,
		src.days_of_week,
		src.scheduled_time,
		src.duration,
		'demo.bookings.routes',
		'postgres_demo',
		p_batch_id,
		'U',
		src.raw_row_hash
	from
		tmp_source_routes src
    join raw.routes_snapshot sp on src.route_no = sp.route_no and src.validity=sp.validity
    where src.raw_row_hash!=sp.raw_row_hash;

end;
$$;


-- Удаленные строки: D

create or replace procedure raw.insert_routes_delta_d(p_batch_id bigint)
language plpgsql
as $$
begin 

	insert
	into
	raw.routes(
		route_no,
		validity,
		departure_airport,
		arrival_airport,
		airplane_code,
		days_of_week,
		scheduled_time,
		duration,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		sp.route_no,
		sp.validity,
		sp.departure_airport,
		sp.arrival_airport,
		sp.airplane_code,
		sp.days_of_week,
		sp.scheduled_time,
		sp.duration,
		'demo.bookings.routes',
		'postgres_demo',
		p_batch_id,
		'D',
		sp.raw_row_hash
	from
		raw.routes_snapshot sp
    left join tmp_source_routes src on sp.route_no = src.route_no and sp.validity=src.validity
    where src.route_no is null
	and src.validity is null;
end;
$$;


-- Обнавление routes_snapshot

--create or replace procedure raw.refresh_routes_snapshot()
--language plpgsql
--as $$
--begin
--	
--	truncate table raw.routes_snapshot;
--	
--	insert
--	into
--		raw.routes_snapshot(
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
--	from tmp_source_routes src;
--	
--end;
--$$;

create or replace procedure raw.refresh_routes_snapshot()
language plpgsql
as $$
begin
	
	drop table raw.routes_snapshot;
	

create table raw.routes_snapshot as

	select
		src.route_no,
		src.validity,
		src.departure_airport,
		src.arrival_airport,
		src.airplane_code,
		src.days_of_week,
		src.scheduled_time,
		src.duration,
		src.raw_row_hash
	from tmp_source_routes src;
	
end;
$$;


--Главная сборочная процедура, которая последовательно запускает все delta-процедуры для routes и фиксирует время выполнения каждого этапа --

create or replace procedure raw.load_routes_delta()
language plpgsql
as $$
declare
    v_batch_id bigint;
    v_step_started_at timestamptz;
begin
    v_batch_id := meta.start_batch('raw.load_routes_delta');

    v_step_started_at := clock_timestamp();
    call raw.prepare_routes_delta_source();
    raise notice 'prepare_routes_delta_source duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.insert_routes_delta_i(v_batch_id);
    raise notice 'insert_routes_delta_i duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.insert_routes_delta_u(v_batch_id);
    raise notice 'insert_routes_delta_u duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.insert_routes_delta_d(v_batch_id);
    raise notice 'insert_routes_delta_d duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.refresh_routes_snapshot();
    raise notice 'refresh_routes_snapshot duration: %',
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

call raw.load_routes_initial();

select * from raw.routes order by route_no desc limit 15

call raw.init_routes_snapshot()

select * from raw.routes_snapshot order by route_no desc limit 10

insert into 
	source_fdw.routes(
	 	route_no,
		validity,
		departure_airport,
		arrival_airport,
		airplane_code,
		days_of_week,
		scheduled_time,
		duration)
values ('PG1800',
		'["2027-10-01 05:00:00+05","2027-11-01 05:00:00+05")'::tstzrange, 
		'DEN', 
		'ARN', 
		'789',
		array[1, 3, 5],
		'00:07:00',
		 interval '7 hours'
		);


update source_fdw.routes
set 
	days_of_week=array[1, 3, 5]
where route_no='PG1792' and validity = '["2027-10-01 05:00:00+05","2027-11-01 05:00:00+05")'::tstzrange;

delete from source_fdw.routes
where route_no='PG1797' and validity = '["2027-10-01 05:00:00+05","2027-11-01 05:00:00+05")'::tstzrange;


call raw.load_routes_delta()
