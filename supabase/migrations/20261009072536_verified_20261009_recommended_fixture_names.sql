-- Source-checked Chinese names for the three upcoming recommended fixtures
-- left untranslated on 2026-10-09. Match updates are restricted to exact IDs.
insert into public.football_canonical_name_aliases
  (entity_type, source_name, source_name_normalized, canonical_name_cn, canonical_name_en, authority, source_url, priority)
values
  ('competition', 'J3 League', 'j3 league', '日本J3联赛', 'J3 League', 'verified:chinese_fixture', 'https://www.nowscore.com/news/1237520.htm', 20),
  ('team', 'SC Sagamihara', 'sc sagamihara', 'SC相模原', 'SC Sagamihara', 'verified:chinese_fixture', 'https://www.nowscore.com/news/1237520.htm', 20),
  ('team', 'Kamatamare Sanuki', 'kamatamare sanuki', '赞岐釜玉海', 'Kamatamare Sanuki', 'verified:chinese_fixture', 'https://www.nowscore.com/news/1237520.htm', 20),
  ('competition', 'Israel - Liga Alef', 'israel liga alef', '以色列阿列夫联赛', 'Israel - Liga Alef', 'verified:chinese_fixture', 'https://tips.gg/cn/archive/kfar-saba-1928-football-vs-shimshon-tel-aviv-football/', 20),
  ('team', 'Shimshon Tel Aviv', 'shimshon tel aviv', '辛姆松特拉维夫', 'Shimshon Tel Aviv', 'verified:chinese_fixture', 'https://tips.gg/cn/archive/kfar-saba-1928-football-vs-shimshon-tel-aviv-football/', 20),
  ('team', 'Kfar Saba 1928', 'kfar saba 1928', '卡法萨巴1928队', 'Kfar Saba 1928', 'verified:chinese_fixture', 'https://tips.gg/cn/archive/kfar-saba-1928-football-vs-shimshon-tel-aviv-football/', 20),
  ('competition', 'Austria · 2 Liga', 'austria 2 liga', '奥地利乙级联赛', 'Austria · 2 Liga', 'verified:chinese_fixture', 'https://www.okooo.cn/soccer/match/1335071/history/', 20),
  ('team', 'Kapfenberger SV', 'kapfenberger sv', '卡芬堡', 'Kapfenberger SV', 'verified:chinese_fixture', 'https://www.okooo.cn/soccer/match/1335071/history/', 20),
  ('team', 'FK Austria Vienna II', 'fk austria vienna ii', '奥地利维也纳青年队', 'FK Austria Vienna II', 'verified:chinese_fixture', 'https://www.okooo.cn/soccer/match/1335071/history/', 20)
on conflict (entity_type, source_name_normalized) do update set
  canonical_name_cn = excluded.canonical_name_cn,
  canonical_name_en = excluded.canonical_name_en,
  authority = excluded.authority,
  source_url = excluded.source_url,
  priority = excluded.priority,
  active = true,
  verified_at = now(),
  updated_at = now();

update public.football_feature_matches set
  competition_name_cn = '日本J3联赛', home_team_cn = 'SC相模原', away_team_cn = '赞岐釜玉海',
  canonical_name_source = 'registry:verified', canonical_name_checked_at = now()
where match_key = 'nowgoal:3001218'
  and competition_name = 'J3 League' and home_team = 'SC Sagamihara' and away_team = 'Kamatamare Sanuki';

update public.football_feature_matches set
  competition_name_cn = '以色列阿列夫联赛', home_team_cn = '辛姆松特拉维夫', away_team_cn = '卡法萨巴1928队',
  canonical_name_source = 'registry:verified', canonical_name_checked_at = now()
where match_key = 'nowgoal:3074961'
  and competition_name = 'Israel - Liga Alef' and home_team = 'Shimshon Tel Aviv' and away_team = 'Kfar Saba 1928';

update public.football_feature_matches set
  competition_name_cn = '奥地利乙级联赛', home_team_cn = '卡芬堡', away_team_cn = '奥地利维也纳青年队',
  canonical_name_source = 'registry:verified', canonical_name_checked_at = now()
where match_key = 'oddstorm:13607568'
  and competition_name = 'Austria · 2 Liga' and home_team = 'Kapfenberger SV' and away_team = 'FK Austria Vienna II';
;
