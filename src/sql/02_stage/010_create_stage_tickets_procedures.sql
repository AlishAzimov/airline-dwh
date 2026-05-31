------------------------------------------------------------------------------------------------------
-- Создание процедур слоя STAGE: загрузка, очистка и валидация данных из RAW перед передачей в ODS --
------------------------------------------------------------------------------------------------------

-- Функция определения batch_id

create or replace function stg.get_tickets_batch_id(p_batch_id bigint default null)
returns bigint
language plpgsql
as $$
declare
    v_batch_id bigint;
begin
    v_batch_id := p_batch_id;

    if v_batch_id is null then
        select max(batch_id)
        into v_batch_id
        from raw.tickets;
    end if;

    if v_batch_id is null then
        raise exception 'No batch_id found in raw.tickets';
    end if;

    return v_batch_id;
end;
$$;


-- Процедура загрузки из RAW в STAGE

create or replace procedure stg.insert_tickets_from_raw(p_batch_id bigint)
language plpgsql
as $$
begin
    if p_batch_id is null then
        raise exception 'p_batch_id cannot be null in stg.insert_tickets_from_raw';
    end if;

    insert into stg.tickets (
        ticket_no,
        book_ref,
        passenger_id,
        passenger_name,
        outbound,
        raw_load_date,
        stg_load_date,
        source_system,
        record_source,
        batch_id,
        operation_type
    )
    select
        nullif(trim(r.ticket_no), '') as ticket_no,
        nullif(trim(r.book_ref::text), '') as book_ref,
        nullif(trim(r.passenger_id), '') as passenger_id,
        nullif(trim(r.passenger_name), '') as passenger_name,
        r.outbound,
        r.load_date as raw_load_date,
        now() as stg_load_date,
        r.source_system,
        r.record_source,
        r.batch_id,
        r.operation_type
    from raw.tickets r
    where r.batch_id = p_batch_id;
end;
$$;


-- Процедура проверки качества данных

create or replace procedure stg.validate_tickets()
language plpgsql
as $$
begin
    update stg.tickets
    set
        is_valid =
            case
                when ticket_no is null then false
                when trim(ticket_no) = '' then false
                when book_ref is null then false
                when trim(book_ref) = '' then false
                when passenger_id is null then false
                when trim(passenger_id) = '' then false
                when passenger_name is null then false
                when trim(passenger_name) = '' then false
                when outbound is null then false
                when operation_type not in ('I', 'U', 'D') then false
                else true
            end,

        validation_error =
            nullif(
                concat_ws(
                    '; ',
                    case
                        when ticket_no is null or trim(ticket_no) = ''
                        then 'ticket_no is empty'
                    end,
                    case
                        when book_ref is null or trim(book_ref) = ''
                        then 'book_ref is empty'
                    end,
                    case
                        when passenger_id is null or trim(passenger_id) = ''
                        then 'passenger_id is empty'
                    end,
                    case
                        when passenger_name is null or trim(passenger_name) = ''
                        then 'passenger_name is empty'
                    end,
                    case
                        when outbound is null
                        then 'outbound is null'
                    end,
                    case
                        when operation_type not in ('I', 'U', 'D')
                        then 'operation_type is invalid'
                    end
                ),
                ''
            );
end;
$$;


-- Главная сборочная процедура

create or replace procedure stg.load_tickets_from_raw(p_batch_id bigint default null)
language plpgsql
as $$
declare
    v_batch_id bigint;
    v_step_started_at timestamptz;
begin
    v_batch_id := stg.get_tickets_batch_id(p_batch_id);

    v_step_started_at := clock_timestamp();

    truncate table stg.tickets;

    raise notice 'truncate table stg.tickets duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call stg.insert_tickets_from_raw(v_batch_id);

    raise notice 'stg.insert_tickets_from_raw duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call stg.validate_tickets();

    raise notice 'stg.validate_tickets duration: %',
        clock_timestamp() - v_step_started_at;


    raise notice 'stg.tickets loaded. batch_id = %, rows = %, invalid rows = %',
        v_batch_id,
        (select count(*) from stg.tickets),
        (select count(*) from stg.tickets where is_valid = false);
end;
$$;