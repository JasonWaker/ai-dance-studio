alter table public.football_feature_matches
  add column if not exists last_pre_match_market_at timestamptz,
  add column if not exists last_pre_match_market jsonb not null default '{}'::jsonb;

create index if not exists football_feature_matches_market_observed_idx
  on public.football_feature_matches (last_pre_match_market_at desc);

comment on column public.football_feature_matches.last_pre_match_market is
  'Last reliable pre-kickoff market-median snapshot. Decimal prices are rounded to two decimal places.';
;
