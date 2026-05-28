--------------------------------------------------------------------------
-- Первичное заполнение raw.seats данными из источника в RAW-слой --
--------------------------------------------------------------------------

create or replace procedure raw.load_seats_initial()
language plpgsql
as $$
declare
	v_batch_id bigint;

begin

-- Создаем запись о запуске загрузки и получаем batch_id

 v_batch_id := meta.start_batch('raw.load_seats_initial');

-- Загружаем данные из source_fdw.seats в raw.seats
	insert
	into
	raw.seats(
		airplane_code,
		seat_no,
		fare_conditions,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		s.airplane_code,
		s.seat_no,
		s.fare_conditions,
		'demo.bookings.seats',
		'postgres_demo',
		v_batch_id,
		'I',
		md5(
    		concat_ws('|',
	        coalesce(s.airplane_code, ''),
	        coalesce(s.seat_no, ''),
	        coalesce(s.fare_conditions, '')
    			)
			)
	from
		source_fdw.seats s;

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
-- Первичное заполнение raw.seats_snapshot данными из источника --
--------------------------------------------------------------------------

create or replace procedure raw.init_seats_snapshot()
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
	raw.seats_snapshot;

	if v_snapshot_count = 0 then
		insert
		into
		raw.seats_snapshot(
			airplane_code,
			seat_no,
			fare_conditions,
			raw_row_hash)
		select
			s.airplane_code,
			s.seat_no,
			s.fare_conditions,
			md5(
    		concat_ws('|',
	        coalesce(s.airplane_code, ''),
	        coalesce(s.seat_no, ''),
	        coalesce(s.fare_conditions, '')
    			)
			)
	from
			source_fdw.seats s;

	else 
		 raise notice 'raw.seats_snapshot is not empty. Initialization skipped.';
	end if;

end;
$$;

--------------------------------------------------------------------------
-- Delta-загрузка seats в RAW через snapshot CDC imitation --
--------------------------------------------------------------------------

-- Подготовка временного снимка данных source_fdw.seats для расчёта delta

create or replace procedure raw.prepare_seats_delta_source()
language plpgsql
as $$
begin
	
	drop table if exists tmp_source_seats;
	
	create temp table tmp_source_seats
	on commit drop
	as
		select
			s.airplane_code,
			s.seat_no,
			s.fare_conditions,
			md5(
    		concat_ws('|',
	        coalesce(s.airplane_code, ''),
	        coalesce(s.seat_no, ''),
	        coalesce(s.fare_conditions, '')
    			)
			) as raw_row_hash
	from
			source_fdw.seats s;
	
--create index idx_tmp_source_seats_book_ref
--on tmp_source_seats(book_ref);
--
--analyze tmp_source_seats;

end;
$$;


-- Поиск новых строк: I

create or replace procedure raw.insert_seats_delta_i(p_batch_id bigint)
language plpgsql
as $$
begin 
	insert
	into
	raw.seats(
		airplane_code,
		seat_no,
		fare_conditions,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		src.airplane_code,
		src.seat_no,
		src.fare_conditions,
		'demo.bookings.seats',
		'postgres_demo',
		p_batch_id,
		'I',
		src.raw_row_hash
	
	from
		tmp_source_seats src
    left join raw.seats_snapshot sp on src.airplane_code = sp.airplane_code and src.seat_no = sp.seat_no
    where sp.airplane_code is null
	and sp.seat_no is null;
end;
$$;


-- Изменённые строки: U

create or replace procedure raw.insert_seats_delta_u(p_batch_id bigint)
language plpgsql
as $$
begin 
	insert
	into
	raw.seats(
		airplane_code,
		seat_no,
		fare_conditions,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		src.airplane_code,
		src.seat_no,
		src.fare_conditions,
		'demo.bookings.seats',
		'postgres_demo',
		p_batch_id,
		'U',
		src.raw_row_hash
	from
		tmp_source_seats src
    join raw.seats_snapshot sp on src.airplane_code = sp.airplane_code and src.seat_no = sp.seat_no
    where src.raw_row_hash!=sp.raw_row_hash;

end;
$$;


-- Удаленные строки: D

create or replace procedure raw.insert_seats_delta_d(p_batch_id bigint)
language plpgsql
as $$
begin 

	insert
	into
	raw.seats(
		airplane_code,
		seat_no,
		fare_conditions,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		sp.airplane_code,
		sp.seat_no,
		sp.fare_conditions,
		'demo.bookings.seats',
		'postgres_demo',
		p_batch_id,
		'D',
		sp.raw_row_hash
	from
		raw.seats_snapshot sp
    left join tmp_source_seats src on sp.airplane_code = src.airplane_code and sp.seat_no = src.seat_no
    where src.airplane_code is null
	and src.seat_no is null;
end;
$$;


-- Обнавление seats_snapshot

--create or replace procedure raw.refresh_seats_snapshot()
--language plpgsql
--as $$
--begin
--	
--	truncate table raw.seats_snapshot;
--	
--	insert
--	into
--		raw.seats_snapshot(
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
--	from tmp_source_seats src;
--	
--end;
--$$;

create or replace procedure raw.refresh_seats_snapshot()
language plpgsql
as $$
begin
	
	drop table raw.seats_snapshot;
	

create table raw.seats_snapshot as

	select
		src.airplane_code,
		src.seat_no,
		src.fare_conditions,
		src.raw_row_hash,
		now() as last_seen_at
	from tmp_source_seats src;
	
end;
$$;


--Главная сборочная процедура, которая последовательно запускает все delta-процедуры для seats и фиксирует время выполнения каждого этапа --

create or replace procedure raw.load_seats_delta()
language plpgsql
as $$
declare
    v_batch_id bigint;
    v_step_started_at timestamptz;
begin
    v_batch_id := meta.start_batch('raw.load_seats_delta');

    v_step_started_at := clock_timestamp();
    call raw.prepare_seats_delta_source();
    raise notice 'prepare_seats_delta_source duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.insert_seats_delta_i(v_batch_id);
    raise notice 'insert_seats_delta_i duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.insert_seats_delta_u(v_batch_id);
    raise notice 'insert_seats_delta_u duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.insert_seats_delta_d(v_batch_id);
    raise notice 'insert_seats_delta_d duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.refresh_seats_snapshot();
    raise notice 'refresh_seats_snapshot duration: %',
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

call raw.load_seats_initial();

select * from raw.seats order by seat_no limit 20

call raw.init_seats_snapshot()

select * from raw.seats_snapshot limit 20

insert into source_fdw.seats (
    airplane_code,
	seat_no,
	fare_conditions
)
values (
    '32N',
    '0A',
    'Business'
);


update source_fdw.seats
set fare_conditions = 'Economy'
where airplane_code = '32N' and seat_no = '0A';

delete from source_fdw.seats
where airplane_code = '32N' and seat_no = '0A';


call raw.load_seats_delta()
