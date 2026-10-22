alter table public.bet_records
  add column if not exists note text not null default ''
  check (char_length(note) <= 1000);
comment on column public.bet_records.note is 'User note attached to this specific active or cancelled betting commitment.';
