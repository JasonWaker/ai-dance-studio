create or replace view public.under3_low_odds_stats_by_above_range_odds
with (security_invoker = true)
as
select
  latest_under3_odds,
  count(*)::bigint as samples,
  count(*) filter (where status = 'settled')::bigint as settled,
  count(*) filter (where status = 'settled' and goals_3plus_hit is true)::bigint as goals_3plus,
  round(
    100.0 * count(*) filter (where status = 'settled' and goals_3plus_hit is true)
    / nullif(count(*) filter (where status = 'settled'), 0),
    2
  ) as goals_3plus_rate
from public.under3_low_odds_dashboard
where latest_under3_odds > 1.75
group by latest_under3_odds;

revoke all on public.under3_low_odds_stats_by_above_range_odds from public, anon, authenticated;
grant select on public.under3_low_odds_stats_by_above_range_odds to service_role;;
