alter table public.h2h_high_over_matches
  drop constraint if exists h2h_high_over_matches_scan_rule_check;

alter table public.h2h_high_over_matches
  add constraint h2h_high_over_matches_scan_rule_check
  check (
    (scan_rule = 'h2h6_gt80' and h2h_sample_size = 6 and h2h_over_count between 5 and 6 and h2h_over_rate > 80)
    or
    (scan_rule = 'h2h10_gt70' and h2h_sample_size = 10 and h2h_over_count between 8 and 10 and h2h_over_rate > 70)
    or
    (scan_rule = 'h2h_dynamic_ge80' and h2h_sample_size between 1 and 10 and h2h_over_count between 0 and h2h_sample_size and h2h_over_rate >= 80)
  );

create or replace view public.h2h_high_over_dashboard
with (security_invoker = true)
as
select
  id,
  match_key,
  scan_batch_id,
  scanned_at,
  kickoff_at,
  kickoff_at at time zone 'Asia/Shanghai' as kickoff_beijing,
  competition_name,
  competition_country,
  competition_level,
  home_team,
  away_team,
  ou_line,
  over_odds,
  under_odds,
  h2h_sample_size,
  h2h_over_count,
  h2h_over_rate,
  h2h_results,
  over_rate_basis,
  odds_source,
  h2h_source,
  source_match_id,
  status,
  home_score,
  away_score,
  total_goals,
  settlement_line,
  settlement_result,
  over_hit,
  settled_at,
  result_source,
  updated_at,
  created_at,
  odds_updated_at,
  scan_rule
from public.h2h_high_over_matches
where scan_rule in ('h2h10_gt70','h2h_dynamic_ge80')
order by kickoff_at desc;

create or replace view public.h2h_high_over_stats
with (security_invoker = true)
as
select
  count(*) filter (where status='settled') as settled_matches,
  count(*) filter (where status='settled' and settlement_result='OVER') as full_over,
  count(*) filter (where status='settled' and settlement_result='HALF_OVER') as half_over,
  count(*) filter (where status='settled' and settlement_result='PUSH') as push,
  count(*) filter (where status='settled' and settlement_result='HALF_UNDER') as half_under,
  count(*) filter (where status='settled' and settlement_result='UNDER') as full_under,
  round(
    100.0 * (
      count(*) filter (where status='settled' and settlement_result='OVER')
      + 0.5 * count(*) filter (where status='settled' and settlement_result='HALF_OVER')
    )::numeric
    / nullif(count(*) filter (where status='settled' and settlement_result in ('OVER','HALF_OVER','HALF_UNDER','UNDER')),0)::numeric,
    2
  ) as weighted_over_hit_rate,
  round(
    100.0 * count(*) filter (where status='settled' and settlement_result in ('OVER','HALF_OVER'))::numeric
    / nullif(count(*) filter (where status='settled' and settlement_result in ('OVER','HALF_OVER','HALF_UNDER','UNDER')),0)::numeric,
    2
  ) as simple_over_hit_rate,
  count(*) as total_matches,
  count(*) filter (where status='scheduled') as scheduled_matches,
  count(*) filter (where scanned_at at time zone 'Asia/Shanghai' >= date_trunc('day', now() at time zone 'Asia/Shanghai')) as today_scanned,
  count(*) filter (where round(h2h_over_rate,2)=83.33) as h2h_83_count,
  count(*) filter (where h2h_over_rate=100) as h2h_100_count,
  round(
    100.0 * (
      count(*) filter (where status='settled' and h2h_over_rate=100 and settlement_result='OVER')
      + 0.5 * count(*) filter (where status='settled' and h2h_over_rate=100 and settlement_result='HALF_OVER')
    )::numeric
    / nullif(count(*) filter (where status='settled' and h2h_over_rate=100 and settlement_result in ('OVER','HALF_OVER','HALF_UNDER','UNDER')),0)::numeric,
    2
  ) as h2h_100_weighted_over_hit_rate,
  count(*) filter (where h2h_over_rate>=80 and h2h_over_rate<90) as h2h_80_count,
  count(*) filter (where h2h_over_rate>=90 and h2h_over_rate<100) as h2h_90_count,
  'h2h_dynamic_ge80'::text as current_rule,
  count(*) filter (where scan_rule='h2h10_gt70') as legacy_h2h10_count,
  count(*) filter (where scan_rule='h2h_dynamic_ge80') as dynamic_rule_count,
  count(*) filter (where h2h_sample_size<10) as short_history_count
from public.h2h_high_over_matches
where scan_rule in ('h2h10_gt70','h2h_dynamic_ge80');

create or replace view public.h2h_high_over_stats_by_sample_size
with (security_invoker = true)
as
select
  h2h_sample_size,
  count(*) as total_matches,
  count(*) filter (where status='settled') as settled_matches,
  count(*) filter (where status='settled' and settlement_result='OVER') as full_over,
  count(*) filter (where status='settled' and settlement_result='HALF_OVER') as half_over,
  count(*) filter (where status='settled' and settlement_result='PUSH') as push,
  count(*) filter (where status='settled' and settlement_result='HALF_UNDER') as half_under,
  count(*) filter (where status='settled' and settlement_result='UNDER') as full_under,
  round(
    100.0 * (
      count(*) filter (where status='settled' and settlement_result='OVER')
      + 0.5 * count(*) filter (where status='settled' and settlement_result='HALF_OVER')
    )::numeric
    / nullif(count(*) filter (where status='settled' and settlement_result in ('OVER','HALF_OVER','HALF_UNDER','UNDER')),0)::numeric,
    2
  ) as weighted_over_hit_rate,
  round(
    100.0 * count(*) filter (where status='settled' and settlement_result in ('OVER','HALF_OVER'))::numeric
    / nullif(count(*) filter (where status='settled' and settlement_result in ('OVER','HALF_OVER','HALF_UNDER','UNDER')),0)::numeric,
    2
  ) as simple_over_hit_rate
from public.h2h_high_over_matches
where scan_rule in ('h2h10_gt70','h2h_dynamic_ge80')
group by h2h_sample_size
order by h2h_sample_size desc;;
