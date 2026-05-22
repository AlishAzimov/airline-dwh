--------------------------------------------------------------------------
-- Создание функции и процедур для логирования процесса загрузки данных --
--------------------------------------------------------------------------

create or replace function meta.start_batch(p_process_name text)
returns bigint
language plpgsql
as $$
declare 
	v_batch_id bigint;
begin
	insert into 
	meta.load_batch(process_name,
		status,
		started_at)
	values(p_process_name,
			'RUNNING',
			now())
	returning batch_id into v_batch_id;

	return v_batch_id;
end;
$$; 


create or replace procedure meta.finish_batch(p_batch_id bigint)
language plpgsql
as $$
begin
	update
		meta.load_batch
	set
		status = 'SUCCESS',
	    finished_at = now()
	where
		batch_id = p_batch_id;
end;
$$;


create or replace procedure meta.fail_batch(p_batch_id bigint, p_error_message text)
language plpgsql
as $$
begin
	update
		meta.load_batch
	set
		status = 'FAILED',
		finished_at = now(),
	    error_message = p_error_message
	where
		batch_id = p_batch_id;
end;
$$;

--------------------------------------------------------------------------
-- Процедура полной первичной загрузки данных bookings в RAW-слой --
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
	-- on commit drop
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







update source_fdw.bookings
set total_amount = 2000.00
where book_ref = 'TST001';






insert into source_fdw.bookings (
    book_ref,
    book_date,
    total_amount
)
values (
    'TST001',
    now(),
    1000.00
);




call raw.prepare_bookings_delta_source();
select meta.start_batch('test_insert_bookings_delta_i');
call raw.insert_bookings_delta_i(3);

select
    book_ref,
    book_date,
    total_amount,
    batch_id,
    operation_type,
    raw_row_hash
from raw.bookings
where batch_id = 3;

select operation_type, count(*)
from raw.bookings
where batch_id = 999
group by operation_type;

------------------------------------------------------


--call raw.load_bookings_initial();
--call raw.init_bookings_snapshot();
--call raw.load_bookings_delta();
--
--
--select * from meta.load_batch
