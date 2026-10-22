-- Repair market-median snapshots whose handicap polarity was transiently
-- inverted relative to the aggregate reference observed in the same scan.
with conflicts as (
  select distinct on (m.id)
    m.id,
    sign(a.home_handicap) * abs(m.home_handicap) as corrected_current,
    case
      when m.opening_home_handicap is null then null
      when coalesce(a.opening_home_handicap, a.home_handicap) = 0 then m.opening_home_handicap
      else sign(coalesce(a.opening_home_handicap, a.home_handicap)) * abs(m.opening_home_handicap)
    end as corrected_opening
  from public.football_feature_quotes m
  join public.football_feature_quotes a
    on a.match_key = m.match_key
   and a.observed_at = m.observed_at
   and a.quote_type = 'aggregate_reference'
  where m.quote_type = 'market_median'
    and m.home_handicap is not null
    and a.home_handicap is not null
    and m.home_handicap <> 0
    and a.home_handicap <> 0
    and sign(m.home_handicap) <> sign(a.home_handicap)
    and abs(abs(m.home_handicap) - abs(a.home_handicap)) <= 0.5
  order by m.id, abs(abs(m.home_handicap) - abs(a.home_handicap))
)
update public.football_feature_quotes q
set home_handicap = c.corrected_current,
    opening_home_handicap = c.corrected_opening,
    raw_evidence = jsonb_set(
      jsonb_set(
        jsonb_set(coalesce(q.raw_evidence, '{}'::jsonb), '{home_handicap}', to_jsonb(c.corrected_current), true),
        '{opening_home_handicap}', coalesce(to_jsonb(c.corrected_opening), 'null'::jsonb), true
      ),
      '{polarity_corrected_from_same_scan_aggregate}', 'true'::jsonb, true
    )
from conflicts c
where q.id = c.id;

-- If the repaired market direction already has a signal, retain that signal
-- and remove the conflicting duplicate before changing the unique side key.
delete from public.football_feature_signals bad
using public.football_feature_quotes q
where bad.kind = 'handicap_rise_05'
  and bad.bookmaker = '市场中位数'
  and bad.match_key = q.match_key
  and bad.trigger_at = q.observed_at
  and q.quote_type = 'market_median'
  and q.raw_evidence->>'polarity_corrected_from_same_scan_aggregate' = 'true'
  and exists (
    select 1
    from public.football_feature_signals keep
    where keep.match_key = bad.match_key
      and keep.bookmaker = bad.bookmaker
      and keep.kind = bad.kind
      and keep.side = case when q.home_handicap < 0 then 'home' else 'away' end
      and keep.id <> bad.id
  );

with repaired as (
  select
    s.id,
    q.home_handicap,
    q.opening_home_handicap,
    q.home_odds,
    q.away_odds,
    case when q.home_handicap < 0 then 'home' else 'away' end as corrected_side,
    -abs(q.home_handicap) as corrected_handicap,
    case
      when m.result->>'status' = 'finished'
       and m.result->>'period' = 'regular_time'
      then case when q.home_handicap < 0
        then (m.result->>'home_score')::numeric - (m.result->>'away_score')::numeric
        else (m.result->>'away_score')::numeric - (m.result->>'home_score')::numeric
      end
      else null
    end as margin
  from public.football_feature_signals s
  join public.football_feature_quotes q
    on q.match_key = s.match_key
   and q.observed_at = s.trigger_at
   and q.quote_type = 'market_median'
  join public.football_feature_matches m on m.match_key = s.match_key
  where s.kind = 'handicap_rise_05'
    and s.bookmaker = '市场中位数'
    and q.raw_evidence->>'polarity_corrected_from_same_scan_aggregate' = 'true'
), scored as (
  select
    repaired.*,
    case
      when margin is null then null
      when corrected_handicap * 2 = trunc(corrected_handicap * 2)
        then sign(margin + corrected_handicap)
      else (
        sign(margin + floor(corrected_handicap * 2) / 2)
        + sign(margin + ceil(corrected_handicap * 2) / 2)
      ) / 2
    end as corrected_value
  from repaired
)
update public.football_feature_signals s
set side = r.corrected_side,
    handicap = r.corrected_handicap,
    trigger_price = case when r.corrected_side = 'home' then r.home_odds else r.away_odds end,
    market_reference_price = case when r.corrected_side = 'home' then r.home_odds else r.away_odds end,
    value = coalesce(r.corrected_value, s.value),
    outcome = case coalesce(r.corrected_value, s.value)
      when 1 then 'WIN'
      when 0.5 then 'HALF_WIN'
      when 0 then 'PUSH'
      when -0.5 then 'HALF_LOSS'
      when -1 then 'LOSS'
      else s.outcome
    end,
    evidence = s.evidence || jsonb_build_object(
      'initial', r.opening_home_handicap,
      'current', r.home_handicap,
      'line_rise', abs(r.home_handicap) - abs(r.opening_home_handicap),
      'home_odds', r.home_odds,
      'away_odds', r.away_odds,
      'settlement_basis', 'favorite_asian_handicap',
      'polarity_corrected_from_same_scan_aggregate', true
    )
from scored r
where s.id = r.id;

comment on view public.football_feature_stats is
  'Feature statistics; handicap_rise_05 measures whether the same favorite covers the post-rise handicap after a depth increase of at least 0.50.';
;
