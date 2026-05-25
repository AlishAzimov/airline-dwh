

--------------------------------------------------------------------------------------------
-- RAW CDC snapshot: хранит последнее состояние таблиц в source для определения I/U/D --
--------------------------------------------------------------------------------------------

--bookings

CREATE table if not exists raw.bookings_snapshot (
	book_ref text primary key,
	book_date timestamptz ,
	total_amount numeric(10, 2),
	-- технические поля
	raw_row_hash text not null, -- хеш строки для проверки изменений
	last_seen_at timestamptz not null default now() -- дата последнего фиксирование строки в source
);
	
	
--tickets

CREATE table if not exists raw.tickets_snapshot (
	ticket_no text primary key,
	book_ref text,
	passenger_id text,
	passenger_name text,
	outbound bool,
	-- технические поля
	raw_row_hash text not null, -- хеш строки для проверки изменений
	last_seen_at timestamptz not null default now() -- дата последнего фиксирование строки в source
);
	
	
--select count(*) from raw.bookings_snapshot 






select * from raw.tickets_snapshot












