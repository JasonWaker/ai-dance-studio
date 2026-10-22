alter table public.football_feature_signals
  add column if not exists source_count smallint not null default 1 check (source_count >= 1),
  add column if not exists verification_status text not null default 'single_source'
    check (verification_status in ('cross_verified', 'history_verified', 'single_source')),
  add column if not exists included_in_stats boolean not null default false;

with bookmaker_counts as (
  select match_key, kind, count(distinct bookmaker)::smallint as source_count
  from public.football_feature_signals
  where quote_type = 'bookmaker'
  group by match_key, kind
)
update public.football_feature_signals s
set source_count = case
      when s.quote_type = 'market_median' then greatest(3, coalesce((s.evidence->>'source_count')::smallint, 3))
      when s.quote_type = 'bookmaker' then greatest(1, coalesce(c.source_count, 1))
      else 1
    end,
    verification_status = case
      when s.quote_type = 'market_median' then 'cross_verified'
      when s.quote_type = 'bookmaker' and coalesce(c.source_count, 1) >= 3 then 'cross_verified'
      when s.quote_type = 'aggregate_reference' and s.kind in ('losing_streak', 'over_streak') then 'history_verified'
      else 'single_source'
    end,
    included_in_stats = case
      when s.quote_type = 'market_median' then true
      when s.quote_type = 'bookmaker' and coalesce(c.source_count, 1) >= 3 then true
      when s.quote_type = 'aggregate_reference' and s.kind in ('losing_streak', 'over_streak') then true
      else false
    end
from bookmaker_counts c
where c.match_key = s.match_key and c.kind = s.kind;

update public.football_feature_signals s
set source_count = case when s.quote_type = 'market_median' then greatest(3, coalesce((s.evidence->>'source_count')::smallint, 3)) else 1 end,
    verification_status = case
      when s.quote_type = 'market_median' then 'cross_verified'
      when s.quote_type = 'aggregate_reference' and s.kind in ('losing_streak', 'over_streak') then 'history_verified'
      else 'single_source'
    end,
    included_in_stats = case
      when s.quote_type = 'market_median' then true
      when s.quote_type = 'aggregate_reference' and s.kind in ('losing_streak', 'over_streak') then true
      else false
    end
where s.quote_type <> 'bookmaker'
   or not exists (
     select 1 from public.football_feature_signals b
     where b.match_key = s.match_key and b.kind = s.kind and b.quote_type = 'bookmaker'
   );

create or replace function public.set_football_feature_signal_verification()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  evidence_count integer := greatest(1, coalesce((new.evidence->>'source_count')::integer, 1));
begin
  new.source_count := evidence_count;
  if new.quote_type = 'market_median' or (new.quote_type = 'bookmaker' and evidence_count >= 3) then
    new.verification_status := 'cross_verified';
    new.included_in_stats := true;
  elsif new.quote_type = 'aggregate_reference' and new.kind in ('losing_streak', 'over_streak') then
    new.verification_status := 'history_verified';
    new.included_in_stats := true;
  else
    new.verification_status := 'single_source';
    new.included_in_stats := false;
  end if;
  return new;
exception when invalid_text_representation or numeric_value_out_of_range then
  new.source_count := 1;
  new.verification_status := 'single_source';
  new.included_in_stats := false;
  return new;
end
$$;

drop trigger if exists football_feature_signal_verification on public.football_feature_signals;
create trigger football_feature_signal_verification
before insert or update of quote_type, kind, evidence
on public.football_feature_signals
for each row execute function public.set_football_feature_signal_verification();

create index if not exists football_feature_signals_verified_kind_idx
  on public.football_feature_signals (kind, included_in_stats, trigger_at desc);

create or replace view public.football_feature_stats
with (security_invoker = true) as
with kinds(kind) as (
  values ('away_zero'), ('reversal'), ('rise_075'), ('losing_streak'), ('over_streak'), ('weak_favorite')
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

comment on column public.football_feature_signals.verification_status is
  'cross_verified=至少3家公司盘口交叉验证；history_verified=完整历史链核验；single_source=单一聚合参考，需复核。';
comment on column public.football_feature_signals.included_in_stats is
  '仅可信度达到正式统计口径的特征信号为 true。';
;
