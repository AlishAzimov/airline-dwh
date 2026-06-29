--------------------------------------------------------------------------------------------------------
-- Создание процедур слоя DDS: загрузка фактов Билетов из ODS в DDS --
--------------------------------------------------------------------------------------------------------


-- Процедура I/U/D: вставка новых и обновление существующих билетов

create or replace procedure dds.upsert_fact_tickets_from_ods()
language plpgsql
as $$
declare
    v_last_loaded_batch_id bigint;
begin	
	
    select coalesce(max(batch_id), 0)
    into v_last_loaded_batch_id
    from dds.fact_tickets;

    insert into dds.fact_tickets (
 		ticket_sk,
       	bookings_sk, 
		passenger_sk,
        ticket_no,
		outbound,	
        source_system,
        record_source,
        batch_id,
        last_changed_at,
        is_deleted
    )

    select
		md5(o.ticket_no || '|' || o.source_system)::uuid as ticket_sk,
	 	fb.bookings_sk, 
		dp.passenger_sk,
        o.ticket_no,
        o.outbound,
        o.source_system,
        o.record_source,
        o.updated_batch_id as batch_id,
        now() as last_changed_at,
        o.is_deleted
    from ods.tickets o
	join dds.fact_bookings fb 
		on o.book_ref=fb.book_ref
	join dds.dim_passenger dp
		on o.passenger_id=dp.passenger_id
	where o.updated_batch_id > v_last_loaded_batch_id
		and o.ticket_no is not null

    on conflict (ticket_no) do update
    set
		bookings_sk = excluded.bookings_sk,
		passenger_sk = excluded.passenger_sk,
        outbound = excluded.outbound,
        source_system = excluded.source_system,
        record_source = excluded.record_source,
        batch_id = excluded.batch_id,
        last_changed_at = now(),
        is_deleted = excluded.is_deleted
	where dds.fact_tickets.batch_id < excluded.batch_id;

end;
$$;


-- Главная сборочная процедура

create or replace procedure dds.load_fact_tickets_from_ods()
language plpgsql
as $$
declare
    v_step_started_at timestamptz;
begin
    v_step_started_at := clock_timestamp();

    call dds.upsert_fact_tickets_from_ods();

    raise notice 'dds.upsert_fact_tickets_from_ods duration: %',
        clock_timestamp() - v_step_started_at;

    raise notice 'dds.fact_tickets loaded. rows = %, active rows = %, deleted rows = %',
        (select count(*) from dds.fact_tickets),
        (select count(*) from dds.fact_tickets where is_deleted = false),
        (select count(*) from dds.fact_tickets where is_deleted = true);
end;
$$;