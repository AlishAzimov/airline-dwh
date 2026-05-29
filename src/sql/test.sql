
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

