update public.football_feature_signals s
set
  outcome = case when ((m.result->>'home_score')::integer + (m.result->>'away_score')::integer) >= 3 then 'WIN' else 'LOSS' end,
  value = case when ((m.result->>'home_score')::integer + (m.result->>'away_score')::integer) >= 3 then 1 else -1 end,
  settled_at = coalesce((m.result->>'finished_at')::timestamptz, now()),
  evidence = coalesce(s.evidence, '{}'::jsonb) || jsonb_build_object(
    'settlement_basis', 'goals_3_plus_reference',
    'settlement_note', 'No trusted current-match total line; reference result only and excluded from official statistics.'
  )
from public.football_feature_matches m
where s.match_key = m.match_key
  and s.kind = 'over_streak'
  and s.quote_type = 'aggregate_reference'
  and s.included_in_stats = false
  and s.outcome is null
  and s.total_line is null
  and m.result->>'status' = 'finished'
  and jsonb_typeof(m.result->'home_score') = 'number'
  and jsonb_typeof(m.result->'away_score') = 'number';

comment on column public.football_feature_signals.outcome is
  'Asian-line outcome when a trusted trigger line exists. For excluded aggregate-reference over_streak rows without a line, WIN/LOSS records whether total goals were at least three; evidence.settlement_basis identifies this reference-only fallback.';;
