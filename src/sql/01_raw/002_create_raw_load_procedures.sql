

-- Создание функции и процедур для логирования процесса загрузки данных --

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

-----------------------------------------------------------------------------------

-- Процедура полной первичной загрузки данных bookings в RAW-слой --

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


-- Первичное заполнение raw.bookings_snapshot данными из источника --

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




create or replace procedure raw.load_bookings_delta()
language plpgsql
as $$
declare
    v_batch_id bigint;
begin
    -- Создаем запись о запуске загрузки и получаем batch_id
    v_batch_id := meta.start_batch('raw.load_bookings_delta');

    begin
        -- Временная таблица с текущим состоянием source и рассчитанным hash
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

        -- I: новые строки, которых нет в snapshot
        insert into raw.bookings (
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
            'demo.bookings.bookings' as record_source,
            'postgres_demo' as source_system,
            v_batch_id as batch_id,
            'I' as operation_type,
            src.raw_row_hash
        from tmp_source_bookings src
        left join raw.bookings_snapshot snap
            on snap.book_ref = src.book_ref
        where snap.book_ref is null;

        -- U: строки есть и в source, и в snapshot, но hash изменился
        insert into raw.bookings (
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
            'demo.bookings.bookings' as record_source,
            'postgres_demo' as source_system,
            v_batch_id as batch_id,
            'U' as operation_type,
            src.raw_row_hash
        from tmp_source_bookings src
        join raw.bookings_snapshot snap
            on snap.book_ref = src.book_ref
        where src.raw_row_hash <> snap.raw_row_hash;

        -- D: строки были в snapshot, но исчезли из source
        insert into raw.bookings (
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
            snap.book_ref,
            snap.book_date,
            snap.total_amount,
            'demo.bookings.bookings' as record_source,
            'postgres_demo' as source_system,
            v_batch_id as batch_id,
            'D' as operation_type,
            snap.raw_row_hash
        from raw.bookings_snapshot snap
        left join tmp_source_bookings src
            on src.book_ref = snap.book_ref
        where src.book_ref is null;

        -- Обновляем snapshot: новые и изменённые строки
        insert into raw.bookings_snapshot (
            book_ref,
            book_date,
            total_amount,
            raw_row_hash,
            last_seen_at
        )
        select
            src.book_ref,
            src.book_date,
            src.total_amount,
            src.raw_row_hash,
            now() as last_seen_at
        from tmp_source_bookings src
        on conflict (book_ref) do update
        set
            book_date = excluded.book_date,
            total_amount = excluded.total_amount,
            raw_row_hash = excluded.raw_row_hash,
            last_seen_at = now();

        -- Удаляем из snapshot строки, которых больше нет в source
        delete from raw.bookings_snapshot snap
        where not exists (
            select 1
            from tmp_source_bookings src
            where src.book_ref = snap.book_ref
        );

        -- Успешное завершение batch
        call meta.finish_batch(v_batch_id);

    exception
        when others then
            call meta.fail_batch(v_batch_id, sqlerrm);

            raise notice 'raw.load_bookings_delta failed: %', sqlerrm;
    end;
end;
$$;






call raw.load_bookings_initial();
call raw.init_bookings_snapshot();
call raw.load_bookings_delta();


