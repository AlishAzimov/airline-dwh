--------------------------------------------------------------------------------------------------------
-- Создание pipeline-процедур: последовательная загрузка данных по слоям RAW → STAGE → ODS → DDS --
--------------------------------------------------------------------------------------------------------


-- Pipeline загрузки самолётов: RAW delta → STAGE → ODS
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

