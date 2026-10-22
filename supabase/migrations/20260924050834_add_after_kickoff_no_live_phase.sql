alter table public.multi_feature_decisions
  add column analysis_phase text not null default 'pre_match'
    check (analysis_phase in ('pre_match','after_kickoff_no_live')),
  add column locked_at timestamptz,
  add column source_cutoff_at timestamptz;
update public.multi_feature_decisions
set source_cutoff_at = calculated_at
where source_cutoff_at is null;
create index multi_feature_decisions_phase_idx
  on public.multi_feature_decisions(analysis_phase,calculated_at desc);
create or replace function public.multi_feature_enforce_decision_lock()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
declare
  settlement_fields constant text[] := array[
    'result_home_score','result_away_score','settlement_outcome','profit_u',
    'result_source','settled_at','updated_at'
  ];
begin
  if old.locked_at is not null
     and (to_jsonb(new) - settlement_fields) is distinct from (to_jsonb(old) - settlement_fields) then
    raise exception 'MFDR_LOCKED_DECISION_IMMUTABLE';
  end if;
  return new;
end $$;
create trigger multi_feature_decisions_immutable_lock
before update on public.multi_feature_decisions
for each row execute function public.multi_feature_enforce_decision_lock();
drop view if exists public.multi_feature_decision_stats;
create view public.multi_feature_decision_stats with (security_invoker=true) as
select
  analysis_phase,
  grade,
  market_type,
  independent_module_count,
  case
    when conflict_index < .20 then 'low'
    when conflict_index < .35 then 'mild'
    when conflict_index <= .50 then 'medium'
    else 'high'
  end as conflict_bucket,
  feature_combination,
  count(*) filter (where decision_status='RECOMMEND') as recommendations,
  count(*) filter (where settlement_outcome is not null) as settled,
  count(*) filter (where settlement_outcome in ('WIN','HALF_WIN')) as positive,
  count(*) filter (where settlement_outcome in ('WIN','HALF_WIN','HALF_LOSS','LOSS')) as decisive,
  round(avg(expected_value) filter (where decision_status='RECOMMEND'),6) as average_ev,
  round(sum(profit_u) filter (where settlement_outcome is not null),4) as profit_u,
  round(sum(profit_u) filter (where settlement_outcome is not null) /
    nullif(sum(recommended_units) filter (where settlement_outcome is not null),0),6) as roi
from public.multi_feature_decisions
group by analysis_phase,grade,market_type,independent_module_count,conflict_bucket,feature_combination;
revoke all on public.multi_feature_decision_stats from public,anon,authenticated;
grant select on public.multi_feature_decision_stats to service_role;
revoke execute on function public.multi_feature_enforce_decision_lock() from public,anon,authenticated;
grant execute on function public.multi_feature_enforce_decision_lock() to service_role;
comment on column public.multi_feature_decisions.analysis_phase is
  'pre_match means calculated before kickoff; after_kickoff_no_live means calculated after kickoff exclusively from timestamped pre-match inputs.';
comment on column public.multi_feature_decisions.locked_at is
  'Once set, the recommendation is immutable except for result settlement fields.';
comment on column public.multi_feature_decisions.source_cutoff_at is
  'Latest permitted source-data boundary. For after_kickoff_no_live this is the scheduled kickoff timestamp.';
