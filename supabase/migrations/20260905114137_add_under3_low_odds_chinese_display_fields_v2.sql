drop view if exists public.under3_low_odds_dashboard;

alter table public.under3_low_odds_matches
  add column if not exists competition_name_zh text,
  add column if not exists home_team_zh text,
  add column if not exists away_team_zh text;

create view public.under3_low_odds_dashboard
with (security_invoker = true) as
select
  m.*,
  timezone('Asia/Shanghai', m.kickoff_at) as kickoff_beijing,
  case when m.goals_3plus_hit is true then '>=3球' when m.goals_3plus_hit is false then '<=2球' else '待结算' end as result_label,
  case when m.is_165_focus then '1.65重点样本' else '普通样本' end as focus_label,
  (select count(*)::bigint from public.under3_low_odds_snapshots s where s.match_id = m.id) as snapshot_count,
  coalesce(m.competition_name_zh, m.competition_name) as display_competition_name,
  coalesce(m.home_team_zh, m.home_team) as display_home_team,
  coalesce(m.away_team_zh, m.away_team) as display_away_team
from public.under3_low_odds_matches m;

grant select on public.under3_low_odds_dashboard to anon, authenticated;;
