-- A broad handicap-rise feature, kept separate from the exact rise-to-0.75 signal.
alter table public.football_feature_signals
  drop constraint if exists football_feature_signals_kind_check,
  add constraint football_feature_signals_kind_check
    check (kind in (
      'away_zero', 'reversal', 'rise_075', 'handicap_rise_05',
      'losing_streak', 'over_streak', 'weak_favorite', 'total_line_jump'
    ));

create or replace view public.football_feature_stats
with (security_invoker = true) as
with kinds(kind) as (
  values ('away_zero'), ('reversal'), ('rise_075'), ('handicap_rise_05'),
    ('losing_streak'), ('over_streak'), ('weak_favorite'), ('total_line_jump')
)
select
  k.kind,
  count(s.id) as samples,
  count(distinct s.match_key) as matches,
  count(s.id) filter (where s.outcome is null) as pending,
  count(s.id) filter (where s.outcome = 'VOID') as voids,
  count(s.id) filter (where s.value is not null) as settled,
  count(s.id) filter (where s.value = 1) as wins,
  count(s.id) filter (where s.value = 0.5) as half_wins,
  count(s.id) filter (where s.value = 0) as pushes,
  count(s.id) filter (where s.value = -0.5) as half_losses,
  count(s.id) filter (where s.value = -1) as losses,
  round(100.0 * count(s.id) filter (
    where case
      when k.kind = 'away_zero' then s.value >= 0
      when k.kind = 'losing_streak' then s.value < 0
      else s.value > 0
    end
  ) / nullif(count(s.id) filter (where s.value is not null), 0), 2) as hit_rate,
  round(100.0 * count(s.id) filter (
    where case when k.kind = 'away_zero' then s.value >= 0 else s.value = 1 end
  ) / nullif(count(s.id) filter (
    where case when k.kind = 'away_zero' then s.value is not null else s.value in (-1, 1) end
  ), 0), 2) as decisive_win_rate,
  count(s.id) filter (where s.included_in_stats) as official_samples,
  count(distinct s.match_key) filter (where s.included_in_stats) as official_matches,
  count(s.id) filter (where s.included_in_stats and s.outcome is null) as official_pending,
  count(s.id) filter (where s.included_in_stats and s.value is not null) as official_settled,
  count(s.id) filter (where s.included_in_stats and s.value = 1) as official_wins,
  count(s.id) filter (where s.included_in_stats and s.value = 0.5) as official_half_wins,
  count(s.id) filter (where s.included_in_stats and s.value = 0) as official_pushes,
  count(s.id) filter (where s.included_in_stats and s.value = -0.5) as official_half_losses,
  count(s.id) filter (where s.included_in_stats and s.value = -1) as official_losses,
  round(100.0 * count(s.id) filter (
    where s.included_in_stats and case
      when k.kind = 'away_zero' then s.value >= 0
      when k.kind = 'losing_streak' then s.value < 0
      else s.value > 0
    end
  ) / nullif(count(s.id) filter (where s.included_in_stats and s.value is not null), 0), 2) as official_hit_rate
from kinds k
left join public.football_feature_signals s on s.kind = k.kind
group by k.kind;

create or replace view public.football_feature_stats_by_bookmaker
with (security_invoker = true) as
select
  s.quote_type,
  s.bookmaker,
  s.kind,
  count(*) as samples,
  count(distinct s.match_key) as matches,
  count(*) filter (where s.value is not null) as settled,
  count(*) filter (where s.outcome is null) as pending,
  count(*) filter (where s.value = 1) as wins,
  count(*) filter (where s.value = 0.5) as half_wins,
  count(*) filter (where s.value = 0) as pushes,
  count(*) filter (where s.value = -0.5) as half_losses,
  count(*) filter (where s.value = -1) as losses,
  round(100.0 * count(*) filter (
    where case
      when s.kind = 'away_zero' then s.value >= 0
      when s.kind = 'losing_streak' then s.value < 0
      else s.value > 0
    end
  ) / nullif(count(*) filter (where s.value is not null), 0), 2) as hit_rate,
  count(*) filter (where s.included_in_stats) as official_samples,
  count(distinct s.match_key) filter (where s.included_in_stats) as official_matches,
  count(*) filter (where s.included_in_stats and s.value is not null) as official_settled,
  round(100.0 * count(*) filter (
    where s.included_in_stats and case
      when s.kind = 'away_zero' then s.value >= 0
      when s.kind = 'losing_streak' then s.value < 0
      else s.value > 0
    end
  ) / nullif(count(*) filter (where s.included_in_stats and s.value is not null), 0), 2) as official_hit_rate
from public.football_feature_signals s
group by s.quote_type, s.bookmaker, s.kind;

revoke all on table public.football_feature_stats from anon, authenticated;
revoke all on table public.football_feature_stats_by_bookmaker from anon, authenticated;
grant select on table public.football_feature_stats to service_role;
grant select on table public.football_feature_stats_by_bookmaker to service_role;

-- Backfill the earliest qualifying stored quote for each match and bookmaker.
with quote_counts as (
  select match_key, observed_at, count(distinct bookmaker)::integer as source_count
  from public.football_feature_quotes
  where quote_type = 'bookmaker'
  group by match_key, observed_at
), candidates as (
  select
    q.*,
    m.kickoff_at,
    case when q.home_handicap < 0 then 'home' else 'away' end as signal_side,
    case when q.home_handicap < 0 then q.home_odds else q.away_odds end as selected_price,
    case when q.quote_type = 'market_median' then 3 else greatest(1, coalesce(qc.source_count, 1)) end as source_count,
    row_number() over (
      partition by q.match_key, q.bookmaker
      order by q.observed_at, q.id
    ) as candidate_order
  from public.football_feature_quotes q
  join public.football_feature_matches m using (match_key)
  left join quote_counts qc using (match_key, observed_at)
  where q.home_handicap is not null
    and q.opening_home_handicap is not null
    and q.home_handicap <> 0
    and abs(q.home_handicap) - abs(q.opening_home_handicap) >= 0.5
    and (q.opening_home_handicap = 0 or sign(q.opening_home_handicap) = sign(q.home_handicap))
    and q.opening_at is not null
    and q.opening_at <= q.observed_at
    and q.observed_at < m.kickoff_at
)
insert into public.football_feature_signals (
  match_key, bookmaker, kind, side, trigger_at, handicap, total_line,
  evidence, quote_type, source_platform, source_url, trigger_price,
  market_reference_price, last_observed_at, latest_price,
  latest_handicap, latest_total_line
)
select
  match_key,
  bookmaker,
  'handicap_rise_05',
  signal_side,
  observed_at,
  -abs(home_handicap),
  total_line,
  jsonb_build_object(
    'initial', opening_home_handicap,
    'current', home_handicap,
    'line_rise', abs(home_handicap) - abs(opening_home_handicap),
    'home_odds', home_odds,
    'away_odds', away_odds,
    'source_platform', source_platform,
    'source_url', source_url,
    'quote_type', quote_type,
    'source_count', source_count,
    'verification_status', case when quote_type = 'market_median' or source_count >= 3 then 'cross_verified' else 'single_source' end,
    'backfilled_from_stored_quote', true
  ),
  quote_type,
  source_platform,
  source_url,
  selected_price,
  selected_price,
  observed_at,
  selected_price,
  -abs(home_handicap),
  total_line
from candidates
where candidate_order = 1
on conflict (match_key, bookmaker, kind, side) do nothing;

-- Settle backfilled completed matches against the frozen handicap.
with scored as (
  select
    s.id,
    s.handicap,
    case when s.side = 'home'
      then (m.result->>'home_score')::numeric - (m.result->>'away_score')::numeric
      else (m.result->>'away_score')::numeric - (m.result->>'home_score')::numeric
    end as margin
  from public.football_feature_signals s
  join public.football_feature_matches m using (match_key)
  where s.kind = 'handicap_rise_05'
    and s.outcome is null
    and s.handicap is not null
    and m.result->>'status' = 'finished'
    and m.result->>'period' = 'regular_time'
), recalculated as (
  select
    id,
    case when handicap * 2 = trunc(handicap * 2)
      then sign(margin + handicap)
      else (sign(margin + floor(handicap * 2) / 2) + sign(margin + ceil(handicap * 2) / 2)) / 2
    end as new_value
  from scored
)
update public.football_feature_signals s
set value = r.new_value,
    outcome = case r.new_value
      when 1 then 'WIN'
      when 0.5 then 'HALF_WIN'
      when 0 then 'PUSH'
      when -0.5 then 'HALF_LOSS'
      when -1 then 'LOSS'
    end,
    settled_at = coalesce(s.settled_at, now()),
    evidence = s.evidence || jsonb_build_object('settlement_basis', 'favorite_asian_handicap')
from recalculated r
where s.id = r.id;

comment on constraint football_feature_signals_kind_check
  on public.football_feature_signals is
  'handicap_rise_05 = same-direction favorite handicap depth rises by at least 0.50; rise_075 remains the exact 0.75 destination feature.';

comment on view public.football_feature_stats is
  'Independent feature statistics, including exact rise-to-0.75 and broad same-direction handicap rises of at least 0.50.';
;
