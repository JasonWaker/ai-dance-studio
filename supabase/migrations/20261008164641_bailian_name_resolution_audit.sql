alter table public.football_name_sync_runs
  add column if not exists ai_attempted integer not null default 0,
  add column if not exists ai_accepted integer not null default 0;
create table if not exists public.football_name_ai_attempts (
  id bigint generated always as identity primary key,
  run_id uuid references public.football_name_sync_runs(id) on delete set null,
  match_key text not null references public.football_feature_matches(match_key) on delete cascade,
  provider text not null default 'alibaba_bailian' check (provider = 'alibaba_bailian'),
  model text not null default 'qwen-plus',
  status text not null check (status in ('accepted', 'rejected', 'error')),
  proposed_names jsonb not null default '{}'::jsonb,
  source_links jsonb not null default '[]'::jsonb,
  confidence numeric(4,3),
  reason text,
  attempted_at timestamptz not null default now()
);
create index if not exists football_name_ai_attempts_recent_idx on public.football_name_ai_attempts(attempted_at desc);
create index if not exists football_name_ai_attempts_match_idx on public.football_name_ai_attempts(match_key, attempted_at desc);
alter table public.football_name_ai_attempts enable row level security;
revoke all on public.football_name_ai_attempts from anon, authenticated;
grant all on public.football_name_ai_attempts to service_role;
grant usage, select on sequence public.football_name_ai_attempts_id_seq to service_role;;
