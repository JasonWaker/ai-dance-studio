-- 让重点比赛拥有独立、可追溯的赛果，不再依赖该场比赛恰好进入特征库。
-- 写入仍由 service_role 的赛果追补任务执行；现有 RLS 策略不放宽。

alter table public.monitored_fixture_schedule
  add column if not exists home_score integer,
  add column if not exists away_score integer,
  add column if not exists result_source text,
  add column if not exists result_source_url text,
  add column if not exists settled_at timestamptz,
  add column if not exists last_result_check_at timestamptz;
alter table public.monitored_fixture_schedule
  drop constraint if exists monitored_fixture_home_score_check,
  drop constraint if exists monitored_fixture_away_score_check;
alter table public.monitored_fixture_schedule
  add constraint monitored_fixture_home_score_check
    check (home_score is null or home_score >= 0),
  add constraint monitored_fixture_away_score_check
    check (away_score is null or away_score >= 0);
create index if not exists monitored_fixture_pending_result_idx
  on public.monitored_fixture_schedule (last_result_check_at nulls first, kickoff_at desc)
  where settled_at is null and status in ('scheduled', 'live', 'finished');
comment on column public.monitored_fixture_schedule.home_score is '已核实的90分钟主队进球（含补时，不含加时/点球）。';
comment on column public.monitored_fixture_schedule.away_score is '已核实的90分钟客队进球（含补时，不含加时/点球）。';
comment on column public.monitored_fixture_schedule.result_source is '赛果来源名称。';
comment on column public.monitored_fixture_schedule.result_source_url is '可核验的 HTTPS 赛果来源。';
comment on column public.monitored_fixture_schedule.settled_at is '重点比赛赛果确认并写入的时间。';
comment on column public.monitored_fixture_schedule.last_result_check_at is '最近一次自动赛果追补尝试时间。';
