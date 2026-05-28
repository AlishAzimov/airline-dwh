--------------------------------------------------------------------------
-- Первичное заполнение raw.airplanes_data данными из источника в RAW-слой --
--------------------------------------------------------------------------

create or replace procedure raw.load_airplanes_data_initial()
language plpgsql
as $$
declare
	v_batch_id bigint;

begin

-- Создаем запись о запуске загрузки и получаем batch_id

 v_batch_id := meta.start_batch('raw.load_airplanes_data_initial');

-- Загружаем данные из source_fdw.airplanes_data в raw.airplanes_data
	insert
	into
	raw.airplanes_data(
		airplane_code,
		model,
		"range",
		speed,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		ad.airplane_code,
		ad.model,
		ad."range",
		ad.speed,
		'demo.bookings.airplanes_data',
		'postgres_demo',
		v_batch_id,
		'I',
		md5(
    		concat_ws('|',
	        coalesce(ad.airplane_code, ''),
	        coalesce(ad.model::text, ''),
	        coalesce(ad."range"::text, ''),
	        coalesce(ad.speed::text, '')
    			)
			)
	from
		source_fdw.airplanes_data ad;

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
-- Первичное заполнение raw.airplanes_data_snapshot данными из источника --
--------------------------------------------------------------------------

create or replace procedure raw.init_airplanes_data_snapshot()
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
	raw.airplanes_data_snapshot;

	if v_snapshot_count = 0 then
		insert
		into
		raw.airplanes_data_snapshot(
			airplane_code,
			model,
			"range",
			speed,
			raw_row_hash)
		select
			ad.airplane_code,
			ad.model,
			ad."range",
			ad.speed,
			md5(
    		concat_ws('|',
	        coalesce(ad.airplane_code, ''),
	        coalesce(ad.model::text, ''),
	        coalesce(ad."range"::text, ''),
	        coalesce(ad.speed::text, '')
    			)
			)
	from
			source_fdw.airplanes_data ad;

	else 
		 raise notice 'raw.airplanes_data_snapshot is not empty. Initialization skipped.';
	end if;

end;
$$;

--------------------------------------------------------------------------
-- Delta-загрузка airplanes_data в RAW через snapshot CDC imitation --
--------------------------------------------------------------------------

-- Подготовка временного снимка данных source_fdw.airplanes_data для расчёта delta

create or replace procedure raw.prepare_airplanes_data_delta_source()
language plpgsql
as $$
begin
	
	drop table if exists tmp_source_airplanes_data;
	
	create temp table tmp_source_airplanes_data
	on commit drop
	as
		select
			ad.airplane_code,
			ad.model,
			ad."range",
			ad.speed,
			md5(
    		concat_ws('|',
	        coalesce(ad.airplane_code, ''),
	        coalesce(ad.model::text, ''),
	        coalesce(ad."range"::text, ''),
	        coalesce(ad.speed::text, '')
    			)
			) as raw_row_hash
	from
			source_fdw.airplanes_data ad;
	
--create index idx_tmp_source_airplanes_data_book_ref
--on tmp_source_airplanes_data(book_ref);
--
--analyze tmp_source_airplanes_data;

end;
$$;


-- Поиск новых строк: I

create or replace procedure raw.insert_airplanes_data_delta_i(p_batch_id bigint)
language plpgsql
as $$
begin 
	insert
	into
	raw.airplanes_data(
		airplane_code,
		model,
		"range",
		speed,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		src.airplane_code,
		src.model,
		src."range",
		src.speed,
		'demo.bookings.airplanes_data',
		'postgres_demo',
		p_batch_id,
		'I',
		src.raw_row_hash
	
	from
		tmp_source_airplanes_data src
    left join raw.airplanes_data_snapshot sp on src.airplane_code = sp.airplane_code 
    where sp.airplane_code is null;

end;
$$;


-- Изменённые строки: U

create or replace procedure raw.insert_airplanes_data_delta_u(p_batch_id bigint)
language plpgsql
as $$
begin 
	insert
	into
	raw.airplanes_data(
		airplane_code,
		model,
		"range",
		speed,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		src.airplane_code,
		src.model,
		src."range",
		src.speed,
		'demo.bookings.airplanes_data',
		'postgres_demo',
		p_batch_id,
		'U',
		src.raw_row_hash
	from
		tmp_source_airplanes_data src
    join raw.airplanes_data_snapshot sp on src.airplane_code = sp.airplane_code
    where src.raw_row_hash!=sp.raw_row_hash;

end;
$$;


-- Удаленные строки: D

create or replace procedure raw.insert_airplanes_data_delta_d(p_batch_id bigint)
language plpgsql
as $$
begin 

	insert
	into
	raw.airplanes_data(
		airplane_code,
		model,
		"range",
		speed,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		sp.airplane_code,
		sp.model,
		sp."range",
		sp.speed,
		'demo.bookings.airplanes_data',
		'postgres_demo',
		p_batch_id,
		'D',
		sp.raw_row_hash
	from
		raw.airplanes_data_snapshot sp
    left join tmp_source_airplanes_data src on sp.airplane_code = src.airplane_code
    where src.airplane_code is null;
end;
$$;


-- Обнавление airplanes_data_snapshot

--create or replace procedure raw.refresh_airplanes_data_snapshot()
--language plpgsql
--as $$
--begin
--	
--	truncate table raw.airplanes_data_snapshot;
--	
--	insert
--	into
--		raw.airplanes_data_snapshot(
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
--	from tmp_source_airplanes_data src;
--	
--end;
--$$;

create or replace procedure raw.refresh_airplanes_data_snapshot()
language plpgsql
as $$
begin
	
	drop table raw.airplanes_data_snapshot;
	

create table raw.airplanes_data_snapshot as

	select
		src.airplane_code,
		src.model,
		src."range",
		src.speed,
		src.raw_row_hash,
		now() as last_seen_at
	from tmp_source_airplanes_data src;
	
end;
$$;


--Главная сборочная процедура, которая последовательно запускает все delta-процедуры для airplanes_data и фиксирует время выполнения каждого этапа --

create or replace procedure raw.load_airplanes_data_delta()
language plpgsql
as $$
declare
    v_batch_id bigint;
    v_step_started_at timestamptz;
begin
    v_batch_id := meta.start_batch('raw.load_airplanes_data_delta');

    v_step_started_at := clock_timestamp();
    call raw.prepare_airplanes_data_delta_source();
    raise notice 'prepare_airplanes_data_delta_source duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.insert_airplanes_data_delta_i(v_batch_id);
    raise notice 'insert_airplanes_data_delta_i duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.insert_airplanes_data_delta_u(v_batch_id);
    raise notice 'insert_airplanes_data_delta_u duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.insert_airplanes_data_delta_d(v_batch_id);
    raise notice 'insert_airplanes_data_delta_d duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.refresh_airplanes_data_snapshot();
    raise notice 'refresh_airplanes_data_snapshot duration: %',
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
--call raw.load_airplanes_data_initial();
--
--select * from raw.airplanes_data 
--
--call raw.init_airplanes_data_snapshot()
--
--select * from raw.airplanes_data_snapshot 
--
--insert into source_fdw.airplanes_data (
--    airplane_code,
--    model,
--    "range",
--    speed
--)
--values (
--    '738',
--    '{"en": "Boeing 737-800", "ru": "Боинг 737-800"}'::jsonb,
--    5765,
--    850
--);
--
--
--update source_fdw.airplanes_data
--set speed = 855
--where airplane_code = '76F';
--
--delete from source_fdw.airplanes_data
--where airplane_code='738';
--
--
--call raw.load_airplanes_data_delta()
