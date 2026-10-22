create or replace view public.under3_low_odds_stats as
select
  count(*) as total_samples,
  count(*) filter (where status='scheduled') as scheduled_samples,
  count(*) filter (where status='settled') as settled_samples,
  count(*) filter (where status='settled' and goals_3plus_hit is true) as goals_3plus_count,
  count(*) filter (where status='settled' and goals_3plus_hit is false) as goals_le2_count,
  round(100.0 * count(*) filter (where status='settled' and goals_3plus_hit is true) / nullif(count(*) filter (where status='settled'),0),2) as goals_3plus_rate,
  count(*) filter (where round(latest_under3_odds,2)=1.65) as focus_165_samples,
  count(*) filter (where round(latest_under3_odds,2)=1.65 and status='settled') as focus_165_settled,
  count(*) filter (where round(latest_under3_odds,2)=1.65 and status='settled' and goals_3plus_hit is true) as focus_165_goals_3plus,
  round(100.0 * count(*) filter (where round(latest_under3_odds,2)=1.65 and status='settled' and goals_3plus_hit is true) / nullif(count(*) filter (where round(latest_under3_odds,2)=1.65 and status='settled'),0),2) as focus_165_goals_3plus_rate
from public.under3_low_odds_matches
where latest_under3_odds between 1.60 and 1.75;

create or replace view public.under3_low_odds_stats_by_odds as
select
  trigger_under3_odds,
  count(*) as samples,
  count(*) filter (where status='settled') as settled,
  count(*) filter (where status='settled' and goals_3plus_hit is true) as goals_3plus,
  round(100.0 * count(*) filter (where status='settled' and goals_3plus_hit is true) / nullif(count(*) filter (where status='settled'),0),2) as goals_3plus_rate
from public.under3_low_odds_matches
where trigger_under3_odds between 1.60 and 1.75
group by trigger_under3_odds
order by trigger_under3_odds;

create or replace view public.under3_low_odds_stats_by_main_line as
select
  coalesce(latest_main_ou_line, trigger_main_ou_line) as trigger_main_ou_line,
  count(*) as samples,
  count(*) filter (where status='settled') as settled,
  count(*) filter (where status='settled' and goals_3plus_hit is true) as goals_3plus,
  round(100.0 * count(*) filter (where status='settled' and goals_3plus_hit is true) / nullif(count(*) filter (where status='settled'),0),2) as goals_3plus_rate
from public.under3_low_odds_matches
where latest_under3_odds between 1.60 and 1.75
group by coalesce(latest_main_ou_line, trigger_main_ou_line)
order by coalesce(latest_main_ou_line, trigger_main_ou_line);

create or replace view public.under3_low_odds_stats_by_latest_odds as
select
  round(latest_under3_odds,2) as latest_under3_odds,
  count(*) as samples,
  count(*) filter (where status='settled') as settled,
  count(*) filter (where status='settled' and goals_3plus_hit is true) as goals_3plus,
  round(100.0 * count(*) filter (where status='settled' and goals_3plus_hit is true) / nullif(count(*) filter (where status='settled'),0),2) as goals_3plus_rate,
  round(avg(total_goals) filter (where status='settled'),2) as avg_total_goals
from public.under3_low_odds_matches
where latest_under3_odds between 1.60 and 1.75
group by round(latest_under3_odds,2)
order by round(latest_under3_odds,2);

create or replace view public.under3_low_odds_stats_by_trigger_latest as
select
  trigger_under3_odds,
  round(latest_under3_odds,2) as latest_under3_odds,
  count(*) as samples,
  count(*) filter (where status='settled') as settled,
  count(*) filter (where status='settled' and goals_3plus_hit is true) as goals_3plus,
  round(100.0 * count(*) filter (where status='settled' and goals_3plus_hit is true) / nullif(count(*) filter (where status='settled'),0),2) as goals_3plus_rate,
  round(avg(total_goals) filter (where status='settled'),2) as avg_total_goals
from public.under3_low_odds_matches
where trigger_under3_odds between 1.60 and 1.75 and latest_under3_odds is not null
group by trigger_under3_odds, round(latest_under3_odds,2)
order by trigger_under3_odds, round(latest_under3_odds,2);;
