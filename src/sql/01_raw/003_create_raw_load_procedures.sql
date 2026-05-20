

create or replace procedure raw.load_bookings_initial()
language plpgsql
as $$
declare
	v_batch_id bigint;
begin
	
	-- Создаем ифномацию о загрузке в meta.load_batch и поулчаем ID загрузки
	insert into meta.load_batch(process_name,status,started_at)
	values ('raw.load_bookings_initial','RUNNING',now())
	returning batch_id into v_batch_id;
	
	-- Забираем данные из source.booking таблицы
	insert into raw.bookings(
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
	from source_fdw.bookings b;
	
	-- Обyновляем meta.load_batch
	update meta.load_batch
	set status = 'SUCCESS',
	    finished_at = now()
	where batch_id = v_batch_id;
	
	-- обрабокта ошибки
exception
	when others then
		update meta.load_batch
		set status = 'FAILED',
			finished_at = now(),
		    error_message = sqlerrm
		where batch_id = v_batch_id;
		
		raise;

end
$$;




call raw.load_bookings_initial()


select count(*) from raw.bookings


select * from meta.load_batch limit 10


select count(*) as source_count
from source_fdw.bookings;
