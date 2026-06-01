--------------------------------------------------------------------------------------------------------
-- Создание pipeline-процедур: последовательная загрузка данных по слоям RAW → STAGE → ODS → DDS --
--------------------------------------------------------------------------------------------------------


-- Pipeline загрузки самолётов: RAW delta - STAGE - ODS - DDS
create or replace procedure meta.load_airplanes_pipeline()
language plpgsql
as $$
begin
	
	call raw.load_airplanes_data_delta();
	call stg.load_airplanes_from_raw();
	call ods.apply_airplanes_from_stage();
	call dds.load_dim_airplanes_from_ods();
end;
$$;



-- Pipeline загрузки аэропортов: RAW delta - STAGE - ODS - DDS
create or replace procedure meta.load_airports_pipeline()
language plpgsql
as $$
begin
	
	call raw.load_airports_data_delta();
	call stg.load_airports_from_raw();
	call ods.apply_airports_from_stage();
	call dds.load_dim_airports_from_ods();
end;
$$;

-- Pipeline загрузки маршрутов: RAW delta - STAGE - ODS - DDS
create or replace procedure meta.load_routes_pipeline()
language plpgsql
as $$
begin
	
	call raw.load_routes_delta();
	call stg.load_routes_from_raw();
	call ods.apply_routes_from_stage();
	call dds.load_dim_routes_from_ods();
end;
$$;


-- Pipeline загрузки маршрутов: RAW delta - STAGE - ODS - DDS
create or replace procedure meta.load_seats_pipeline()
language plpgsql
as $$
begin
	
	call raw.load_seats_delta();
	call stg.load_seats_from_raw();
	call ods.apply_seats_from_stage();
	call dds.load_dim_seats_from_ods();
end;
$$;