create or replace view public.under3_low_odds_stats as
select
  count(*) as total_samples,
  count(*) filter (where status = 'scheduled') as scheduled_samples,
  count(*) filter (where status = 'settled') as settled_samples,
  count(*) filter (where status = 'settled' and goals_3plus_hit is true) as goals_3plus_count,
  count(*) filter (where status = 'settled' and goals_3plus_hit is false) as goals_le2_count,
  round(100.0 * count(*) filter (where status = 'settled' and goals_3plus_hit is true)::numeric /
        nullif(count(*) filter (where status = 'settled'), 0)::numeric, 2) as goals_3plus_rate,
  count(*) filter (where trigger_under3_odds = 1.65) as focus_165_samples,
  count(*) filter (where trigger_under3_odds = 1.65 and status = 'settled') as focus_165_settled,
  count(*) filter (where trigger_under3_odds = 1.65 and status = 'settled' and goals_3plus_hit is true) as focus_165_goals_3plus,
  round(100.0 * count(*) filter (where trigger_under3_odds = 1.65 and status = 'settled' and goals_3plus_hit is true)::numeric /
        nullif(count(*) filter (where trigger_under3_odds = 1.65 and status = 'settled'), 0)::numeric, 2) as focus_165_goals_3plus_rate
from public.under3_low_odds_matches
where trigger_under3_odds between 1.65 and 1.70;

create or replace view public.under3_low_odds_stats_by_odds as
select
  trigger_under3_odds,
  count(*) as samples,
  count(*) filter (where status = 'settled') as settled,
  count(*) filter (where status = 'settled' and goals_3plus_hit is true) as goals_3plus,
  round(100.0 * count(*) filter (where status = 'settled' and goals_3plus_hit is true)::numeric /
        nullif(count(*) filter (where status = 'settled'), 0)::numeric, 2) as goals_3plus_rate
from public.under3_low_odds_matches
where trigger_under3_odds between 1.65 and 1.70
group by trigger_under3_odds
order by trigger_under3_odds;

create or replace view public.under3_low_odds_stats_by_main_line as
select
  trigger_main_ou_line,
  count(*) as samples,
  count(*) filter (where status = 'settled') as settled,
  count(*) filter (where status = 'settled' and goals_3plus_hit is true) as goals_3plus,
  round(100.0 * count(*) filter (where status = 'settled' and goals_3plus_hit is true)::numeric /
        nullif(count(*) filter (where status = 'settled'), 0)::numeric, 2) as goals_3plus_rate
from public.under3_low_odds_matches
where trigger_under3_odds between 1.65 and 1.70
group by trigger_main_ou_line
order by trigger_main_ou_line;;
