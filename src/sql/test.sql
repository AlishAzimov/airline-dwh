
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
