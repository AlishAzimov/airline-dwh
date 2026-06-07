
--------------------------------------------------------------------------------------------------------
-- TEST DDS --
--------------------------------------------------------------------------------------------------------

-- test dds.dim_airplanes

call dds.load_dim_airplanes_from_ods()


select * from dds.dim_airplanes a 

insert into source_fdw.airplanes_data (
    airplane_code,
    model,
    "range",
    speed
)
values (
    '740',
    '{"en": "Boeing 737-800", "ru": "Боинг 737-800"}'::jsonb,
   5765,
    850
);


update source_fdw.airplanes_data
set speed = 855
where airplane_code = '76F';

call meta.load_airplanes_pipeline()

delete from source_fdw.airplanes_data
where airplane_code='738';

call meta.load_airplanes_pipeline()



-- test dds.dim_airports


call dds.load_dim_airports_from_ods()

select * from dds.dim_airports a 
where country_en ilike 'uzb%' 



insert into source_fdw.airports_data (
    airport_code,
    airport_name,
    city,
    country,
    coordinates,
    timezone
)
values (
    'UGH',
    '{"en": "Urgench", "ru": "Ургенч"}'::jsonb,
    '{"en": "Urgench", "ru": "Ургенч"}'::jsonb,
    '{"en": "Uzbekistan", "ru": "Узбекистан"}'::jsonb,
    point(60.6417, 41.5843),
    'Asia/Samarkand'
);


update source_fdw.airports_data
set 
	timezone='Asia/Tashkent'
where  airport_code='NVI'

delete from source_fdw.airports_data
where airport_code='UGH';

call meta.load_airports_pipeline()




-- test dds.dim_routes

call dds.load_dim_routes_from_ods()

select * from dds.dim_routes



insert into 
	source_fdw.routes(
	 	route_no,
		validity,
		departure_airport,
		arrival_airport,
		airplane_code,
		days_of_week,
		scheduled_time,
		duration)
values ('PG1900',
		'["2027-11-01 05:00:00+05","2027-12-01 05:00:00+05")'::tstzrange, 
		'DEN', 
		'ARN', 
		'789',
		array[2, 4, 6],
		'11:00:00',
		 interval '10 hours'
		);



update source_fdw.routes
set 
	days_of_week=array[1, 3, 5]
where route_no='PG0167' and validity = '["2027-10-01 05:00:00+05","2027-11-01 05:00:00+05")'::tstzrange;


delete from source_fdw.routes
where route_no='PG1797' and validity = '["2027-10-01 05:00:00+05","2027-11-01 05:00:00+05")'::tstzrange;


call meta.load_routes_pipeline()

-- test dds.dim_routes seats

call meta.load_seats_pipeline()

select * from dds.dim_seats order by batch_id desc

select distinct batch_id from dds.dim_seats 


insert into source_fdw.seats (
    airplane_code,
	seat_no,
	fare_conditions
)
values (
    '32N',
    '0B',
    'Business'
);


update source_fdw.seats
set fare_conditions = 'Comfort'
where airplane_code = '32N' and seat_no = '0B';

delete from source_fdw.seats
where airplane_code = '32N' and seat_no = '0B';


-- test dds.dim_passanger 

call dds.upsert_dim_passenger_from_ods()

select *
from dds.dim_passenger
limit 10



-- test dds.fact_flights

call dds.load_fact_flights_from_ods()

select *
from dds.fact_flights
where is_deleted = true
limit 10

call meta.load_flights_pipeline()



-- test dds.fact_bookings

call dds.load_fact_bookings_from_ods(); 

select * from dds.fact_bookings order by last_changed_at desc limit 20

update source_fdw.bookings
set total_amount = 4500.00
where book_ref = '96IRDX';

call meta.load_bookings_pipeline()


-- test dds.fact_tickets

call dds.load_fact_tickets_from_ods();

select * from dds.fact_tickets where ticket_no ='0005453207701'

insert into 
	source_fdw.tickets(
			ticket_no,
			book_ref,
			passenger_id,
			passenger_name,
			outbound)
values ('0005453207701', 'OJ1F1D', 'UZ 9000000000001', 'Ali Azimov', false);

call meta.load_tickets_pipeline();


-- test dds.fact_segments

call dds.load_fact_segments_from_ods();

select * from dds.fact_segments order by batch_id desc limit 10 

update source_fdw.segments
set 
	fare_conditions='Comfort',
	price=10001.00
where ticket_no='0005453207644' 
and flight_id=135087

call meta.load_segments_pipeline()


-- test dds.boarding_passes

call dds.load_fact_boarding_passes_from_ods();

select * from dds.fact_boarding_passes order by batch_id desc, ticket_sk asc limit 10

update source_fdw.boarding_passes
set 
	boarding_no=3000
where ticket_no='0005432253980' 
and flight_id=27

call meta.load_boarding_passes_pipeline();

--------------------------------------------------------------------------------------------------------
-- TEST STG and ODS --
--------------------------------------------------------------------------------------------------------



-- test stg.airplanes/ods.airplanes


call ods.apply_airplanes_from_stage()

select * from ods.airplanes a 

select * from stg.airplanes a 

select distinct	batch_id from raw.airplanes_data 

select * from source_fdw.airplanes_data 

call stg.load_airplanes_from_raw(42);
call ods.apply_airplanes_from_stage();



-- test stg.airports/ods.airports

select distinct	batch_id from raw.airports_data 

call stg.load_airports_from_raw(35)

select * from stg.airports a 

call ods.apply_airports_from_stage()

select * from ods.airports a order by last_changed_at desc



-- test stg.boarding_passes/ods.boarding_passes

select distinct	batch_id from raw.boarding_passes

call stg.load_boarding_passes_from_raw(27)

select * from stg.boarding_passes limit 20

call ods.apply_boarding_passes_from_stage()

select * from ods.boarding_passes order by last_changed_at desc limit 20



-- test stg.bookings/ods.bookings

select distinct	batch_id from raw.bookings

call stg.load_bookings_from_raw(8)

select * from stg.bookings limit 20

call ods.apply_bookings_from_stage()

select * from ods.bookings order by last_changed_at desc limit 20




-- test stg.flightss/ods.flights

select distinct	batch_id from raw.flights

call stg.load_flights_from_raw()

select * from stg.flights limit 20

call ods.apply_flights_from_stage()

select * from ods.flights order by last_changed_at desc limit 20



-- test stg.routes/ods.routes

select distinct	batch_id from raw.routes

call stg.load_routes_from_raw()

select * from stg.routes limit 20

call ods.apply_routes_from_stage()

select * from ods.routes order by last_changed_at desc limit 20


-- test stg.seats/ods.seats

select distinct	batch_id from raw.seats

call stg.load_seats_from_raw()

select * from stg.seats limit 20

call ods.apply_seats_from_stage()

select * from ods.seats order by last_changed_at desc limit 20



-- test stg.segments/ods.segments

select distinct	batch_id from raw.segments

call stg.load_segments_from_raw()

select * from stg.segments limit 20

call ods.apply_segments_from_stage()

select * from ods.segments order by last_changed_at desc limit 20


-- test stg.tickets/ods.tickets 

select distinct	batch_id from raw.tickets 

call stg.load_tickets_from_raw()

select * from stg.tickets limit 20

call ods.apply_tickets_from_stage()

select * from ods.tickets order by last_changed_at desc limit 20
