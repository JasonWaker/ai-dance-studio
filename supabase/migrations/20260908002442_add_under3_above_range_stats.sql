create or replace view public.under3_low_odds_stats_above_range
with (security_invoker = true)
as
select
  count(*)::bigint as samples,
  count(*) filter (where status = 'settled')::bigint as settled,
  count(*) filter (where status = 'settled' and goals_3plus_hit is true)::bigint as goals_3plus,
  count(*) filter (where status = 'settled' and goals_3plus_hit is false)::bigint as goals_le2,
  round(
    100.0 * count(*) filter (where status = 'settled' and goals_3plus_hit is true)
    / nullif(count(*) filter (where status = 'settled'), 0),
    2
  ) as goals_3plus_rate,
  min(latest_under3_odds) as min_latest_under3_odds,
  max(latest_under3_odds) as max_latest_under3_odds
from public.under3_low_odds_dashboard
where latest_under3_odds > 1.75;

revoke all on public.under3_low_odds_stats_above_range from public, anon, authenticated;
grant select on public.under3_low_odds_stats_above_range to service_role;;
