-- Stable aliases are private scanner state, never a browser-writable API.
create table if not exists public.football_feature_source_identities (
  source_key text primary key,
  source_platform text not null,
  source_event_id text not null,
  match_key text not null references public.football_feature_matches(match_key),
  source_url text,
  competition_name text,
  home_team text,
  away_team text,
  kickoff_at timestamptz,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  unique (source_platform, source_event_id)
);
create index if not exists football_feature_source_identities_match_idx
  on public.football_feature_source_identities(match_key);
alter table public.football_feature_source_identities enable row level security;
revoke all on table public.football_feature_source_identities from anon, authenticated;
grant all on table public.football_feature_source_identities to service_role;

create table if not exists public.football_feature_identity_conflicts (
  id bigint generated always as identity primary key,
  source_key text not null,
  match_key text,
  reason text not null,
  evidence jsonb not null default '{}'::jsonb,
  detected_at timestamptz not null default now()
);
create index if not exists football_feature_identity_conflicts_detected_idx
  on public.football_feature_identity_conflicts(detected_at desc);
alter table public.football_feature_identity_conflicts enable row level security;
revoke all on table public.football_feature_identity_conflicts from anon, authenticated;
grant all on table public.football_feature_identity_conflicts to service_role;
;
