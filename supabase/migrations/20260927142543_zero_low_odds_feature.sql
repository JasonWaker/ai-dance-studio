-- 让0低水：市场中位让球为 0，严格低水一方的十进制水位在 1.50-1.70。
-- 正向统计低水方不败（胜/平），反向统计高水方取胜（低水方负）。
alter table public.football_feature_signals
  drop constraint football_feature_signals_kind_check;
alter table public.football_feature_signals
  add constraint football_feature_signals_kind_check
  check (kind = any (array[
    'away_zero','home_weak_zero','reversal','rise_075','handicap_rise_05',
    'losing_streak','winning_streak','over_streak','under_streak','weak_favorite',
    'total_line_jump','home_receive_225_25','h2h_over_70',
    'home_dragon','away_worm','five_plus_total','underdog_075','total_35',
    'zero_low_odds'
  ]));
create or replace view public.football_feature_stats
with (security_invoker = true) as
with kinds(kind) as (
  values ('away_zero'), ('home_weak_zero'), ('reversal'), ('rise_075'),
    ('handicap_rise_05'), ('losing_streak'), ('over_streak'), ('under_streak'),
    ('winning_streak'), ('weak_favorite'), ('total_line_jump'),
    ('home_receive_225_25'), ('h2h_over_70'), ('home_dragon'),
    ('away_worm'), ('underdog_075'), ('total_35'), ('zero_low_odds')
), signal_pool as (
  select s.*
  from public.football_feature_signals s
  where s.kind not in ('underdog_075', 'total_35', 'zero_low_odds')
  union all
  select water.* from (
    select distinct on (s.kind, s.match_key) s.*
    from public.football_feature_signals s
    where s.kind in ('underdog_075', 'total_35', 'zero_low_odds')
    order by s.kind, s.match_key, s.trigger_at, s.source_count desc, s.id
  ) water
)
select
  k.kind,
  count(s.id) as samples,
  count(distinct s.match_key) as matches,
  count(s.id) filter (where s.outcome is null) as pending,
  count(s.id) filter (where s.outcome = 'VOID') as voids,
  count(s.id) filter (where s.value is not null and (k.kind not in ('losing_streak','winning_streak','over_streak','under_streak','home_dragon','away_worm') or s.value <> 0)) as settled,
  count(s.id) filter (where s.value = 1) as wins,
  count(s.id) filter (where s.value = 0.5) as half_wins,
  count(s.id) filter (where s.value = 0) as pushes,
  count(s.id) filter (where s.value = -0.5) as half_losses,
  count(s.id) filter (where s.value = -1) as losses,
  round(100.0 * count(s.id) filter (where case
    when k.kind in ('away_zero','home_weak_zero','zero_low_odds') then s.value >= 0
    when k.kind in ('losing_streak','away_worm') then s.value < 0
    else s.value > 0 end)
    / nullif(count(s.id) filter (where s.value is not null and (k.kind not in ('losing_streak','winning_streak','over_streak','under_streak','home_dragon','away_worm') or s.value <> 0)), 0), 2) as hit_rate,
  round(100.0 * count(s.id) filter (where case when k.kind in ('away_zero','home_weak_zero','zero_low_odds') then s.value >= 0 else s.value = 1 end)
    / nullif(count(s.id) filter (where case when k.kind in ('away_zero','home_weak_zero','zero_low_odds') then s.value is not null else s.value in (-1,1) end), 0), 2) as decisive_win_rate,
  count(s.id) filter (where s.included_in_stats) as official_samples,
  count(distinct s.match_key) filter (where s.included_in_stats) as official_matches,
  count(s.id) filter (where s.included_in_stats and s.outcome is null) as official_pending,
  count(s.id) filter (where s.included_in_stats and s.value is not null and (k.kind not in ('losing_streak','winning_streak','over_streak','under_streak','home_dragon','away_worm') or s.value <> 0)) as official_settled,
  count(s.id) filter (where s.included_in_stats and s.value = 1) as official_wins,
  count(s.id) filter (where s.included_in_stats and s.value = 0.5) as official_half_wins,
  count(s.id) filter (where s.included_in_stats and s.value = 0) as official_pushes,
  count(s.id) filter (where s.included_in_stats and s.value = -0.5) as official_half_losses,
  count(s.id) filter (where s.included_in_stats and s.value = -1) as official_losses,
  round(100.0 * count(s.id) filter (where s.included_in_stats and case
    when k.kind in ('away_zero','home_weak_zero','zero_low_odds') then s.value >= 0
    when k.kind in ('losing_streak','away_worm') then s.value < 0
    else s.value > 0 end)
    / nullif(count(s.id) filter (where s.included_in_stats and s.value is not null and (k.kind not in ('losing_streak','winning_streak','over_streak','under_streak','home_dragon','away_worm') or s.value <> 0)), 0), 2) as official_hit_rate
from kinds k
left join signal_pool s on s.kind = k.kind
group by k.kind;
create or replace view public.football_feature_stats_by_bookmaker
with (security_invoker = true) as
with signal_pool as (
  select s.*
  from public.football_feature_signals s
  where s.kind not in ('underdog_075', 'total_35', 'zero_low_odds')
  union all
  select water.* from (
    select distinct on (s.kind, s.match_key) s.*
    from public.football_feature_signals s
    where s.kind in ('underdog_075', 'total_35', 'zero_low_odds')
    order by s.kind, s.match_key, s.trigger_at, s.source_count desc, s.id
  ) water
)
select
  s.quote_type, s.bookmaker, s.kind,
  count(*) as samples,
  count(distinct s.match_key) as matches,
  count(*) filter (where s.value is not null and (s.kind not in ('losing_streak','winning_streak','over_streak','under_streak','home_dragon','away_worm') or s.value <> 0)) as settled,
  count(*) filter (where s.outcome is null) as pending,
  count(*) filter (where s.value = 1) as wins,
  count(*) filter (where s.value = 0.5) as half_wins,
  count(*) filter (where s.value = 0) as pushes,
  count(*) filter (where s.value = -0.5) as half_losses,
  count(*) filter (where s.value = -1) as losses,
  round(100.0 * count(*) filter (where case
    when s.kind in ('away_zero','home_weak_zero','zero_low_odds') then s.value >= 0
    when s.kind in ('losing_streak','away_worm') then s.value < 0
    else s.value > 0 end)
    / nullif(count(*) filter (where s.value is not null and (s.kind not in ('losing_streak','winning_streak','over_streak','under_streak','home_dragon','away_worm') or s.value <> 0)), 0), 2) as hit_rate,
  count(*) filter (where s.included_in_stats) as official_samples,
  count(distinct s.match_key) filter (where s.included_in_stats) as official_matches,
  count(*) filter (where s.included_in_stats and s.value is not null and (s.kind not in ('losing_streak','winning_streak','over_streak','under_streak','home_dragon','away_worm') or s.value <> 0)) as official_settled,
  round(100.0 * count(*) filter (where s.included_in_stats and case
    when s.kind in ('away_zero','home_weak_zero','zero_low_odds') then s.value >= 0
    when s.kind in ('losing_streak','away_worm') then s.value < 0
    else s.value > 0 end)
    / nullif(count(*) filter (where s.included_in_stats and s.value is not null and (s.kind not in ('losing_streak','winning_streak','over_streak','under_streak','home_dragon','away_worm') or s.value <> 0)), 0), 2) as official_hit_rate
from signal_pool s
group by s.quote_type, s.bookmaker, s.kind;
revoke all on table public.football_feature_stats from anon, authenticated;
revoke all on table public.football_feature_stats_by_bookmaker from anon, authenticated;
grant select on table public.football_feature_stats to service_role;
grant select on table public.football_feature_stats_by_bookmaker to service_role;
comment on constraint football_feature_signals_kind_check on public.football_feature_signals is
  '统一足球特征枚举；zero_low_odds=让0盘中低水方十进制水位1.50-1.70，统计低水方不败。';
