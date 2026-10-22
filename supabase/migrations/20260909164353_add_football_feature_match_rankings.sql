alter table public.football_feature_matches
  add column if not exists home_rank smallint,
  add column if not exists away_rank smallint;

alter table public.football_feature_matches
  drop constraint if exists football_feature_matches_home_rank_check,
  add constraint football_feature_matches_home_rank_check
    check (home_rank is null or home_rank between 1 and 999),
  drop constraint if exists football_feature_matches_away_rank_check,
  add constraint football_feature_matches_away_rank_check
    check (away_rank is null or away_rank between 1 and 999);

with latest_rank as (
  select distinct on (match_key)
    match_key,
    (payload->>'home_rank')::smallint as home_rank,
    (payload->>'away_rank')::smallint as away_rank
  from public.football_feature_observations
  where payload->>'home_rank' ~ '^[1-9][0-9]{0,2}$'
    and payload->>'away_rank' ~ '^[1-9][0-9]{0,2}$'
  order by match_key, observed_at desc
)
update public.football_feature_matches as matches
set home_rank = latest_rank.home_rank,
    away_rank = latest_rank.away_rank
from latest_rank
where matches.match_key = latest_rank.match_key;

comment on column public.football_feature_matches.home_rank is
  'Verified league position for the home team at the latest public scan; null for unavailable or non-league fixtures.';
comment on column public.football_feature_matches.away_rank is
  'Verified league position for the away team at the latest public scan; null for unavailable or non-league fixtures.';;
