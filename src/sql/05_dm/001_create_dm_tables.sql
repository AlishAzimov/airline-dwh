
-----------------------------------------------------------------------------------------------
-- Создание таблиц слоя DDS: измерения и факты для аналитической модели данных --
-----------------------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS dm.flight_sales_mart (











)


select
    s.ticket_no,
    s.flight_id,
    t.book_ref,
    t.passenger_id,
    p.passenger_name,
    f.route_no,
    r.departure_airport,
    dep.airport_name_en as departure_airport_name,
    r.arrival_airport,
    arr.airport_name_en as arrival_airport_name,
    r.airplane_code,
    a.model_en as airplane_model,
    s.fare_conditions,
    s.price,
    b.book_date,
    f.scheduled_departure,
    f.scheduled_arrival,
    f.actual_departure,
    f.actual_arrival,
    f.status,
    t.outbound,
    greatest(
        s.batch_id,
        t.batch_id,
        b.batch_id,
        f.batch_id,
        r.batch_id,
        dep.batch_id,
        arr.batch_id,
        a.batch_id,
        p.batch_id
    ) as source_max_batch_id
from dds.fact_segments s
left join dds.fact_tickets t
    on s.ticket_sk = t.ticket_sk
left join dds.fact_bookings b
    on t.bookings_sk = b.bookings_sk
left join dds.fact_flights f
    on s.flight_sk = f.flight_sk
left join dds.dim_routes r
    on f.route_sk = r.route_sk
left join dds.dim_airports dep
    on r.departure_airport_sk = dep.airport_sk
left join dds.dim_airports arr
    on r.arrival_airport_sk = arr.airport_sk
left join dds.dim_airplanes a
    on r.airplane_sk = a.airplane_sk
left join dds.dim_passenger p
    on t.passenger_sk = p.passenger_sk
where s.is_deleted = false;