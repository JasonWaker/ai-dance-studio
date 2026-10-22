with scored as (
  select s.id,s.handicap,
    case when s.side='home'
      then (m.result->>'home_score')::numeric-(m.result->>'away_score')::numeric
      else (m.result->>'away_score')::numeric-(m.result->>'home_score')::numeric
    end margin
  from public.football_feature_signals s
  join public.football_feature_matches m using(match_key)
  where s.kind='reversal' and s.handicap is not null
    and m.result->>'status'='finished' and m.result->>'period'='regular_time'
), recalculated as (
  select id,
    case when handicap*2=trunc(handicap*2)
      then sign(margin+handicap)
      else (sign(margin+floor(handicap*2)/2)+sign(margin+ceil(handicap*2)/2))/2
    end new_value
  from scored
)
update public.football_feature_signals s
set value=r.new_value,
    outcome=case r.new_value when 1 then 'WIN' when 0.5 then 'HALF_WIN' when 0 then 'PUSH' when -0.5 then 'HALF_LOSS' when -1 then 'LOSS' end,
    evidence=coalesce(s.evidence,'{}'::jsonb)||jsonb_build_object('settlement_basis','new_favorite_asian_handicap')
from recalculated r where s.id=r.id;

comment on constraint football_feature_signals_kind_check on public.football_feature_signals is
'total_line_jump = the cross-verified market median total rises by at least 0.50 goals from the first reliable pre-match observation; reversal is settled against the new favorite frozen handicap.';;
