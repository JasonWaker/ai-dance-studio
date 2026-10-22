-- 连续小球：与连续大球完全独立，按球队最近连续亚洲小球盘 N 场统计
-- 第 N+1 场继续小球率；走盘不进入接续率分母。
alter table public.football_feature_signals
  drop constraint football_feature_signals_kind_check;

alter table public.football_feature_signals
  add constraint football_feature_signals_kind_check
  check (kind = any (array[
    'away_zero','home_weak_zero','reversal','rise_075','handicap_rise_05',
    'losing_streak','winning_streak','over_streak','under_streak','weak_favorite',
    'total_line_jump','home_receive_225_25','h2h_over_70',
    'home_dragon','away_worm','five_plus_total','underdog_075','total_35'
  ]));

-- 连续特征以“球队 + 比赛”为一次机会；同场主客两队可能同时形成连续小球，
-- 因此信号唯一键必须包含 side，不能把两队合并成一条。
drop index if exists public.uq_feature_signal_point;
create unique index uq_feature_signal_point
  on public.football_feature_signals
  (match_key, kind, side, coalesce(handicap, 0), coalesce(total_line, 0));

create or replace view public.football_feature_stats
with (security_invoker = true) as
with kinds(kind) as (
  values ('away_zero'), ('home_weak_zero'), ('reversal'), ('rise_075'),
    ('handicap_rise_05'), ('losing_streak'), ('over_streak'), ('under_streak'),
    ('winning_streak'), ('weak_favorite'), ('total_line_jump'),
    ('home_receive_225_25'), ('h2h_over_70'), ('home_dragon'),
    ('away_worm'), ('underdog_075'), ('total_35')
), signal_pool as (
  select s.*
  from public.football_feature_signals s
  where s.kind not in ('underdog_075', 'total_35')
  union all
  select water.* from (
    select distinct on (s.kind, s.match_key) s.*
    from public.football_feature_signals s
    where s.kind in ('underdog_075', 'total_35')
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
    when k.kind in ('away_zero','home_weak_zero') then s.value >= 0
    when k.kind in ('losing_streak','away_worm') then s.value < 0
    else s.value > 0 end)
    / nullif(count(s.id) filter (where s.value is not null and (k.kind not in ('losing_streak','winning_streak','over_streak','under_streak','home_dragon','away_worm') or s.value <> 0)), 0), 2) as hit_rate,
  round(100.0 * count(s.id) filter (where case when k.kind in ('away_zero','home_weak_zero') then s.value >= 0 else s.value = 1 end)
    / nullif(count(s.id) filter (where case when k.kind in ('away_zero','home_weak_zero') then s.value is not null and (k.kind not in ('losing_streak','winning_streak','over_streak','under_streak','home_dragon','away_worm') or s.value <> 0) else s.value in (-1,1) end), 0), 2) as decisive_win_rate,
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
    when k.kind in ('away_zero','home_weak_zero') then s.value >= 0
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
  where s.kind not in ('underdog_075', 'total_35')
  union all
  select water.* from (
    select distinct on (s.kind, s.match_key) s.*
    from public.football_feature_signals s
    where s.kind in ('underdog_075', 'total_35')
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
    when s.kind in ('away_zero','home_weak_zero') then s.value >= 0
    when s.kind in ('losing_streak','away_worm') then s.value < 0
    else s.value > 0 end)
    / nullif(count(*) filter (where s.value is not null and (s.kind not in ('losing_streak','winning_streak','over_streak','under_streak','home_dragon','away_worm') or s.value <> 0)), 0), 2) as hit_rate,
  count(*) filter (where s.included_in_stats) as official_samples,
  count(distinct s.match_key) filter (where s.included_in_stats) as official_matches,
  count(*) filter (where s.included_in_stats and s.value is not null and (s.kind not in ('losing_streak','winning_streak','over_streak','under_streak','home_dragon','away_worm') or s.value <> 0)) as official_settled,
  round(100.0 * count(*) filter (where s.included_in_stats and case
    when s.kind in ('away_zero','home_weak_zero') then s.value >= 0
    when s.kind in ('losing_streak','away_worm') then s.value < 0
    else s.value > 0 end)
    / nullif(count(*) filter (where s.included_in_stats and s.value is not null and (s.kind not in ('losing_streak','winning_streak','over_streak','under_streak','home_dragon','away_worm') or s.value <> 0)), 0), 2) as official_hit_rate
from signal_pool s
group by s.quote_type, s.bookmaker, s.kind;

do $migration$
declare
  definition text;
begin
  definition := pg_get_functiondef('public.football_feature_normalize_source_metadata()'::regprocedure);
  if position('under_streak' in definition) = 0 then
    definition := replace(definition,
      $$new.kind in ('losing_streak', 'winning_streak', 'over_streak', 'home_dragon', 'away_worm')$$,
      $$new.kind in ('losing_streak', 'winning_streak', 'over_streak', 'under_streak', 'home_dragon', 'away_worm')$$);
    if position('under_streak' in definition) = 0 then raise exception 'football_feature_normalize_source_metadata definition changed'; end if;
    execute definition;
  end if;

  definition := pg_get_functiondef('public.football_feature_refresh_history_evidence(jsonb)'::regprocedure);
  if position('under_streak' in definition) = 0 then
    definition := replace(definition,
      $$s->>'kind' in ('losing_streak', 'winning_streak', 'over_streak', 'home_dragon', 'away_worm')$$,
      $$s->>'kind' in ('losing_streak', 'winning_streak', 'over_streak', 'under_streak', 'home_dragon', 'away_worm')$$);
    if position('under_streak' in definition) = 0 then raise exception 'football_feature_refresh_history_evidence definition changed'; end if;
    execute definition;
  end if;

  definition := pg_get_functiondef('public.football_feature_commit(uuid,jsonb,jsonb)'::regprocedure);
  if position('under_streak' in definition) = 0 then
    definition := replace(definition,
      $$s->>'kind' in ('losing_streak','winning_streak','over_streak')$$,
      $$s->>'kind' in ('losing_streak','winning_streak','over_streak','under_streak')$$);
    if position('under_streak' in definition) = 0 then raise exception 'football_feature_commit history-kind definition changed'; end if;
  end if;
  definition := replace(definition,
    $$on conflict (match_key, kind, (coalesce(handicap, 0)), (coalesce(total_line, 0)))$$,
    $$on conflict (match_key, kind, side, (coalesce(handicap, 0)), (coalesce(total_line, 0)))$$);
  if position('on conflict (match_key, kind, side,' in definition) = 0 then raise exception 'football_feature_commit conflict target changed'; end if;
  execute definition;
end
$migration$;

revoke all on table public.football_feature_stats from anon, authenticated;
revoke all on table public.football_feature_stats_by_bookmaker from anon, authenticated;
grant select on table public.football_feature_stats to service_role;
grant select on table public.football_feature_stats_by_bookmaker to service_role;

comment on constraint football_feature_signals_kind_check on public.football_feature_signals is
  '统一足球特征枚举；under_streak=球队赛前连续亚洲小球盘至少2场。';
;
