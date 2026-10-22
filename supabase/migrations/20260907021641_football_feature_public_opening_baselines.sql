create table public.football_feature_opening_baselines (
  match_key text not null references public.football_feature_matches(match_key) on delete cascade,
  bookmaker text not null,
  source_platform text not null,
  source_url text not null check (source_url ~ '^https://'),
  first_observed_at timestamptz not null,
  first_home_handicap numeric not null,
  first_home_odds numeric,
  first_away_odds numeric,
  primary key (match_key, bookmaker)
);

alter table public.football_feature_opening_baselines enable row level security;
revoke all on public.football_feature_opening_baselines from anon, authenticated;
grant all on public.football_feature_opening_baselines to service_role;

comment on table public.football_feature_opening_baselines is
  'First line observed by the public-page scanner. This is a sampling baseline and must not be described as the bookmaker official opening line.';
;
