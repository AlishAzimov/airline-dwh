--------------------------------------------------------------------------
-- Первичное заполнение raw.segments данными из источника в RAW-слой --
--------------------------------------------------------------------------

create or replace procedure raw.load_segments_initial()
language plpgsql
as $$
declare
	v_batch_id bigint;

begin

-- Создаем запись о запуске загрузки и получаем batch_id

 v_batch_id := meta.start_batch('raw.load_segments_initial');

-- Загружаем данные из source_fdw.segments в raw.segments
	insert
	into
	raw.segments(
		ticket_no,
		flight_id,
		fare_conditions,
		price,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		s.ticket_no,
		s.flight_id,
		s.fare_conditions,
		s.price,
		'demo.bookings.segments',
		'postgres_demo',
		v_batch_id,
		'I',
		md5(
    		concat_ws('|',
	        coalesce(s.ticket_no, ''),
	        coalesce(s.flight_id::text, ''),
	        coalesce(s.fare_conditions, ''),
	        coalesce(s.price::text, '')
    			)
			)
	from
		source_fdw.segments s;

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
-- Первичное заполнение raw.segments_snapshot данными из источника --
--------------------------------------------------------------------------

create or replace procedure raw.init_segments_snapshot()
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
	raw.segments_snapshot;

	if v_snapshot_count = 0 then
		insert
		into
			raw.segments_snapshot(
			ticket_no,
			flight_id,
			fare_conditions,
			price,
			raw_row_hash)
		select
			s.ticket_no,
			s.flight_id,
			s.fare_conditions,
			s.price,
			md5(
    		concat_ws('|',
	        coalesce(s.ticket_no, ''),
	        coalesce(s.flight_id::text, ''),
	        coalesce(s.fare_conditions, ''),
	        coalesce(s.price::text, '')
    		))
	from
			source_fdw.segments s;

	else 
		 raise notice 'raw.segments_snapshot is not empty. Initialization skipped.';
	end if;

end;
$$;

--------------------------------------------------------------------------
-- Delta-загрузка segments в RAW через snapshot CDC imitation --
--------------------------------------------------------------------------

-- Подготовка временного снимка данных source_fdw.segments для расчёта delta

create or replace procedure raw.prepare_segments_delta_source()
language plpgsql
as $$
begin
	
	drop table if exists tmp_source_segments;
	
	create temp table tmp_source_segments
	on commit drop
	as
		select
			s.ticket_no,
			s.flight_id,
			s.fare_conditions,
			s.price,
			md5(
    		concat_ws('|',
	        coalesce(s.ticket_no, ''),
	        coalesce(s.flight_id::text, ''),
	        coalesce(s.fare_conditions, ''),
	        coalesce(s.price::text, '')
    		)) as raw_row_hash
		from source_fdw.segments s;
	
--create index idx_tmp_source_segments_book_ref
--on tmp_source_segments(book_ref);
--
--analyze tmp_source_segments;

end;
$$;


-- Поиск новых строк: I

create or replace procedure raw.insert_segments_delta_i(p_batch_id bigint)
language plpgsql
as $$
begin 
	insert
	into
	raw.segments(
		ticket_no,
		flight_id,
		fare_conditions,
		price,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		src.ticket_no,
		src.flight_id,
		src.fare_conditions,
		src.price,	
		'demo.bookings.segments',
		'postgres_demo',
		p_batch_id,
		'I',
		src.raw_row_hash
	
	from
		tmp_source_segments src
    left join raw.segments_snapshot sp on src.ticket_no = sp.ticket_no and src.flight_id = sp.flight_id
    where sp.ticket_no is null 
	and  sp.flight_id is null;

end;
$$;


-- Изменённые строки: U

create or replace procedure raw.insert_segments_delta_u(p_batch_id bigint)
language plpgsql
as $$
begin 
	insert
	into
	raw.segments(
		ticket_no,
		flight_id,
		fare_conditions,
		price,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		src.ticket_no,
		src.flight_id,
		src.fare_conditions,
		src.price,		
		'demo.bookings.segments',
		'postgres_demo',
		p_batch_id,
		'U',
		src.raw_row_hash
	from
		tmp_source_segments src
    join raw.segments_snapshot sp on src.ticket_no = sp.ticket_no and src.flight_id = sp.flight_id
    where src.raw_row_hash!=sp.raw_row_hash;

end;
$$;


-- Удаленные строки: D

create or replace procedure raw.insert_segments_delta_d(p_batch_id bigint)
language plpgsql
as $$
begin 

	insert
	into
	raw.segments(
		ticket_no,
		flight_id,
		fare_conditions,
		price,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
		)
	select 
		sp.ticket_no,
		sp.flight_id,
		sp.fare_conditions,
		sp.price,	
		'demo.bookings.segments',
		'postgres_demo',
		p_batch_id,
		'D',
		sp.raw_row_hash
	from
		raw.segments_snapshot sp
    left join tmp_source_segments src on sp.ticket_no = src.ticket_no and src.flight_id = sp.flight_id
    where src.ticket_no is null
    and  src.flight_id is null;
end;
$$;


-- Обнавление segments_snapshot

--create or replace procedure raw.refresh_segments_snapshot()
--language plpgsql
--as $$
--begin
--	
--	truncate table raw.segments_snapshot;
--	
--	insert
--	into
--		raw.segments_snapshot(
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
--	from tmp_source_segments src;
--	
--end;
--$$;

create or replace procedure raw.refresh_segments_snapshot()
language plpgsql
as $$
begin
	
	drop table raw.segments_snapshot;
	

create table raw.segments_snapshot as

	select
		src.ticket_no,
		src.flight_id,
		src.fare_conditions,
		src.price,	
		src.raw_row_hash,
		now() as last_seen_at
	from tmp_source_segments src;
	
end;
$$;


--Главная сборочная процедура, которая последовательно запускает все delta-процедуры для segments и фиксирует время выполнения каждого этапа --

create or replace procedure raw.load_segments_delta()
language plpgsql
as $$
declare
    v_batch_id bigint;
    v_step_started_at timestamptz;
begin
    v_batch_id := meta.start_batch('raw.load_segments_delta');

    v_step_started_at := clock_timestamp();
    call raw.prepare_segments_delta_source();
    raise notice 'prepare_segments_delta_source duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.insert_segments_delta_i(v_batch_id);
    raise notice 'insert_segments_delta_i duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.insert_segments_delta_u(v_batch_id);
    raise notice 'insert_segments_delta_u duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.insert_segments_delta_d(v_batch_id);
    raise notice 'insert_segments_delta_d duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.refresh_segments_snapshot();
    raise notice 'refresh_segments_snapshot duration: %',
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
--
--call raw.load_segments_initial();
--
--select * from raw.segments order by ticket_no desc limit 15
--
--call raw.init_segments_snapshot()
--
--select * from raw.segments_snapshot order by ticket_no desc limit 10
--
--insert into 
--	source_fdw.segments(
--			ticket_no,
--			flight_id,
--			fare_conditions,
--			price)
--values ('0005453207700', 135473, 'Business', 10000.15);
--
--
--update source_fdw.segments
--set 
--	fare_conditions='Comfort',
--	price=10000.25
--where ticket_no='0005453207644' 
--and flight_id=135087
--
--delete from source_fdw.segments
--where ticket_no='0005453207641'
--and flight_id=135473
--
--select * from source_fdw.segments order by ticket_no desc limit 15
--
--
--delete from source_fdw.segments
--where ticket_no = '0005453207640'
--
--
--call raw.load_segments_delta()