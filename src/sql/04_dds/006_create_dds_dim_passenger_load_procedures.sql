--------------------------------------------------------------------------------------------------------
-- Создание процедур слоя DDS: загрузка SCD1-измерения пассажиров из ODS в DDS --
--------------------------------------------------------------------------------------------------------


-- Процедура I/U/D: вставка новых и обновление существующих пассажиров
create or replace procedure dds.upsert_dim_passenger_from_ods()
language plpgsql
as $$

declare
    v_last_loaded_batch_id bigint;
begin

    select coalesce(max(batch_id), 0)
    into v_last_loaded_batch_id
    from dds.dim_passenger;

insert into dds.dim_passenger(
		passenger_id,
		passenger_name,
		source_system,
		record_source,
		batch_id,
		last_changed_at
		)
	select distinct on (passenger_id)
	    o.passenger_id,
	    o.passenger_name,
	    o.source_system,
	    o.record_source,
	    o.updated_batch_id as batch_id,
		now() as last_changed_at
	from ods.tickets o
	where passenger_id is not null 
	and o.updated_batch_id > v_last_loaded_batch_id
	order by passenger_id, updated_batch_id desc
	
	on conflict (passenger_id) do update
    set
        passenger_name = excluded.passenger_name,
        source_system = excluded.source_system,
        record_source = excluded.record_source,
        batch_id = excluded.batch_id,
        last_changed_at = now();

end;
$$;



-- Главная сборочная процедур

create or replace procedure dds.load_dim_passenger_from_ods()
language plpgsql
as $$
declare
    v_step_started_at timestamptz;
begin
    v_step_started_at := clock_timestamp();

    call dds.upsert_dim_passenger_from_ods();

    raise notice 'dds.upsert_dim_passenger_from_ods duration: %',
        clock_timestamp() - v_step_started_at;

    raise notice 'dds.dim_passenger loaded. rows = %',
        (select count(*) from dds.dim_passenger);
end;
$$;