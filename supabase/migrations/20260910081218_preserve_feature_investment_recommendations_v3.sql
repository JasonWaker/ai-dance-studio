alter table public.under3_low_odds_matches
           add column if not exists investment_recommendation_snapshot jsonb,
           add column if not exists investment_recommendation_locked_at timestamptz;

         alter table public.football_feature_matches
           add column if not exists investment_recommendation_snapshot jsonb,
           add column if not exists investment_recommendation_locked_at timestamptz;

         create or replace view public.under3_low_odds_dashboard as
         select
           id, match_key, scan_batch_id, first_seen_at, last_seen_at, kickoff_at,
           competition_name, competition_country, competition_level,
           home_team, away_team, source_match_id,
           trigger_main_ou_line, trigger_main_over_odds, trigger_main_under_odds,
           trigger_under3_odds, trigger_over3_odds,
           latest_main_ou_line, latest_main_over_odds, latest_main_under_odds,
           latest_under3_odds, latest_over3_odds,
           is_165_focus, odds_source, source_url, signal_rule, status,
           home_score, away_score, total_goals, goals_3plus_hit,
           settled_at, result_source, created_at, updated_at,
           competition_name_zh, home_team_zh, away_team_zh,
           timezone('Asia/Shanghai'::text, kickoff_at) as kickoff_beijing,
           case
             when goals_3plus_hit is true then '>=3球'::text
             when goals_3plus_hit is false then '<=2球'::text
             else '待结算'::text
           end as result_label,
           case
             when is_165_focus then '1.65重点样本'::text
             else '普通样本'::text
           end as focus_label,
           (select count(*) from public.under3_low_odds_snapshots s where s.match_id=m.id) as snapshot_count,
           coalesce(competition_name_zh, competition_name) as display_competition_name,
           coalesce(home_team_zh, home_team) as display_home_team,
           coalesce(away_team_zh, away_team) as display_away_team,
           investment_recommendation_snapshot,
           investment_recommendation_locked_at
         from public.under3_low_odds_matches m;;
