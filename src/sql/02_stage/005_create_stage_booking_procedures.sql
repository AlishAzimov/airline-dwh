------------------------------------------------------------------------------------------------------
-- Создание процедур слоя STAGE: загрузка, очистка и валидация данных из RAW перед передачей в ODS --
------------------------------------------------------------------------------------------------------


-- Функция определения batch_id

create or replace function stg.get_bookings_batch_id(p_batch_id bigint default null)
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
        from raw.bookings;
    end if;

    if v_batch_id is null then
        raise exception 'No batch_id found in raw.bookings';
    end if;

    return v_batch_id;
end;
$$;


-- Процедура загрузки из RAW в STAGE

create or replace procedure stg.insert_bookings_from_raw(p_batch_id bigint)
language plpgsql
as $$
begin
    if p_batch_id is null then
        raise exception 'p_batch_id cannot be null in stg.insert_bookings_from_raw';
    end if;

    insert into stg.bookings (
        book_ref,
        book_date,
        total_amount,
        raw_load_date,
        stg_load_date,
        source_system,
        record_source,
        batch_id,
        operation_type
    )
    select
        nullif(trim(r.book_ref::text), '') as book_ref,
        r.book_date,
        r.total_amount,
        r.load_date as raw_load_date,
        now() as stg_load_date,
        r.source_system,
        r.record_source,
        r.batch_id,
        r.operation_type
    from raw.bookings r
    where r.batch_id = p_batch_id;
end;
$$;


-- Процедура проверки качества данных

create or replace procedure stg.validate_bookings()
language plpgsql
as $$
begin
    update stg.bookings
    set
        is_valid =
            case
                when book_ref is null then false
                when trim(book_ref) = '' then false
                when book_date is null then false
                when total_amount is null then false
                when total_amount < 0 then false
                when operation_type not in ('I', 'U', 'D') then false
                else true
            end,

        validation_error =
            nullif(
                concat_ws(
                    '; ',
                    case
                        when book_ref is null or trim(book_ref) = ''
                        then 'book_ref is empty'
                    end,
                    case
                        when book_date is null
                        then 'book_date is null'
                    end,
                    case
                        when total_amount is null
                        then 'total_amount is null'
                    end,
                    case
                        when total_amount < 0
                        then 'total_amount must be greater than or equal to 0'
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

create or replace procedure stg.load_bookings_from_raw(p_batch_id bigint default null)
language plpgsql
as $$
declare
    v_batch_id bigint;
    v_step_started_at timestamptz;
begin
    v_batch_id := stg.get_bookings_batch_id(p_batch_id);

    v_step_started_at := clock_timestamp();

    truncate table stg.bookings;

    raise notice 'truncate table stg.bookings duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call stg.insert_bookings_from_raw(v_batch_id);

    raise notice 'stg.insert_bookings_from_raw duration: %',
        clock_timestamp() - v_step_started_at;


    v_step_started_at := clock_timestamp();

    call stg.validate_bookings();

    raise notice 'stg.validate_bookings duration: %',
        clock_timestamp() - v_step_started_at;


    raise notice 'stg.bookings loaded. batch_id = %, rows = %, invalid rows = %',
        v_batch_id,
        (select count(*) from stg.bookings),
        (select count(*) from stg.bookings where is_valid = false);
end;
$$;