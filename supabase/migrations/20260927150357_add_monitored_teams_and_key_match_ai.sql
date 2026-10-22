-- 重点球队可管理名单 + 重点赛事 AI 预测快照。
-- 前端只通过管理员 Edge Function 访问；两张表均不直接向 authenticated/anon 开放写入。

create table if not exists public.monitored_teams (
  id uuid primary key default gen_random_uuid(),
  canonical_name text not null check (char_length(canonical_name) between 1 and 160),
  display_name text not null check (char_length(display_name) between 1 and 160),
  aliases text[] not null default '{}',
  note text not null default '',
  scan_enabled boolean not null default true,
  created_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists monitored_teams_canonical_name_uidx
  on public.monitored_teams (lower(canonical_name));
create index if not exists monitored_teams_scan_enabled_idx
  on public.monitored_teams (scan_enabled, updated_at desc);
alter table public.monitored_teams enable row level security;
drop policy if exists "monitored_teams_service_role_all" on public.monitored_teams;
create policy "monitored_teams_service_role_all"
  on public.monitored_teams for all to service_role using (true) with check (true);
-- 从现有重点赛程恢复当前名单，确保上线后不会突然停止现有球队的监测。
insert into public.monitored_teams (canonical_name, display_name)
select distinct btrim(monitored_team), btrim(monitored_team)
from public.monitored_fixture_schedule
where monitored_team is not null and btrim(monitored_team) <> ''
on conflict do nothing;
alter table public.monitored_fixture_schedule
  add column if not exists monitored_team_ids uuid[] not null default '{}';
create index if not exists monitored_fixture_team_ids_gin_idx
  on public.monitored_fixture_schedule using gin (monitored_team_ids);
create table if not exists public.key_match_ai_predictions (
  id uuid primary key default gen_random_uuid(),
  fixture_key text not null check (char_length(fixture_key) between 1 and 160),
  match_key text,
  model_name text not null,
  model_version text not null,
  engine_revision text not null,
  analysis_phase text not null check (analysis_phase in ('pre_match','after_kickoff_no_live','post_match_replay')),
  input_fingerprint text not null,
  source_cutoff_at timestamptz,
  input_snapshot jsonb not null default '{}'::jsonb,
  prediction jsonb not null default '{}'::jsonb,
  created_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists key_match_ai_predictions_fixture_idx
  on public.key_match_ai_predictions (fixture_key, created_at desc);
create index if not exists key_match_ai_predictions_match_idx
  on public.key_match_ai_predictions (match_key, created_at desc)
  where match_key is not null;
alter table public.key_match_ai_predictions enable row level security;
drop policy if exists "key_match_ai_predictions_service_role_all" on public.key_match_ai_predictions;
create policy "key_match_ai_predictions_service_role_all"
  on public.key_match_ai_predictions for all to service_role using (true) with check (true);
comment on table public.monitored_teams is '重点监测球队的唯一可管理配置源；扫描任务只匹配 scan_enabled=true 的球队及别名。';
comment on column public.monitored_teams.aliases is '数据源可能出现的球队别名，扫描匹配时与 canonical_name 一起使用。';
comment on table public.key_match_ai_predictions is '用户按赛事主动触发的 KM-AI 预测快照；永久保留模型版本、输入与分析阶段。';
