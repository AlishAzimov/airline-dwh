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


