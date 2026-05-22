--------------------------------------------------------------------------
-- Первичное заполнение raw.bookings данными из источника  в RAW-слой --
--------------------------------------------------------------------------

create or replace procedure raw.load_bookings_initial()
language plpgsql
as $$
declare
	v_batch_id bigint;

begin

-- Создаем запись о запуске загрузки и получаем batch_id

 v_batch_id := meta.start_batch('raw.load_bookings_initial');

-- Загружаем данные из source_fdw.bookings в raw.bookings
	insert
	into
	raw.bookings(
		book_ref,
		book_date,
		total_amount,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		b.book_ref,
		b.book_date,
		b.total_amount,
		'demo.bookings.bookings',
		'postgres_demo',
		v_batch_id,
		'I',
		md5(
    		concat_ws('|',
	        coalesce(b.book_ref, ''),
	        coalesce(b.book_date::text, ''),
	        coalesce(b.total_amount::text, '')
    			)
			)
	from
		source_fdw.bookings b;

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
-- Первичное заполнение raw.bookings_snapshot данными из источника --
--------------------------------------------------------------------------

create or replace procedure raw.init_bookings_snapshot()
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
	raw.bookings_snapshot;

if v_snapshot_count = 0 then
		insert
	into
		raw.bookings_snapshot( book_ref,
		book_date,
		total_amount,
		raw_row_hash )
		select
			b.book_ref,
			b.book_date,
			b.total_amount,
			md5( concat_ws('|', coalesce(b.book_ref, ''), coalesce(b.book_date::text, ''), coalesce(b.total_amount::text, '') ) )
from
			source_fdw.bookings b;
else 
	 raise notice 'raw.bookings_snapshot is not empty. Initialization skipped.';
end if;
end 
$$;

--------------------------------------------------------------------------
-- Delta-загрузка bookings в RAW через snapshot CDC imitation --
--------------------------------------------------------------------------

-- Подготовка временного снимка данных source_fdw.bookings для расчёта delta

create or replace procedure raw.prepare_bookings_delta_source()
language plpgsql
as $$
begin
	
	drop table if exists tmp_source_bookings;
	
	create temp table tmp_source_bookings
	on commit drop
	as
		select
			b.book_ref,
			b.book_date,
			b.total_amount,
			md5(
			    concat_ws('|',
			        coalesce(b.book_ref, ''),
			        coalesce(b.book_date::text, ''),
			        coalesce(b.total_amount::text, '')
			    )
			) as raw_row_hash
		from source_fdw.bookings b;
	
--create index idx_tmp_source_bookings_book_ref
--on tmp_source_bookings(book_ref);
--
--analyze tmp_source_bookings;

end;
$$;


-- Поиск новых строк: I

create or replace procedure raw.insert_bookings_delta_i(p_batch_id bigint)
language plpgsql
as $$
begin 
	insert
	into
	raw.bookings(
		book_ref,
		book_date,
		total_amount,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		src.book_ref,
		src.book_date,
		src.total_amount,
		'demo.bookings.bookings',
		'postgres_demo',
		p_batch_id,
		'I',
		src.raw_row_hash
	
	from
		tmp_source_bookings src
    left join raw.bookings_snapshot sp on src.book_ref = sp.book_ref
    where sp.book_ref is null;
	
end;
$$;


-- Изменённые строки: U

create or replace procedure raw.insert_bookings_delta_u(p_batch_id bigint)
language plpgsql
as $$
begin 

	insert
	into
	raw.bookings(
		book_ref,
		book_date,
		total_amount,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		src.book_ref,
		src.book_date,
		src.total_amount,
		'demo.bookings.bookings',
		'postgres_demo',
		p_batch_id,
		'U',
		src.raw_row_hash
	from
		tmp_source_bookings src
    join raw.bookings_snapshot sp on src.book_ref = sp.book_ref
    where src.raw_row_hash!=sp.raw_row_hash;

end;
$$;


-- Удаленные строки: D

create or replace procedure raw.insert_bookings_delta_d(p_batch_id bigint)
language plpgsql
as $$
begin 

	insert
	into
	raw.bookings(
		book_ref,
		book_date,
		total_amount,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		sp.book_ref,
		sp.book_date,
		sp.total_amount,
		'demo.bookings.bookings',
		'postgres_demo',
		p_batch_id,
		'D',
		sp.raw_row_hash
	from
		raw.bookings_snapshot sp
    left join tmp_source_bookings src on sp.book_ref = src.book_ref
    where src.book_ref is null;
end;
$$;


-- Обнавление bookings_snapshot

create or replace procedure raw.refresh_bookings_snapshot()
language plpgsql
as $$
begin
	
	truncate table raw.bookings_snapshot;
	
	insert into raw.bookings_snapshot(book_ref,
	    book_date,
	    total_amount,
	    raw_row_hash
	    )
	select
	    src.book_ref,
	    src.book_date,
	    src.total_amount,
	    src.raw_row_hash
	from tmp_source_bookings src;
	
end;
$$;


--create or replace procedure raw.refresh_bookings_snapshot()
--language plpgsql
--as $$
--begin
--
--insert into raw.bookings_snapshot (
--    book_ref,
--    book_date,
--    total_amount,
--    raw_row_hash,
--    last_seen_at
--)
--select
--    src.book_ref,
--    src.book_date,
--    src.total_amount,
--    src.raw_row_hash,
--    now()
--from tmp_source_bookings src
--on conflict (book_ref) do update
--set
--    book_date = excluded.book_date,
--    total_amount = excluded.total_amount,
--    raw_row_hash = excluded.raw_row_hash,
--    last_seen_at = now()
--where raw.bookings_snapshot.raw_row_hash != excluded.raw_row_hash;
--
--delete from raw.bookings_snapshot sp
--where not exists (
--    select 1c
--    from tmp_source_bookings src
--    where src.book_ref = sp.book_ref
--);
--	
--end;
--$$;


--Главная сборочная процедура, которая последовательно запускает все delta-процедуры для bookings и фиксирует время выполнения каждого этапа --

create or replace procedure raw.load_bookings_delta()
language plpgsql
as $$
declare
    v_batch_id bigint;
    v_step_started_at timestamptz;
begin
    v_batch_id := meta.start_batch('raw.load_bookings_delta');

    v_step_started_at := clock_timestamp();
    call raw.prepare_bookings_delta_source();
    raise notice 'prepare_bookings_delta_source duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.insert_bookings_delta_i(v_batch_id);
    raise notice 'insert_bookings_delta_i duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.insert_bookings_delta_u(v_batch_id);
    raise notice 'insert_bookings_delta_u duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.insert_bookings_delta_d(v_batch_id);
    raise notice 'insert_bookings_delta_d duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.refresh_bookings_snapshot();
    raise notice 'refresh_bookings_snapshot duration: %',
        clock_timestamp() - v_step_started_at;

    call meta.finish_batch(v_batch_id);

exception
    when others then
        call meta.fail_batch(v_batch_id, sqlerrm);
        raise;
end;
$$;





-----------------
--
--call raw.load_bookings_delta();
--
--
--call raw.refresh_bookings_snapshot(); 
--
--truncate table raw.bookings_snapshot;
--
--call raw.init_bookings_snapshot();
--
--call raw.prepare_bookings_delta_source();
--
--delete from source_fdw.bookings 
--where book_ref = 'TST001'
--
--update source_fdw.bookings
--set total_amount = 11.00
--where book_ref = 'TST001';
--
--select *
--from raw.bookings_snapshot	
--where book_ref = 'TST001';
--
--call raw.prepare_bookings_delta_source();
--
--select meta.start_batch('test_delete_bookings_delta');
-- 
--
--call raw.delete_bookings_delta(8);
--
--select *
--from raw.bookings
--where book_ref = 'TST001'
--order by load_date;



--select * from meta.load_batch
