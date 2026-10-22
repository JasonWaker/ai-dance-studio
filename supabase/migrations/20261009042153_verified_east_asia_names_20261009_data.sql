-- Exact, source-checked aliases for the fixtures reported on 2026-10-09.
-- No phonetic or token-by-token name generation is used here.
insert into public.football_canonical_name_aliases
  (entity_type, source_name, source_name_normalized, canonical_name_cn, canonical_name_en, authority, source_url, priority)
values
  ('competition', 'K League 1', 'k league 1', '韩国K1联赛', 'K League 1', 'verified:chinese_fixture', 'https://www.soupng.com/stats/157876.html', 20),
  ('competition', 'K League 2', 'k league 2', '韩国K2联赛', 'K League 2', 'verified:chinese_fixture', 'https://m.17500.cn/zq/data-team/course-32452-0-0', 20),
  ('competition', 'Japan J1 League', 'japan j1 league', '日本J1联赛', 'Japan J1 League', 'verified:chinese_fixture', 'https://www.365scores.com/zh/football/match/j1-league-147/gamba-osaka-kashima-antlers-2146-2150-147', 20),
  ('team', 'Gangwon FC', 'gangwon fc', '江原FC', 'Gangwon FC', 'verified:chinese_fixture', 'https://www.soupng.com/stats/157876.html', 20),
  ('team', 'Bucheon FC 1995', 'bucheon fc 1995', '富川1995', 'Bucheon FC 1995', 'verified:chinese_fixture', 'https://www.soupng.com/stats/157876.html', 20),
  ('team', 'Gimpo FC', 'gimpo fc', '金浦市民', 'Gimpo FC', 'verified:chinese_fixture', 'https://m.17500.cn/zq/data-team/course-32452-0-0', 20),
  ('team', 'Seoul E-Land FC', 'seoul e land fc', '首尔衣恋', 'Seoul E-Land FC', 'verified:chinese_fixture', 'https://m.17500.cn/zq/data-team/course-32452-0-0', 20),
  ('team', 'Kashima Antlers', 'kashima antlers', '鹿岛鹿角', 'Kashima Antlers', 'verified:chinese_fixture', 'https://www.365scores.com/zh/football/match/j1-league-147/gamba-osaka-kashima-antlers-2146-2150-147', 20),
  ('team', 'Gamba Osaka', 'gamba osaka', '大阪钢巴', 'Gamba Osaka', 'verified:chinese_fixture', 'https://www.365scores.com/zh/football/match/j1-league-147/gamba-osaka-kashima-antlers-2146-2150-147', 20)
on conflict (entity_type, source_name_normalized) do update set
  canonical_name_cn = excluded.canonical_name_cn,
  canonical_name_en = excluded.canonical_name_en,
  authority = excluded.authority,
  source_url = excluded.source_url,
  priority = excluded.priority,
  active = true,
  verified_at = now(),
  updated_at = now();

update public.football_feature_matches as match set
  competition_name_cn = coalesce(match.competition_name_cn, competition.canonical_name_cn),
  home_team_cn = coalesce(match.home_team_cn, home_team.canonical_name_cn),
  away_team_cn = coalesce(match.away_team_cn, away_team.canonical_name_cn),
  canonical_name_source = coalesce(match.canonical_name_source, 'registry:verified'),
  canonical_name_checked_at = now()
from public.football_canonical_name_aliases as competition,
     public.football_canonical_name_aliases as home_team,
     public.football_canonical_name_aliases as away_team
where competition.entity_type = 'competition'
  and competition.active
  and competition.source_name_normalized = lower(regexp_replace(match.competition_name, '[^a-zA-Z0-9]+', ' ', 'g'))
  and home_team.entity_type = 'team'
  and home_team.active
  and home_team.source_name_normalized = lower(regexp_replace(match.home_team, '[^a-zA-Z0-9]+', ' ', 'g'))
  and away_team.entity_type = 'team'
  and away_team.active
  and away_team.source_name_normalized = lower(regexp_replace(match.away_team, '[^a-zA-Z0-9]+', ' ', 'g'))
  and match.match_key in ('nowgoal:2929736', 'nowgoal:2925544', 'nowgoal:3000477');
;
