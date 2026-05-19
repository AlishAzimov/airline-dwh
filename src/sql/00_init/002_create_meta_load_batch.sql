-- Таблица для контроля запусков загрузки DWH

create table if not exists meta.load_batch (
    batch_id bigserial primary key,
    process_name text not null,
    status text not null,
    started_at timestamp not null default now(),
    finished_at timestamp,
    error_message text
);

select *
from meta.load_batch lb 