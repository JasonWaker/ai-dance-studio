create or replace view public.football_feature_stats
with (security_invoker = true) as
with kinds(kind) as (
  values ('away_zero'), ('reversal'), ('rise_075'), ('losing_streak'), ('over_streak')
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
  round(
    100.0 * count(s.id) filter (
      where case when k.kind = 'losing_streak' then s.value < 0 else s.value > 0 end
    ) / nullif(count(s.id) filter (where s.value is not null), 0),
    2
  ) as hit_rate,
  round(
    100.0 * count(s.id) filter (where s.value = 1)
    / nullif(count(s.id) filter (where s.value in (-1, 1)), 0),
    2
  ) as decisive_win_rate
from kinds k
left join public.football_feature_signals s
  on s.kind = k.kind and s.quote_type = 'bookmaker'
group by k.kind;

revoke all on table public.football_feature_stats from anon, authenticated;
grant select on table public.football_feature_stats to service_role;
;
