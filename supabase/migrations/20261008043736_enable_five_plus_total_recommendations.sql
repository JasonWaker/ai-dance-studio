-- ≥5 球此前仅作为观察特征。自本迁移起，它进入统一的赛前推荐链路：
-- 每个精确进球数盘口独立统计，至少 5 场有效结算，整数命中率按 70/30 生成方向。
-- 历史信号只作为统计样本，不补造历史推荐快照。
update public.football_feature_signals
set evidence = (coalesce(evidence, '{}'::jsonb) - 'observation_only') || '{"recommendation_eligible": true}'::jsonb
where kind = 'five_plus_total'
  and (
    coalesce(evidence->>'observation_only', '') <> ''
    or evidence->>'recommendation_eligible' is distinct from 'true'
  );;
