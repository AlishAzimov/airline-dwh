--------------------------------------------------------------------------
-- Первичное заполнение raw.airports_data данными из источника в RAW-слой --
--------------------------------------------------------------------------

create or replace procedure raw.load_airports_data_initial()
language plpgsql
as $$
declare
	v_batch_id bigint;

begin

-- Создаем запись о запуске загрузки и получаем batch_id

 v_batch_id := meta.start_batch('raw.load_airports_data_initial');

-- Загружаем данные из source_fdw.airports_data в raw.airports_data
	insert
	into
	raw.airports_data(
		airport_code,
		airport_name,
		city,
		country,
		coordinates,
		timezone,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		ad.airport_code,
		ad.airport_name,
		ad.city,
		ad.country,
		ad.coordinates,
		ad.timezone,
		'demo.bookings.airports_data',
		'postgres_demo',
		v_batch_id,
		'I',
		md5(
    		concat_ws('|',
	        coalesce(ad.airport_code, ''),
	        coalesce(ad.airport_name::text, ''),
	        coalesce(ad.city::text, ''),
	        coalesce(ad.country::text, ''),
			coalesce(ad.timezone, '')
    			)
			)
	from
		source_fdw.airports_data ad;

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
-- Первичное заполнение raw.airports_data_snapshot данными из источника --
--------------------------------------------------------------------------

create or replace procedure raw.init_airports_data_snapshot()
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
	raw.airports_data_snapshot;

	if v_snapshot_count = 0 then
		insert
		into
		raw.airports_data_snapshot(
			airport_code,
			airport_name,
			city,
			country,
			coordinates,
			timezone,
			raw_row_hash)
		select
			ad.airport_code,
			ad.airport_name,
			ad.city,
			ad.country,
			ad.coordinates,
			ad.timezone,
			md5(
    		concat_ws('|',
	        coalesce(ad.airport_code, ''),
	        coalesce(ad.airport_name::text, ''),
	        coalesce(ad.city::text, ''),
	        coalesce(ad.country::text, ''),
			coalesce(ad.timezone, '')
    			)
			)
	from
			source_fdw.airports_data ad;

	else 
		 raise notice 'raw.airports_data_snapshot is not empty. Initialization skipped.';
	end if;

end;
$$;

--------------------------------------------------------------------------
-- Delta-загрузка airports_data в RAW через snapshot CDC imitation --
--------------------------------------------------------------------------

-- Подготовка временного снимка данных source_fdw.airports_data для расчёта delta

create or replace procedure raw.prepare_airports_data_delta_source()
language plpgsql
as $$
begin
	
	drop table if exists tmp_source_airports_data;
	
	create temp table tmp_source_airports_data
	on commit drop
	as
		select
			ad.airport_code,
			ad.airport_name,
			ad.city,
			ad.country,
			ad.coordinates,
			ad.timezone,
			md5(
    		concat_ws('|',
	        coalesce(ad.airport_code, ''),
	        coalesce(ad.airport_name::text, ''),
	        coalesce(ad.city::text, ''),
	        coalesce(ad.country::text, ''),
			coalesce(ad.timezone, '')
    			)
			) as raw_row_hash
	from
			source_fdw.airports_data ad;
	
--create index idx_tmp_source_airports_data_book_ref
--on tmp_source_airports_data(book_ref);
--
--analyze tmp_source_airports_data;

end;
$$;


-- Поиск новых строк: I

create or replace procedure raw.insert_airports_data_delta_i(p_batch_id bigint)
language plpgsql
as $$
begin 
	insert
	into
	raw.airports_data(
		airport_code,
		airport_name,
		city,
		country,
		coordinates,
		timezone,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		src.airport_code,
		src.airport_name,
		src.city,
		src.country,
		src.coordinates,
		src.timezone,
		'demo.bookings.airports_data',
		'postgres_demo',
		p_batch_id,
		'I',
		src.raw_row_hash
	
	from
		tmp_source_airports_data src
    left join raw.airports_data_snapshot sp on src.airport_code = sp.airport_code 

    where sp.airport_code is null;

end;
$$;


-- Изменённые строки: U

create or replace procedure raw.insert_airports_data_delta_u(p_batch_id bigint)
language plpgsql
as $$
begin 
	insert
	into
	raw.airports_data(
		airport_code,
		airport_name,
		city,
		country,
		coordinates,
		timezone,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		src.airport_code,
		src.airport_name,
		src.city,
		src.country,
		src.coordinates,
		src.timezone,
		'demo.bookings.airports_data',
		'postgres_demo',
		p_batch_id,
		'U',
		src.raw_row_hash
	from
		tmp_source_airports_data src
    join raw.airports_data_snapshot sp on src.airport_code = sp.airport_code
    where src.raw_row_hash!=sp.raw_row_hash;

end;
$$;


-- Удаленные строки: D

create or replace procedure raw.insert_airports_data_delta_d(p_batch_id bigint)
language plpgsql
as $$
begin 

	insert
	into
	raw.airports_data(
		airport_code,
		airport_name,
		city,
		country,
		coordinates,
		timezone,
		record_source,
		source_system,
		batch_id,
		operation_type,
		raw_row_hash
	)
	select 
		sp.airport_code,
		sp.airport_name,
		sp.city,
		sp.country,
		sp.coordinates,
		sp.timezone,
		'demo.bookings.airports_data',
		'postgres_demo',
		p_batch_id,
		'D',
		sp.raw_row_hash
	from
		raw.airports_data_snapshot sp
    left join tmp_source_airports_data src on sp.airport_code = src.airport_code
    where src.airport_code is null;
end;
$$;


-- Обнавление airports_data_snapshot

--create or replace procedure raw.refresh_airports_data_snapshot()
--language plpgsql
--as $$
--begin
--	
--	truncate table raw.airports_data_snapshot;
--	
--	insert
--	into
--		raw.airports_data_snapshot(
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
--	from tmp_source_airports_data src;
--	
--end;
--$$;

create or replace procedure raw.refresh_airports_data_snapshot()
language plpgsql
as $$
begin
	
	drop table raw.airports_data_snapshot;
	

create table raw.airports_data_snapshot as

	select
		src.airport_code,
		src.airport_name,
		src.city,
		src.country,
		src.coordinates,
		src.timezone,
		src.raw_row_hash,
		now() as last_seen_at
	from tmp_source_airports_data src;
	
end;
$$;


--Главная сборочная процедура, которая последовательно запускает все delta-процедуры для airports_data и фиксирует время выполнения каждого этапа --

create or replace procedure raw.load_airports_data_delta()
language plpgsql
as $$
declare
    v_batch_id bigint;
    v_step_started_at timestamptz;
begin
    v_batch_id := meta.start_batch('raw.load_airports_data_delta');

    v_step_started_at := clock_timestamp();
    call raw.prepare_airports_data_delta_source();
    raise notice 'prepare_airports_data_delta_source duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.insert_airports_data_delta_i(v_batch_id);
    raise notice 'insert_airports_data_delta_i duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.insert_airports_data_delta_u(v_batch_id);
    raise notice 'insert_airports_data_delta_u duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.insert_airports_data_delta_d(v_batch_id);
    raise notice 'insert_airports_data_delta_d duration: %',
        clock_timestamp() - v_step_started_at;

    v_step_started_at := clock_timestamp();
    call raw.refresh_airports_data_snapshot();
    raise notice 'refresh_airports_data_snapshot duration: %',
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

call raw.load_airports_data_initial();

select * from raw.airports_data 
where country ->> 'en' ilike 'Uzbe%'

 

call raw.init_airports_data_snapshot()

select * from raw.airports_data_snapshot order by airport_code desc limit 10

insert into source_fdw.airports_data (
    airport_code,
    airport_name,
    city,
    country,
    coordinates,
    timezone
)
values (
    'XVA',
    '{"en": "Khiva", "ru": "Хива"}'::jsonb,
    '{"en": "Khiva", "ru": "Хива"}'::jsonb,
    '{"en": "Uzbekistan", "ru": "Узбекистан"}'::jsonb,
    '(60.3639,41.3783)'::point,
    'Asia/Tashkent'
);

insert into source_fdw.airports_data (
    airport_code,
    airport_name,
    city,
    country,
    coordinates,
    timezone
)
values (
    'UGC',
    '{"en": "Urgench", "ru": "Ургенч"}'::jsonb,
    '{"en": "Urgench", "ru": "Ургенч"}'::jsonb,
    '{"en": "Uzbekistan", "ru": "Узбекистан"}'::jsonb,
    point(60.6417, 41.5843),
    'Asia/Samarkand'
);


update source_fdw.airports_data
set 
	timezone='Asia/Tashkent'
where  airport_code='TAS'

delete from source_fdw.airports_data
where airport_code='UGC';


call raw.load_airports_data_delta()
