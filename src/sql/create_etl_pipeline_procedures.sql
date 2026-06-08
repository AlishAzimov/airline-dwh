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


-- Pipeline загрузки маршрутов: RAW delta - STAGE - ODS - DDS
create or replace procedure meta.load_flights_pipeline()
language plpgsql
as $$
begin
	
	call raw.load_flights_delta();
	call stg.load_flights_from_raw();
	call ods.apply_flights_from_stage();
	call dds.load_fact_flights_from_ods();
end;
$$;



-- Pipeline загрузки маршрутов: RAW delta - STAGE - ODS - DDS
create or replace procedure meta.load_bookings_pipeline()
language plpgsql
as $$
begin
	
	call raw.load_bookings_delta();
	call stg.load_bookings_from_raw();
	call ods.apply_bookings_from_stage();
	call dds.load_fact_bookings_from_ods();
end;
$$;

-- Pipeline загрузки маршрутов: RAW delta - STAGE - ODS - DDS
create or replace procedure meta.load_tickets_pipeline()
language plpgsql
as $$
begin
	
	call raw.load_tickets_delta();
	call stg.load_tickets_from_raw();
	call ods.apply_tickets_from_stage();
	call dds.load_dim_passenger_from_ods(); -- формирование SCD1-измерения пассажиров на основе ods.tickets
	call dds.load_fact_tickets_from_ods();
end;
$$;


-- Pipeline загрузки маршрутов: RAW delta - STAGE - ODS - DDS
create or replace procedure meta.load_segments_pipeline()
language plpgsql
as $$
begin
	
	call raw.load_segments_delta();
	call stg.load_segments_from_raw();
	call ods.apply_segments_from_stage();
	call dds.load_fact_segments_from_ods();
end;
$$;


-- Pipeline загрузки маршрутов: RAW delta - STAGE - ODS - DDS
create or replace procedure meta.load_boarding_passes_pipeline()
language plpgsql
as $$
begin
	
	call raw.load_boarding_passes_delta();
	call stg.load_boarding_passes_from_raw();
	call ods.apply_boarding_passes_from_stage();
	call dds.load_fact_boarding_passes_from_ods();
end;
$$;.

--------------------------------------------------------------------------------------------------------
-- Главный pipeline загрузки данных: RAW → STAGE → ODS → DDS → DM
-- Последовательно обновляет справочники, факты и аналитические витрины для BI
--------------------------------------------------------------------------------------------------------

create or replace procedure meta.load_data_mart_pipeline()
language plpgsql
as $$
begin
	-- Загрузка справочников и фактов в DDS
	call meta.load_airplanes_pipeline();
	call meta.load_airports_pipeline();
	call meta.load_routes_pipeline();
	call meta.load_flights_pipeline();	
	call meta.load_bookings_pipeline();	
	call meta.load_tickets_pipeline();	
	call meta.load_segments_pipeline();

	-- Загрузка и пересчёт DM-витрин для BI
	call dm.load_flight_sales_mart_from_dds();
	call dm.load_flight_revenue_mart_from_flight_sales_mart();
	call dm.load_airport_traffic_daily_from_flight_sales_mart();
end;
$$;



