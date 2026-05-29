
-- test stg.airplanes/ods.airplanes


call ods.apply_airplanes_from_stage()

select * from ods.airplanes a 

select * from stg.airplanes a 

select distinct	batch_id from raw.airplanes_data 

select * from source_fdw.airplanes_data 

call stg.load_airplanes_from_raw(42);
call ods.apply_airplanes_from_stage();

