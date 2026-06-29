--------------------------------------------------------------------------------------------
-- Создание объектов слоя DQ: хранение результатов PMI-проверок качества данных и миграции --
--------------------------------------------------------------------------------------------


create table if not exists dq.pmi_results (
    pmi_result_id bigserial not null, -- технический первичный ключ результата проверки

    check_id text not null,           -- код проверки: RC-01, SCD2-01, DUP-01, AGG-01
    check_type text not null,         -- категория проверки: row_count/ scd2 / duplicate / aggregate
    layer_from text not null,         -- слой-источник проверки: source / raw / stg / ods / dds / dm
    layer_to text not null,           -- слой-цель проверки: source / raw / stg / ods / dds / dm
    object_name text not null,        -- проверяемый объект: dim_airplanes, dim_seats, fact_flights
    description text,                 -- человекочитаемое пояснение для PMI-отчёта

    src_value numeric,                -- значение слева: источник стыка
    dwh_value numeric,                -- значение справа: цель стыка
    diff numeric,                     -- разница: src_value - dwh_value

    status text not null,             -- результат проверки: PASS / FAIL / WARN
    run_id bigint not null,           -- id прогона PMI, чтобы хранить историю запусков
    checked_at timestamptz not null default now(), -- дата и время выполнения проверки

    constraint pk_dq_pmi_results primary key (pmi_result_id),

    constraint chk_dq_pmi_results_status
        check (status in ('PASS', 'FAIL', 'WARN')),

    constraint chk_dq_pmi_results_layers
        check (layer_from in ('source', 'raw', 'stg', 'ods', 'dds', 'dm')),

    constraint chk_dq_pmi_results_layer_to
        check ( layer_to in ('raw', 'stg', 'ods', 'dds', 'dm'))
);



create sequence if not exists dq.pmi_run_seq;