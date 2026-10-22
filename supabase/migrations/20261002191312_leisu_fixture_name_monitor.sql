alter table public.football_feature_matches
  add column if not exists canonical_name_source text,
  add column if not exists canonical_name_checked_at timestamptz;
create table if not exists public.football_name_sync_runs (
  id uuid primary key default gen_random_uuid(),
  source text not null check (source in ('leisu')),
  status text not null check (status in ('running','completed','failed')),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  source_rows integer not null default 0,
  candidate_rows integer not null default 0,
  matched integer not null default 0,
  updated integer not null default 0,
  conflicts integer not null default 0,
  ambiguous integer not null default 0,
  error_message text
);
create table if not exists public.football_name_comparisons (
  id bigint generated always as identity primary key,
  run_id uuid not null references public.football_name_sync_runs(id) on delete cascade,
  match_key text not null references public.football_feature_matches(match_key) on delete cascade,
  source text not null,
  source_match_id text not null,
  source_url text not null,
  source_competition_name text not null,
  source_home_team text not null,
  source_away_team text not null,
  confidence numeric(4,3) not null,
  outcome text not null check (outcome in ('applied','conflict')),
  applied boolean not null default false,
  observed_at timestamptz not null default now()
);
create index if not exists football_name_sync_runs_started_idx on public.football_name_sync_runs(started_at desc);
create index if not exists football_name_comparisons_match_idx on public.football_name_comparisons(match_key, observed_at desc);
alter table public.football_name_sync_runs enable row level security;
alter table public.football_name_comparisons enable row level security;
revoke all on public.football_name_sync_runs from anon, authenticated;
revoke all on public.football_name_comparisons from anon, authenticated;
grant all on public.football_name_sync_runs to service_role;
grant all on public.football_name_comparisons to service_role;
grant usage, select on sequence public.football_name_comparisons_id_seq to service_role;
do $$
declare existing_job bigint;
begin
  select jobid into existing_job from cron.job where jobname = 'football-leisu-name-sync';
  if existing_job is not null then perform cron.unschedule(existing_job); end if;
end $$;
select cron.schedule(
  'football-leisu-name-sync',
  '3,18,33,48 * * * *',
  $job$
    select net.http_post(
      url := 'https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/football-name-sync',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-scan-key', (select scan_key from public.ah0_scanner_config where id = true)
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 60000
    );
  $job$
);
