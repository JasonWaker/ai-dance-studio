create table if not exists public.football_canonical_name_aliases (
  id bigint generated always as identity primary key,
  entity_type text not null check (entity_type in ('team', 'competition')),
  source_name text not null,
  source_name_normalized text not null,
  canonical_name_cn text not null,
  canonical_name_en text,
  authority text not null,
  source_url text,
  priority smallint not null default 100,
  active boolean not null default true,
  verified_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (entity_type, source_name_normalized)
);

create table if not exists public.football_name_unresolved (
  match_key text primary key references public.football_feature_matches(match_key) on delete cascade,
  kickoff_at timestamptz,
  competition_name text,
  home_team text,
  away_team text,
  missing_fields text[] not null default '{}',
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  occurrences integer not null default 1,
  status text not null default 'open' check (status in ('open', 'resolved', 'ignored')),
  last_error text
);

alter table public.football_name_sync_runs
  add column if not exists alias_applied integer not null default 0,
  add column if not exists unresolved integer not null default 0,
  add column if not exists source_error text;

alter table public.football_name_sync_runs drop constraint if exists football_name_sync_runs_status_check;
alter table public.football_name_sync_runs add constraint football_name_sync_runs_status_check
  check (status in ('running', 'completed', 'partial', 'failed'));

create index if not exists football_canonical_alias_lookup_idx
  on public.football_canonical_name_aliases(entity_type, source_name_normalized) where active;
create index if not exists football_name_unresolved_status_idx
  on public.football_name_unresolved(status, last_seen_at desc);

alter table public.football_canonical_name_aliases enable row level security;
alter table public.football_name_unresolved enable row level security;
revoke all on public.football_canonical_name_aliases, public.football_name_unresolved from anon, authenticated;
grant all on public.football_canonical_name_aliases, public.football_name_unresolved to service_role;
grant usage, select on sequence public.football_canonical_name_aliases_id_seq to service_role;

insert into public.football_canonical_name_aliases
  (entity_type, source_name, source_name_normalized, canonical_name_cn, canonical_name_en, authority, source_url, priority)
values
  ('competition', 'Emperors Cup', 'emperors cup', '日本天皇杯', 'Emperor''s Cup', 'jfa_jleague', 'https://www.jfa.jp/match/emperorscup_2026/', 10),
  ('competition', 'Japan Emperor''s Cup', 'japan emperor s cup', '日本天皇杯', 'Emperor''s Cup', 'jfa_jleague', 'https://www.jfa.jp/match/emperorscup_2026/', 10),
  ('team', 'Fagiano Okayama', 'fagiano okayama', '冈山绿雉', 'Fagiano Okayama', 'jfa_jleague', 'https://www.jleague.jp/club/okayama/', 10),
  ('team', 'Okayama', 'okayama', '冈山绿雉', 'Fagiano Okayama', 'jfa_jleague', 'https://www.jleague.jp/club/okayama/', 10),
  ('team', 'JEF United Chiba', 'jef united chiba', '千叶市原', 'JEF United Chiba', 'jfa_jleague', 'https://www.jleague.jp/club/chiba/', 10),
  ('team', 'Chiba', 'chiba', '千叶市原', 'JEF United Chiba', 'jfa_jleague', 'https://www.jleague.jp/club/chiba/', 10),
  ('team', 'Avispa Fukuoka', 'avispa fukuoka', '福冈黄蜂', 'Avispa Fukuoka', 'jfa_jleague', 'https://www.jleague.jp/club/fukuoka/', 10),
  ('team', 'Yokohama FC', 'yokohama fc', '横滨FC', 'Yokohama FC', 'jfa_jleague', 'https://www.jleague.jp/club/yokohamafc/', 10),
  ('team', 'Sanfrecce Hiroshima', 'sanfrecce hiroshima', '广岛三箭', 'Sanfrecce Hiroshima', 'jfa_jleague', 'https://www.jleague.jp/club/hiroshima/', 10),
  ('team', 'Hiroshima Sanfrecce', 'hiroshima sanfrecce', '广岛三箭', 'Sanfrecce Hiroshima', 'jfa_jleague', 'https://www.jleague.jp/club/hiroshima/', 10),
  ('team', 'Iwaki', 'iwaki', '磐城FC', 'Iwaki FC', 'jfa_jleague', 'https://www.jleague.jp/club/iwaki/', 10),
  ('team', 'Iwaki FC', 'iwaki fc', '磐城FC', 'Iwaki FC', 'jfa_jleague', 'https://www.jleague.jp/club/iwaki/', 10),
  ('team', 'Shimizu S-Pulse', 'shimizu s pulse', '清水心跳', 'Shimizu S-Pulse', 'jfa_jleague', 'https://www.jleague.jp/club/shimizu/', 10),
  ('team', 'V-Varen Nagasaki', 'v varen nagasaki', '长崎成功丸', 'V-Varen Nagasaki', 'jfa_jleague', 'https://www.jleague.jp/club/nagasaki/', 10)
on conflict (entity_type, source_name_normalized) do update set
  canonical_name_cn = excluded.canonical_name_cn,
  canonical_name_en = excluded.canonical_name_en,
  authority = excluded.authority,
  source_url = excluded.source_url,
  priority = excluded.priority,
  active = true,
  verified_at = now(),
  updated_at = now();

update public.football_feature_matches match set
  competition_name_cn = coalesce(competition.canonical_name_cn, match.competition_name_cn),
  home_team_cn = coalesce(home_team.canonical_name_cn, match.home_team_cn),
  away_team_cn = coalesce(away_team.canonical_name_cn, match.away_team_cn),
  canonical_name_source = case when competition.id is not null or home_team.id is not null or away_team.id is not null then 'registry:jfa_jleague' else match.canonical_name_source end,
  canonical_name_checked_at = case when competition.id is not null or home_team.id is not null or away_team.id is not null then now() else match.canonical_name_checked_at end
from public.football_canonical_name_aliases competition,
     public.football_canonical_name_aliases home_team,
     public.football_canonical_name_aliases away_team
where competition.entity_type = 'competition'
  and competition.source_name_normalized = lower(regexp_replace(match.competition_name, '[^a-zA-Z0-9]+', ' ', 'g'))
  and home_team.entity_type = 'team'
  and home_team.source_name_normalized = lower(regexp_replace(match.home_team, '[^a-zA-Z0-9]+', ' ', 'g'))
  and away_team.entity_type = 'team'
  and away_team.source_name_normalized = lower(regexp_replace(match.away_team, '[^a-zA-Z0-9]+', ' ', 'g'));
;
