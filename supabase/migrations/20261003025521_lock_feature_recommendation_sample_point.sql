-- Keep result attribution in the same immutable strategy bucket that produced
-- the pre-match recommendation. The original trigger price/point remains on
-- the signal for audit and market-movement analysis.
alter table public.football_feature_signals
  add column if not exists recommendation_point text,
  add column if not exists recommendation_price numeric,
  add column if not exists recommendation_locked_at timestamptz;

comment on column public.football_feature_signals.recommendation_point is
  'Immutable strategy point used by the locked pre-match recommendation; settled statistics use this before the raw trigger point.';
comment on column public.football_feature_signals.recommendation_price is
  'Exact water/odds used by the locked pre-match recommendation, retained separately from the first-qualified trigger price.';
comment on column public.football_feature_signals.recommendation_locked_at is
  'Time the pre-match recommendation point was frozen; must be before kickoff.';

update public.football_feature_signals as signal
set recommendation_point = match.investment_recommendation_snapshot->>'point',
    recommendation_price = case
      when signal.kind in (
        'underdog_025','underdog_075','underdog_10','underdog_125','underdog_15',
        'total_325','total_35','total_375','total_425','zero_low_odds'
      ) and coalesce(match.investment_recommendation_snapshot->>'strategy_sample_price','') ~ '^[0-9]+([.][0-9]+)?$'
        then (match.investment_recommendation_snapshot->>'strategy_sample_price')::numeric
      when signal.kind in (
        'underdog_025','underdog_075','underdog_10','underdog_125','underdog_15',
        'total_325','total_35','total_375','total_425','zero_low_odds'
      ) and coalesce(match.investment_recommendation_snapshot->>'point','') ~ '水位 [0-9]+([.][0-9]+)?$'
        then substring(match.investment_recommendation_snapshot->>'point' from '水位 ([0-9]+([.][0-9]+)?)$')::numeric
      else null
    end,
    recommendation_locked_at = match.investment_recommendation_locked_at
from public.football_feature_matches as match
where match.match_key = signal.match_key
  and match.investment_recommendation_snapshot->>'status' = 'recommended'
  and match.investment_recommendation_snapshot->>'snapshot_origin' = 'pre_match'
  and match.investment_recommendation_snapshot->>'kind' = signal.kind
  and match.investment_recommendation_locked_at is not null
  and match.investment_recommendation_locked_at < match.kickoff_at
  and signal.recommendation_point is null;

create index if not exists football_feature_signals_recommendation_point_idx
  on public.football_feature_signals (kind, recommendation_point)
  where recommendation_point is not null;;
