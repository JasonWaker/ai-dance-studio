-- MFDR v1 is an independent decision system. It consumes raw feature facts and
-- pre-match market snapshots only; no existing recommendation column/table is
-- referenced by this schema, its functions, or its scheduled jobs.

create table public.multi_feature_runs (
  id uuid primary key default gen_random_uuid(),
  trigger_source text not null check (trigger_source in ('cron','admin','market_change','feature_change','settlement')),
  status text not null default 'running' check (status in ('running','success','partial','failed')),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  matches_scanned integer not null default 0,
  matches_eligible integer not null default 0,
  decisions_written integer not null default 0,
  settled integer not null default 0,
  coverage jsonb not null default '{}'::jsonb,
  error_summary text
);

create table public.multi_feature_signals (
  id uuid primary key default gen_random_uuid(),
  match_key text not null references public.football_feature_matches(match_key) on delete cascade,
  source_signal_id uuid not null references public.football_feature_signals(id) on delete cascade,
  feature_code text not null,
  feature_name_cn text not null,
  feature_category text not null check (feature_category in ('market_anomaly','match_structure','context','historical_trend')),
  feature_group text not null,
  market_type text not null check (market_type in ('asian_handicap','total_goals')),
  direction text not null check (direction in ('home','away','over','under')),
  direction_score smallint not null check (direction_score between -3 and 3),
  category_weight numeric(5,3) not null check (category_weight between 0 and 2),
  reliability numeric(5,4) not null check (reliability between 0 and 1),
  effective_score numeric(8,4) not null,
  triggered_at timestamptz not null,
  trigger_line numeric(8,3),
  trigger_odds numeric(8,3),
  trigger_bookmaker text,
  status text not null default 'active' check (status in ('active','weakened','invalidated')),
  status_reason text,
  source_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(source_signal_id, market_type, direction)
);

create table public.multi_feature_decisions (
  id uuid primary key default gen_random_uuid(),
  match_key text not null references public.football_feature_matches(match_key) on delete cascade,
  decision_rank smallint not null check (decision_rank in (1,2)),
  decision_status text not null check (decision_status in ('RECOMMEND','WAIT')),
  market_type text not null check (market_type in ('asian_handicap','total_goals')),
  selection text not null check (selection in ('home','away','over','under')),
  market_line numeric(8,3) not null,
  market_odds numeric(8,3) not null,
  bookmaker text,
  market_observed_at timestamptz,
  model_fair_line numeric(8,3) not null,
  model_probability numeric(8,6) not null check (model_probability between 0 and 1),
  fair_odds numeric(8,3),
  expected_value numeric(9,6) not null,
  outcome_probabilities jsonb not null default '{}'::jsonb,
  raw_score numeric(9,4) not null,
  valid_feature_count smallint not null,
  independent_module_count smallint not null,
  conflict_index numeric(8,6) not null check (conflict_index between 0 and 1),
  data_completeness numeric(8,6) not null check (data_completeness between 0 and 1),
  confidence_score numeric(8,6) not null check (confidence_score between 0 and 1),
  feature_combination text,
  grade text not null check (grade in ('MF-A','MF-B','MF-C','MF-D')),
  recommended_units numeric(5,2) not null check (recommended_units between 0 and 2),
  is_primary boolean generated always as (decision_rank = 1) stored,
  is_secondary boolean generated always as (decision_rank = 2) stored,
  correlation_risk text not null default 'low' check (correlation_risk in ('low','medium','high')),
  decision_summary text not null,
  risk_summary text not null,
  alternative_lines jsonb not null default '[]'::jsonb,
  feature_snapshot jsonb not null default '[]'::jsonb,
  input_fingerprint text not null,
  checkpoint text,
  model_name text not null default 'Multi-Feature Decision Engine',
  model_version text not null default 'MFDR v1',
  base_project_version text not null default 'football-platform-2026.09.24',
  calculated_at timestamptz not null default now(),
  result_home_score smallint,
  result_away_score smallint,
  settlement_outcome text check (settlement_outcome in ('WIN','HALF_WIN','PUSH','HALF_LOSS','LOSS','VOID')),
  profit_u numeric(9,4),
  result_source text,
  settled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(match_key, decision_rank)
);

create table public.multi_feature_decision_history (
  id uuid primary key default gen_random_uuid(),
  match_key text not null references public.football_feature_matches(match_key) on delete cascade,
  decision_id uuid references public.multi_feature_decisions(id) on delete set null,
  decision_rank smallint not null check (decision_rank in (1,2)),
  input_fingerprint text not null,
  recalc_reason text not null,
  snapshot jsonb not null,
  calculated_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index multi_feature_runs_started_idx on public.multi_feature_runs(started_at desc);
create index multi_feature_signals_match_status_idx on public.multi_feature_signals(match_key,status);
create index multi_feature_signals_group_idx on public.multi_feature_signals(feature_group,feature_category);
create index multi_feature_decisions_calculated_idx on public.multi_feature_decisions(calculated_at desc);
create index multi_feature_decisions_settlement_idx on public.multi_feature_decisions(settled_at,decision_status,calculated_at);
create index multi_feature_history_match_idx on public.multi_feature_decision_history(match_key,calculated_at desc);

create or replace function public.multi_feature_touch_updated_at()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
begin new.updated_at = now(); return new; end $$;

create trigger multi_feature_signals_touch before update on public.multi_feature_signals
for each row execute function public.multi_feature_touch_updated_at();
create trigger multi_feature_decisions_touch before update on public.multi_feature_decisions
for each row execute function public.multi_feature_touch_updated_at();

create or replace view public.multi_feature_decision_stats with (security_invoker=true) as
select
  grade,
  market_type,
  independent_module_count,
  case
    when conflict_index < .20 then 'low'
    when conflict_index < .35 then 'mild'
    when conflict_index <= .50 then 'medium'
    else 'high'
  end as conflict_bucket,
  feature_combination,
  count(*) filter (where decision_status='RECOMMEND') as recommendations,
  count(*) filter (where settlement_outcome is not null) as settled,
  count(*) filter (where settlement_outcome in ('WIN','HALF_WIN')) as positive,
  count(*) filter (where settlement_outcome in ('WIN','HALF_WIN','HALF_LOSS','LOSS')) as decisive,
  round(avg(expected_value) filter (where decision_status='RECOMMEND'),6) as average_ev,
  round(sum(profit_u) filter (where settlement_outcome is not null),4) as profit_u,
  round(sum(profit_u) filter (where settlement_outcome is not null) /
    nullif(sum(recommended_units) filter (where settlement_outcome is not null),0),6) as roi
from public.multi_feature_decisions
group by grade,market_type,independent_module_count,conflict_bucket,feature_combination;

do $$ declare table_name text; begin
  foreach table_name in array array[
    'multi_feature_runs','multi_feature_signals','multi_feature_decisions','multi_feature_decision_history'
  ] loop
    execute format('alter table public.%I enable row level security',table_name);
    execute format('revoke all on public.%I from public,anon,authenticated',table_name);
    execute format('grant all on public.%I to service_role',table_name);
  end loop;
end $$;

revoke all on public.multi_feature_decision_stats from public,anon,authenticated;
grant select on public.multi_feature_decision_stats to service_role;
revoke execute on function public.multi_feature_touch_updated_at() from public,anon,authenticated;
grant execute on function public.multi_feature_touch_updated_at() to service_role;

comment on table public.multi_feature_decisions is
  'MFDR v1 current decisions. Independent from every pre-existing recommendation and settlement table.';
comment on column public.multi_feature_decisions.input_fingerprint is
  'Hash of raw feature facts, market quotes and checkpoint; used to append history only when the independent inputs change.';

do $$ declare job_id bigint; begin
  select jobid into job_id from cron.job where jobname='mfdr-recalculate-every-15-minutes';
  if job_id is not null then perform cron.unschedule(job_id); end if;
end $$;
select cron.schedule(
  'mfdr-recalculate-every-15-minutes',
  '4,19,34,49 * * * *',
  $$select net.http_post(
    url := 'https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/multi-feature-decision-api/recalculate',
    headers := jsonb_build_object('Content-Type','application/json','x-scan-key',(select scan_key from public.ah0_scanner_config where id=true)),
    body := '{"trigger_source":"cron"}'::jsonb,
    timeout_milliseconds := 90000
  );$$
);

do $$ declare job_id bigint; begin
  select jobid into job_id from cron.job where jobname='mfdr-settle-every-2-hours';
  if job_id is not null then perform cron.unschedule(job_id); end if;
end $$;
select cron.schedule(
  'mfdr-settle-every-2-hours',
  '17 */2 * * *',
  $$select net.http_post(
    url := 'https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/multi-feature-decision-api/settle',
    headers := jsonb_build_object('Content-Type','application/json','x-scan-key',(select scan_key from public.ah0_scanner_config where id=true)),
    body := '{"trigger_source":"settlement"}'::jsonb,
    timeout_milliseconds := 90000
  );$$
);
;
