--------------------------------------------------------------------------
-- Первичное заполнение raw.boarding_passes данными из источника в RAW-слой --
--------------------------------------------------------------------------

create or replace procedure raw.load_boarding_passes_initial()
language plpgsql
as $$
declare
	v_batch_id bigint;

begin

-- Создаем запись о запуске загрузки и получаем batch_id

 v_batch_id := meta.start_batch('raw.load_boarding_passes_initial');

-- Загружаем данные из source_fdw.boarding_passes в raw.boarding_passes
	insert
	into
	raw.boarding_passes(
		ticket_no,
		flight_id,
		seat_no,
		boarding_no,
		boarding_time,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		b.ticket_no,
		b.flight_id,
		b.seat_no,
		b.boarding_no,
		b.boarding_time,
		'demo.bookings.boarding_passes',
		'postgres_demo',
		v_batch_id,
		'I',
		md5(
    		concat_ws('|',
	        coalesce(b.ticket_no, ''),
	        coalesce(b.flight_id::text, ''),
	        coalesce(b.seat_no, ''),
	        coalesce(b.boarding_no::text, ''),
			coalesce(b.boarding_time::text, '')
    			)
			)
	from
		source_fdw.boarding_passes b;

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
-- Первичное заполнение raw.boarding_passes_snapshot данными из источника --
--------------------------------------------------------------------------

create or replace procedure raw.init_boarding_passes_snapshot()
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
	raw.boarding_passes_snapshot;

	if v_snapshot_count = 0 then
		insert
		into
			raw.boarding_passes_snapshot(
			ticket_no,
			flight_id,
			seat_no,
			boarding_no,
			boarding_time,
			raw_row_hash)
		select
			b.ticket_no,
			b.flight_id,
			b.seat_no,
			b.boarding_no,
			b.boarding_time,
			md5(
    		concat_ws('|',
	        coalesce(b.ticket_no, ''),
	        coalesce(b.flight_id::text, ''),
	        coalesce(b.seat_no, ''),
	        coalesce(b.boarding_no::text, ''),
			coalesce(b.boarding_time::text, '')
    			)
			)
	from
			source_fdw.boarding_passes b;

	else 
		 raise notice 'raw.boarding_passes_snapshot is not empty. Initialization skipped.';
	end if;

end;
$$;

--------------------------------------------------------------------------
-- Delta-загрузка boarding_passes в RAW через snapshot CDC imitation --
--------------------------------------------------------------------------

-- Подготовка временного снимка данных source_fdw.boarding_passes для расчёта delta

create or replace procedure raw.prepare_boarding_passes_delta_source()
language plpgsql
as $$
begin
	
	drop table if exists tmp_source_boarding_passes;
	
	create temp table tmp_source_boarding_passes
	on commit drop
	as
		select
			b.ticket_no,
			b.flight_id,
			b.seat_no,
			b.boarding_no,
			b.boarding_time,
			md5(
    		concat_ws('|',
	        coalesce(b.ticket_no, ''),
	        coalesce(b.flight_id::text, ''),
	        coalesce(b.seat_no, ''),
	        coalesce(b.boarding_no::text, ''),
			coalesce(b.boarding_time::text, '')
    			)
			) as raw_row_hash
		from source_fdw.boarding_passes b;
	
--create index idx_tmp_source_boarding_passes_book_ref
--on tmp_source_boarding_passes(book_ref);
--
--analyze tmp_source_boarding_passes;

end;
$$;


-- Поиск новых строк: I

create or replace procedure raw.insert_boarding_passes_delta_i(p_batch_id bigint)
language plpgsql
as $$
begin 
	insert
	into
	raw.boarding_passes(
		ticket_no,
		flight_id,
		seat_no,
		boarding_no,
		boarding_time,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		src.ticket_no,
		src.flight_id,
		src.seat_no,
		src.boarding_no,
		src.boarding_time,
		'demo.bookings.boarding_passes',
		'postgres_demo',
		p_batch_id,
		'I',
		src.raw_row_hash
	
	from
		tmp_source_boarding_passes src
    left join raw.boarding_passes_snapshot sp on src.ticket_no = sp.ticket_no and src.flight_id = sp.flight_id
    where sp.ticket_no is null 
	and  sp.flight_id is null;

end;
$$;


-- Изменённые строки: U

create or replace procedure raw.insert_boarding_passes_delta_u(p_batch_id bigint)
language plpgsql
as $$
begin 
	insert
	into
	raw.boarding_passes(
		ticket_no,
		flight_id,
		seat_no,
		boarding_no,
		boarding_time,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		src.ticket_no,
		src.flight_id,
		src.seat_no,
		src.boarding_no,
		src.boarding_time,
		'demo.bookings.boarding_passes',
		'postgres_demo',
		p_batch_id,
		'U',
		src.raw_row_hash
	from
		tmp_source_boarding_passes src
    join raw.boarding_passes_snapshot sp on src.ticket_no = sp.ticket_no and src.flight_id = sp.flight_id
    where src.raw_row_hash!=sp.raw_row_hash;

end;
$$;


-- Удаленные строки: D

create or replace procedure raw.insert_boarding_passes_delta_d(p_batch_id bigint)
language plpgsql
as $$
begin 

		insert
	into
	raw.boarding_passes(
		ticket_no,
		flight_id,
		seat_no,
		boarding_no,
		boarding_time,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		sp.ticket_no,
		sp.flight_id,
		sp.seat_no,
		sp.boarding_no,
		sp.boarding_time,
		'demo.bookings.boarding_passes',
		'postgres_demo',
		p_batch_id,
		'D',
		sp.raw_row_hash
	from
		raw.boarding_passes_snapshot sp
    left join tmp_source_boarding_passes src on sp.ticket_no = src.ticket_no and src.flight_id = sp.flight_id
    where src.ticket_no is null
    and  src.flight_id is null;
end;
$$;


-- Обнавление boarding_passes_snapshot

--create or replace procedure raw.refresh_boarding_passes_snapshot()
--language plpgsql
--as $$
--begin
--	
--	truncate table raw.boarding_passes_snapshot;
--	
--	insert
--	into
--		raw.boarding_passes_snapshot(
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
--	from tmp_source_boarding_passes src;
--	
--end;
--$$;

create or replace procedure raw.refresh_boarding_passes_snapshot()
language plpgsql
as $$
begin
	
	drop table raw.boarding_passes_snapshot;
	

create table raw.boarding_passes_snapshot as

	select
		src.ticket_no,
		src.flight_id,
		src.seat_no,
		src.boarding_no,
		src.boarding_time,	
		src.raw_row_hash,
		now() as last_seen_at
	from tmp_source_boarding_passes src;
	
end;
$$;


--Главная сборочная процедура, которая последовательно запускает все delta-процедуры для boarding_passes и фиксирует время выполнения каждого этапа --

create or replace procedure raw.load_boarding_passes_delta()
language plpgsql
as $$
declare
    v_batch_id bigint;
    v_step_started_at timestamptz;
begin
    v_batch_id := meta.start_batch('raw.load_boarding_passes_delta');

    v_step_started_at := clock_timestamp();
    call raw.prepare_boarding_passes_delta_source();
    raise notice 'prepare_boarding_passes_delta_source duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.insert_boarding_passes_delta_i(v_batch_id);
    raise notice 'insert_boarding_passes_delta_i duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.insert_boarding_passes_delta_u(v_batch_id);
    raise notice 'insert_boarding_passes_delta_u duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.insert_boarding_passes_delta_d(v_batch_id);
    raise notice 'insert_boarding_passes_delta_d duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.refresh_boarding_passes_snapshot();
    raise notice 'refresh_boarding_passes_snapshot duration: %',
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

call raw.load_boarding_passes_initial();

select * from raw.boarding_passes order by ticket_no desc limit 15

call raw.init_boarding_passes_snapshot()

select * from raw.boarding_passes_snapshot order by ticket_no desc limit 10

insert into 
	source_fdw.boarding_passes(
		ticket_no,
		flight_id,
		seat_no,
		boarding_no,
		boarding_time)
values ('0005453207700', 135473, '9A', 9, now());


update source_fdw.boarding_passes
set 
	seat_no='9A',
	boarding_no=777,
	boarding_time=now()
where ticket_no='0005453201244' 
and flight_id=124941

delete from source_fdw.boarding_passes
where ticket_no='0005453201083'
and flight_id=124923

select * from source_fdw.boarding_passes order by ticket_no desc limit 15


delete from source_fdw.boarding_passes
where ticket_no = '0005453207640'


call raw.load_boarding_passes_delta()