-- Keep every discovered feature visible while preserving a separate, stricter official-statistics scope.
create or replace view public.football_feature_stats
with (security_invoker = true) as
with kinds(kind) as (
  values ('away_zero'),('reversal'),('rise_075'),('losing_streak'),('over_streak'),('weak_favorite'),('total_line_jump')
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
  round(100.0 * count(s.id) filter (where case when k.kind = 'losing_streak' then s.value < 0 else s.value > 0 end) / nullif(count(s.id) filter (where s.value is not null), 0), 2) as hit_rate,
  round(100.0 * count(s.id) filter (where s.value = 1) / nullif(count(s.id) filter (where s.value in (-1, 1)), 0), 2) as decisive_win_rate,
  count(s.id) filter (where s.included_in_stats) as official_samples,
  count(distinct s.match_key) filter (where s.included_in_stats) as official_matches,
  count(s.id) filter (where s.included_in_stats and s.outcome is null) as official_pending,
  count(s.id) filter (where s.included_in_stats and s.value is not null) as official_settled,
  count(s.id) filter (where s.included_in_stats and s.value = 1) as official_wins,
  count(s.id) filter (where s.included_in_stats and s.value = 0.5) as official_half_wins,
  count(s.id) filter (where s.included_in_stats and s.value = 0) as official_pushes,
  count(s.id) filter (where s.included_in_stats and s.value = -0.5) as official_half_losses,
  count(s.id) filter (where s.included_in_stats and s.value = -1) as official_losses,
  round(100.0 * count(s.id) filter (where s.included_in_stats and case when k.kind = 'losing_streak' then s.value < 0 else s.value > 0 end) / nullif(count(s.id) filter (where s.included_in_stats and s.value is not null), 0), 2) as official_hit_rate
from kinds k
left join public.football_feature_signals s on s.kind = k.kind
group by k.kind;

create or replace view public.football_feature_stats_by_bookmaker
with (security_invoker = true) as
select
  s.quote_type,s.bookmaker,s.kind,
  count(*) as samples,
  count(distinct s.match_key) as matches,
  count(*) filter (where s.value is not null) as settled,
  count(*) filter (where s.outcome is null) as pending,
  count(*) filter (where s.value = 1) as wins,
  count(*) filter (where s.value = 0.5) as half_wins,
  count(*) filter (where s.value = 0) as pushes,
  count(*) filter (where s.value = -0.5) as half_losses,
  count(*) filter (where s.value = -1) as losses,
  round(100.0 * count(*) filter (where case when s.kind = 'losing_streak' then s.value < 0 else s.value > 0 end) / nullif(count(*) filter (where s.value is not null), 0), 2) as hit_rate,
  count(*) filter (where s.included_in_stats) as official_samples,
  count(distinct s.match_key) filter (where s.included_in_stats) as official_matches,
  count(*) filter (where s.included_in_stats and s.value is not null) as official_settled,
  round(100.0 * count(*) filter (where s.included_in_stats and case when s.kind = 'losing_streak' then s.value < 0 else s.value > 0 end) / nullif(count(*) filter (where s.included_in_stats and s.value is not null), 0), 2) as official_hit_rate
from public.football_feature_signals s
group by s.quote_type,s.bookmaker,s.kind;

revoke all on table public.football_feature_stats from anon, authenticated;
revoke all on table public.football_feature_stats_by_bookmaker from anon, authenticated;
grant select on table public.football_feature_stats to service_role;
grant select on table public.football_feature_stats_by_bookmaker to service_role;

comment on view public.football_feature_stats is 'All feature signals remain visible in the base columns; official_* columns include only verified signals eligible for official performance statistics.';;
