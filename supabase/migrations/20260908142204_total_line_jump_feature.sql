create table public.football_feature_total_opening_baselines (
  match_key text not null references public.football_feature_matches(match_key) on delete cascade,
  bookmaker text not null,
  source_platform text not null,
  source_url text not null check (source_url ~ '^https://'),
  first_observed_at timestamptz not null,
  first_total_line numeric not null,
  first_over_odds numeric,
  first_under_odds numeric,
  primary key (match_key, bookmaker)
);

alter table public.football_feature_total_opening_baselines enable row level security;
revoke all on public.football_feature_total_opening_baselines from anon, authenticated;
grant all on public.football_feature_total_opening_baselines to service_role;

comment on table public.football_feature_total_opening_baselines is
  'First total-goals line observed by the scanner for each bookmaker. It is a sampling baseline, not an official bookmaker opening line.';

alter table public.football_feature_signals
  drop constraint if exists football_feature_signals_kind_check,
  add constraint football_feature_signals_kind_check
    check (kind in (
      'away_zero', 'reversal', 'rise_075', 'losing_streak',
      'over_streak', 'weak_favorite', 'total_line_jump'
    ));

create or replace view public.football_feature_stats
with (security_invoker = true) as
with kinds(kind) as (
  values ('away_zero'), ('reversal'), ('rise_075'), ('losing_streak'),
         ('over_streak'), ('weak_favorite'), ('total_line_jump')
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
  round(100.0 * count(s.id) filter (
    where case when k.kind = 'losing_streak' then s.value < 0 else s.value > 0 end
  ) / nullif(count(s.id) filter (where s.value is not null), 0), 2) as hit_rate,
  round(100.0 * count(s.id) filter (where s.value = 1)
    / nullif(count(s.id) filter (where s.value in (-1, 1)), 0), 2) as decisive_win_rate
from kinds k
left join public.football_feature_signals s
  on s.kind = k.kind and s.included_in_stats = true
group by k.kind;

create or replace view public.football_feature_stats_by_bookmaker
with (security_invoker = true) as
select
  s.quote_type,
  s.bookmaker,
  s.kind,
  count(*) as samples,
  count(distinct s.match_key) as matches,
  count(*) filter (where s.value is not null) as settled,
  count(*) filter (where s.outcome is null) as pending,
  count(*) filter (where s.value = 1) as wins,
  count(*) filter (where s.value = 0.5) as half_wins,
  count(*) filter (where s.value = 0) as pushes,
  count(*) filter (where s.value = -0.5) as half_losses,
  count(*) filter (where s.value = -1) as losses,
  round(100.0 * count(*) filter (
    where case when s.kind = 'losing_streak' then s.value < 0 else s.value > 0 end
  ) / nullif(count(*) filter (where s.value is not null), 0), 2) as hit_rate
from public.football_feature_signals s
where s.included_in_stats = true
group by s.quote_type, s.bookmaker, s.kind;

revoke all on table public.football_feature_stats from anon, authenticated;
revoke all on table public.football_feature_stats_by_bookmaker from anon, authenticated;
grant select on table public.football_feature_stats to service_role;
grant select on table public.football_feature_stats_by_bookmaker to service_role;

comment on constraint football_feature_signals_kind_check on public.football_feature_signals is
  'total_line_jump = market median total opens at 2.50/2.75 and rises to 3.25-3.50 before kickoff.';
;
