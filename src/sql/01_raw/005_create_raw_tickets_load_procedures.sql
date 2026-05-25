--------------------------------------------------------------------------
-- Первичное заполнение raw.tickets данными из источника в RAW-слой --
--------------------------------------------------------------------------

create or replace procedure raw.load_tickets_initial()
language plpgsql
as $$
declare
	v_batch_id bigint;

begin

-- Создаем запись о запуске загрузки и получаем batch_id

 v_batch_id := meta.start_batch('raw.load_tickets_initial');

-- Загружаем данные из source_fdw.tickets в raw.tickets
	insert
	into
	raw.tickets(
		ticket_no,
		book_ref,
		passenger_id,
		passenger_name,
		outbound,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		t.ticket_no,
		t.book_ref,
		t.passenger_id,
		t.passenger_name,
		t.outbound,
		'demo.bookings.tickets',
		'postgres_demo',
		v_batch_id,
		'I',
		md5(
    		concat_ws('|',
	        coalesce(t.ticket_no, ''),
	        coalesce(t.book_ref, ''),
	        coalesce(t.passenger_id, ''),
	        coalesce(t.passenger_name, ''),
	        coalesce(t.outbound::text, '')
    			)
			)
	from
		source_fdw.tickets t;

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
-- Первичное заполнение raw.tickets_snapshot данными из источника --
--------------------------------------------------------------------------

create or replace procedure raw.init_tickets_snapshot()
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
	raw.tickets_snapshot;

if v_snapshot_count = 0 then
	insert
	into
		raw.tickets_snapshot(
		ticket_no,
		book_ref,
		passenger_id,
		passenger_name,
		outbound,
		raw_row_hash)
		select
			t.ticket_no,
			t.book_ref,
			t.passenger_id,
			t.passenger_name,
			t.outbound,
			md5(
    		concat_ws('|',
	        coalesce(t.ticket_no, ''),
	        coalesce(t.book_ref, ''),
	        coalesce(t.passenger_id, ''),
	        coalesce(t.passenger_name, ''),
	        coalesce(t.outbound::text, '')
    			)
			)
from
			source_fdw.tickets t;
else 
	 raise notice 'raw.tickets_snapshot is not empty. Initialization skipped.';
end if;
end 
$$;

--------------------------------------------------------------------------
-- Delta-загрузка tickets в RAW через snapshot CDC imitation --
--------------------------------------------------------------------------

-- Подготовка временного снимка данных source_fdw.tickets для расчёта delta

create or replace procedure raw.prepare_tickets_delta_source()
language plpgsql
as $$
begin
	
	drop table if exists tmp_source_tickets;
	
	create temp table tmp_source_tickets
	on commit drop
	as
		select
			t.ticket_no,
			t.book_ref,
			t.passenger_id,
			t.passenger_name,
			t.outbound,
			md5(
    		concat_ws('|',
	        coalesce(t.ticket_no, ''),
	        coalesce(t.book_ref, ''),
	        coalesce(t.passenger_id, ''),
	        coalesce(t.passenger_name, ''),
	        coalesce(t.outbound::text, '')
    			)) as raw_row_hash
		from source_fdw.tickets t;
	
--create index idx_tmp_source_tickets_book_ref
--on tmp_source_tickets(book_ref);
--
--analyze tmp_source_tickets;

end;
$$;


-- Поиск новых строк: I

create or replace procedure raw.insert_tickets_delta_i(p_batch_id bigint)
language plpgsql
as $$
begin 
	insert
	into
	raw.tickets(
		ticket_no,
		book_ref,
		passenger_id,
		passenger_name,
		outbound,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		src.ticket_no,
		src.book_ref,
		src.passenger_id,
		src.passenger_name,
		src.outbound,	
		'demo.bookings.tickets',
		'postgres_demo',
		p_batch_id,
		'I',
		src.raw_row_hash
	
	from
		tmp_source_tickets src
    left join raw.tickets_snapshot sp on src.ticket_no = sp.ticket_no
    where sp.ticket_no is null;

end;
$$;


-- Изменённые строки: U

create or replace procedure raw.insert_tickets_delta_u(p_batch_id bigint)
language plpgsql
as $$
begin 
	insert
	into
	raw.tickets(
		ticket_no,
		book_ref,
		passenger_id,
		passenger_name,
		outbound,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		src.ticket_no,
		src.book_ref,
		src.passenger_id,
		src.passenger_name,
		src.outbound,	
		'demo.bookings.tickets',
		'postgres_demo',
		p_batch_id,
		'U',
		src.raw_row_hash
	from
		tmp_source_tickets src
    join raw.tickets_snapshot sp on src.ticket_no = sp.ticket_no
    where src.raw_row_hash!=sp.raw_row_hash;

end;
$$;


-- Удаленные строки: D

create or replace procedure raw.insert_tickets_delta_d(p_batch_id bigint)
language plpgsql
as $$
begin 

	insert
	into
	raw.tickets(
		ticket_no,
		book_ref,
		passenger_id,
		passenger_name,
		outbound,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		sp.ticket_no,
		sp.book_ref,
		sp.passenger_id,
		sp.passenger_name,
		sp.outbound,
		'demo.bookings.tickets',
		'postgres_demo',
		p_batch_id,
		'D',
		sp.raw_row_hash
	from
		raw.tickets_snapshot sp
    left join tmp_source_tickets src on sp.ticket_no = src.ticket_no
    where src.ticket_no is null;
end;
$$;


-- Обнавление tickets_snapshot

--create or replace procedure raw.refresh_tickets_snapshot()
--language plpgsql
--as $$
--begin
--	
--	truncate table raw.tickets_snapshot;
--	
--	insert
--	into
--		raw.tickets_snapshot(
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
--	from tmp_source_tickets src;
--	
--end;
--$$;

create or replace procedure raw.refresh_tickets_snapshot()
language plpgsql
as $$
begin
	
	drop table raw.tickets_snapshot;
	

create table raw.tickets_snapshot as

	select
		src.ticket_no,
		src.book_ref,
		src.passenger_id,
		src.passenger_name,
		src.outbound,
		src.raw_row_hash
	from tmp_source_tickets src;
	
end;
$$;


--Главная сборочная процедура, которая последовательно запускает все delta-процедуры для tickets и фиксирует время выполнения каждого этапа --

create or replace procedure raw.load_tickets_delta()
language plpgsql
as $$
declare
    v_batch_id bigint;
    v_step_started_at timestamptz;
begin
    v_batch_id := meta.start_batch('raw.load_tickets_delta');

    v_step_started_at := clock_timestamp();
    call raw.prepare_tickets_delta_source();
    raise notice 'prepare_tickets_delta_source duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.insert_tickets_delta_i(v_batch_id);
    raise notice 'insert_tickets_delta_i duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.insert_tickets_delta_u(v_batch_id);
    raise notice 'insert_tickets_delta_u duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.insert_tickets_delta_d(v_batch_id);
    raise notice 'insert_tickets_delta_d duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.refresh_tickets_snapshot();
    raise notice 'refresh_tickets_snapshot duration: %',
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

call raw.load_tickets_initial()

select * from raw.tickets order by ticket_no desc limit 10

call raw.init_tickets_snapshot()

select * from raw.tickets_snapshot limit 10

insert into 
	source_fdw.tickets(
			ticket_no,
			book_ref,
			passenger_id,
			passenger_name,
			outbound)
values ('0005453207700', 'OJ1F1D', 'UZ 9000000000000', 'Alisher Azimov', false);


update source_fdw.tickets
set 
	passenger_id='UZ 9000000000000',
	passenger_name = 'Alisher Azimov',
	outbound = false
where ticket_no='0005453207642'

delete from source_fdw.tickets
where ticket_no='0005453207640'

delete from source_fdw.segments
where ticket_no = '0005453207640'


call raw.load_tickets_delta()