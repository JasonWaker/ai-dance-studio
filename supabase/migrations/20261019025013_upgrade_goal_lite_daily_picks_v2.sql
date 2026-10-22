-- GOAL-Lite v2.0: extend the existing ledger without replacing historical rows.
alter table public.goal_lite_daily_picks
  add column if not exists competition_code text,
  add column if not exists competition_type text,
  add column if not exists competition_stage text,
  add column if not exists source_match_id text,
  add column if not exists source_url text,
  add column if not exists prediction_confidence numeric,
  add column if not exists data_completeness numeric,
  add column if not exists profit_units numeric,
  add column if not exists settlement_source text,
  add column if not exists settlement_verified_at timestamptz,
  add column if not exists analysis_details jsonb not null default '{}'::jsonb,
  add column if not exists sync_run_id uuid;

update public.goal_lite_daily_picks
set competition_code=coalesce(competition_code,league_code),
    competition_type=coalesce(competition_type,'league')
where competition_code is null or competition_type is null;

alter table public.goal_lite_daily_picks
  drop constraint if exists goal_lite_daily_picks_competition_type_check,
  add constraint goal_lite_daily_picks_competition_type_check check(competition_type in ('league','cup','international')),
  drop constraint if exists goal_lite_daily_picks_confidence_check,
  add constraint goal_lite_daily_picks_confidence_check check(prediction_confidence is null or prediction_confidence between 0 and 1),
  drop constraint if exists goal_lite_daily_picks_completeness_check,
  add constraint goal_lite_daily_picks_completeness_check check(data_completeness is null or data_completeness between 0 and 1),
  drop constraint if exists goal_lite_daily_picks_profit_check,
  add constraint goal_lite_daily_picks_profit_check check(profit_units is null or profit_units between -1 and 10),
  drop constraint if exists goal_lite_daily_picks_settlement_check,
  add constraint goal_lite_daily_picks_settlement_check check(settlement_result is null or settlement_result in ('win','half_win','push','half_loss','loss','void'));

create index if not exists goal_lite_daily_picks_report_idx on public.goal_lite_daily_picks(report_date desc,kickoff_at);
create index if not exists goal_lite_daily_picks_competition_idx on public.goal_lite_daily_picks(competition_code,report_date desc);
create index if not exists goal_lite_daily_picks_unsettled_idx on public.goal_lite_daily_picks(kickoff_at) where settled_at is null;

create table if not exists public.goal_lite_sync_runs (
  id uuid primary key default gen_random_uuid(),
  report_date date not null,
  source_type text not null,
  requested_count integer not null default 0,
  accepted_count integer not null default 0,
  rejected_count integer not null default 0,
  status text not null check(status in ('running','success','partial','failed')),
  error_details jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);
alter table public.goal_lite_sync_runs enable row level security;
revoke all on public.goal_lite_sync_runs from anon,authenticated;
grant all on public.goal_lite_sync_runs to service_role;

do $$ begin
  alter table public.goal_lite_daily_picks
    add constraint goal_lite_daily_picks_sync_run_fk
    foreign key(sync_run_id) references public.goal_lite_sync_runs(id) on delete set null;
exception when duplicate_object then null;
end $$;

-- Keep the existing public read-only policy; explicitly deny client writes.
revoke insert,update,delete,truncate,references,trigger on public.goal_lite_daily_picks from anon,authenticated;
grant select on public.goal_lite_daily_picks to anon,authenticated;
;
