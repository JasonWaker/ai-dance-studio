-- oddstorm:13612364 的赛前推荐由 football-feature-scan 漏查 trigger_under3_odds 后，
-- 错误回退到 latest_under3_odds=1.67 的 25 场/72% 样本池。比赛尚未开赛，撤销
-- 这条错误快照；部署后的统一触发水位口径会将其重新计算为 48 场/58.3% 待定。
update public.under3_low_odds_matches
set investment_recommendation_snapshot = null,
    investment_recommendation_locked_at = null,
    updated_at = now()
where match_key = 'oddstorm:13612364'
  and status = 'scheduled'
  and settled_at is null
  and kickoff_at > now()
  and investment_recommendation_snapshot->>'status' = 'recommended'
  and investment_recommendation_snapshot->>'point' = '1.67'
  and investment_recommendation_snapshot->>'settled' = '25'
  and investment_recommendation_snapshot->>'hit_rate' = '72';
