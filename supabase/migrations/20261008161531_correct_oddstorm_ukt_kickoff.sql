-- OddStorm's UKT schedule uses fixed UTC. Before 2026-10-08 16:13:21 UTC,
-- both scanners incorrectly applied British Summer Time and stored UTC-1.
-- Preserve every original canonical timestamp for audit and safe rollback.
create table if not exists public.football_kickoff_time_corrections (
  dataset text not null,
  match_key text not null,
  old_kickoff_at timestamptz not null,
  new_kickoff_at timestamptz not null,
  reason text not null,
  corrected_at timestamptz not null default now(),
  primary key (dataset, match_key)
);
alter table public.football_kickoff_time_corrections enable row level security;

insert into public.football_kickoff_time_corrections
  (dataset, match_key, old_kickoff_at, new_kickoff_at, reason)
select 'football_feature_matches', match_key, kickoff_at, kickoff_at + interval '1 hour',
       'OddStorm UKT treated as British Summer Time instead of UTC'
from public.football_feature_matches
where match_key like 'oddstorm:%'
  and first_seen_at < '2026-10-08 16:13:21+00'::timestamptz
  and last_seen_at < '2026-10-08 16:13:21+00'::timestamptz
  and kickoff_at >= '2026-03-29 01:00+00'::timestamptz
  and kickoff_at < '2026-10-25 01:00+00'::timestamptz
on conflict (dataset, match_key) do nothing;

insert into public.football_kickoff_time_corrections
  (dataset, match_key, old_kickoff_at, new_kickoff_at, reason)
select 'under3_low_odds_matches', match_key, kickoff_at, kickoff_at + interval '1 hour',
       'OddStorm UKT treated as British Summer Time instead of UTC'
from public.under3_low_odds_matches
where match_key like 'oddstorm:%'
  and first_seen_at < '2026-10-08 16:13:21+00'::timestamptz
  and last_seen_at < '2026-10-08 16:13:21+00'::timestamptz
  and kickoff_at >= '2026-03-29 01:00+00'::timestamptz
  and kickoff_at < '2026-10-25 01:00+00'::timestamptz
on conflict (dataset, match_key) do nothing;

update public.football_feature_matches m
set kickoff_at = c.new_kickoff_at
from public.football_kickoff_time_corrections c
where c.dataset = 'football_feature_matches'
  and c.match_key = m.match_key and m.kickoff_at = c.old_kickoff_at;

update public.under3_low_odds_matches m
set kickoff_at = c.new_kickoff_at
from public.football_kickoff_time_corrections c
where c.dataset = 'under3_low_odds_matches'
  and c.match_key = m.match_key and m.kickoff_at = c.old_kickoff_at;

update public.football_feature_source_identities s
set kickoff_at = c.new_kickoff_at
from public.football_kickoff_time_corrections c
where c.dataset = 'football_feature_matches'
  and c.match_key = s.match_key and s.kickoff_at = c.old_kickoff_at;

update public.football_feature_observations o
set payload = jsonb_set(o.payload, '{kickoff_at}', to_jsonb(c.new_kickoff_at::text))
from public.football_kickoff_time_corrections c
where c.dataset = 'football_feature_matches'
  and c.match_key = o.match_key
  and (o.payload->>'kickoff_at')::timestamptz = c.old_kickoff_at;

update public.bet_records b
set kickoff_at = c.new_kickoff_at
from public.football_kickoff_time_corrections c
where c.match_key = b.match_key and b.kickoff_at = c.old_kickoff_at;

update public.match_favorites f
set kickoff_at = c.new_kickoff_at
from public.football_kickoff_time_corrections c
where c.match_key = f.match_key and f.kickoff_at = c.old_kickoff_at;

update public.football_name_unresolved n
set kickoff_at = c.new_kickoff_at
from public.football_kickoff_time_corrections c
where c.match_key = n.match_key and n.kickoff_at = c.old_kickoff_at;
;
