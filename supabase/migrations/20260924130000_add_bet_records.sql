create table if not exists public.bet_records (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  match_key text not null check (char_length(match_key) between 1 and 160),
  kickoff_at timestamptz not null,
  competition_name text not null default '' check (char_length(competition_name) <= 160),
  home_team text not null check (char_length(home_team) between 1 and 160),
  away_team text not null check (char_length(away_team) between 1 and 160),
  source_path text not null default '' check (char_length(source_path) <= 500),
  feature_kinds text[] not null default '{}',
  placed_at timestamptz not null default now(),
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint bet_records_cancelled_after_created check (cancelled_at is null or cancelled_at >= created_at)
);
comment on table public.bet_records is 'User-confirmed betting commitments. Cancellation is retained for self-control auditing.';
comment on column public.bet_records.placed_at is 'The explicit moment the user marked the match as bet.';
comment on column public.bet_records.cancelled_at is 'Soft cancellation timestamp; active lists only show NULL.';
create unique index if not exists bet_records_one_active_match_idx
  on public.bet_records (user_id, match_key)
  where cancelled_at is null;
create index if not exists bet_records_user_kickoff_active_idx
  on public.bet_records (user_id, kickoff_at desc, id desc)
  where cancelled_at is null;
alter table public.bet_records enable row level security;
create policy "bet records are readable by their owner"
  on public.bet_records for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "bet records are insertable by their owner"
  on public.bet_records for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "bet records are updatable by their owner"
  on public.bet_records for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
grant select, insert, update on public.bet_records to authenticated;
grant usage, select on sequence public.bet_records_id_seq to authenticated;
