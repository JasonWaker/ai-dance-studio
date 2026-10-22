create or replace view public.under3_low_odds_stats_by_latest_odds as
select
  round(latest_under3_odds, 2) as latest_under3_odds,
  count(*) as samples,
  count(*) filter (where status = 'settled') as settled,
  count(*) filter (where status = 'settled' and goals_3plus_hit is true) as goals_3plus,
  round(100.0 * count(*) filter (where status = 'settled' and goals_3plus_hit is true)::numeric /
        nullif(count(*) filter (where status = 'settled'), 0)::numeric, 2) as goals_3plus_rate,
  round(avg(total_goals) filter (where status = 'settled'), 2) as avg_total_goals
from public.under3_low_odds_matches
where trigger_under3_odds between 1.65 and 1.70
  and latest_under3_odds is not null
group by round(latest_under3_odds, 2)
order by round(latest_under3_odds, 2);

create or replace view public.under3_low_odds_stats_by_trigger_latest as
select
  trigger_under3_odds,
  round(latest_under3_odds, 2) as latest_under3_odds,
  count(*) as samples,
  count(*) filter (where status = 'settled') as settled,
  count(*) filter (where status = 'settled' and goals_3plus_hit is true) as goals_3plus,
  round(100.0 * count(*) filter (where status = 'settled' and goals_3plus_hit is true)::numeric /
        nullif(count(*) filter (where status = 'settled'), 0)::numeric, 2) as goals_3plus_rate,
  round(avg(total_goals) filter (where status = 'settled'), 2) as avg_total_goals
from public.under3_low_odds_matches
where trigger_under3_odds between 1.65 and 1.70
  and latest_under3_odds is not null
group by trigger_under3_odds, round(latest_under3_odds, 2)
order by trigger_under3_odds, round(latest_under3_odds, 2);;
