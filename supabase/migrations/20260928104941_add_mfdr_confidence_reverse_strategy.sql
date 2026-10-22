alter table public.multi_feature_decisions
  add column if not exists confidence_bucket text,
  add column if not exists confidence_strategy_direction text not null default 'none'
    check (confidence_strategy_direction in ('none','forward','reverse')),
  add column if not exists confidence_strategy_sample_count integer not null default 0
    check (confidence_strategy_sample_count >= 0),
  add column if not exists confidence_strategy_base_hit_rate numeric(8,6)
    check (confidence_strategy_base_hit_rate between 0 and 1),
  add column if not exists confidence_strategy_rule_version text,
  add column if not exists confidence_strategy_blocked text,
  add column if not exists original_selection text
    check (original_selection in ('home','away','over','under')),
  add column if not exists original_market_line numeric(8,3),
  add column if not exists original_market_odds numeric(8,3),
  add column if not exists original_bookmaker text,
  add column if not exists original_market_observed_at timestamptz,
  add column if not exists original_settlement_outcome text
    check (original_settlement_outcome in ('WIN','HALF_WIN','PUSH','HALF_LOSS','LOSS','VOID'));
-- Existing locked decisions are intentionally immutable. Temporarily suspend
-- that trigger only inside this migration so legacy rows can receive an exact
-- copy of their already-published original recommendation.
alter table public.multi_feature_decisions disable trigger multi_feature_decisions_immutable_lock;
update public.multi_feature_decisions
set
  confidence_bucket = case
    when confidence_score >= 0.9 then '≥90%'
    when confidence_score >= 0.8 then '80%–<90%'
    when confidence_score >= 0.7 then '70%–<80%'
    when confidence_score >= 0.6 then '60%–<70%'
    when confidence_score >= 0.5 then '50%–<60%'
    when confidence_score >= 0.4 then '40%–<50%'
    when confidence_score >= 0.3 then '30%–<40%'
    when confidence_score >= 0.2 then '20%–<30%'
    when confidence_score >= 0.1 then '10%–<20%'
    else '<10%'
  end,
  original_selection = coalesce(original_selection, selection),
  original_market_line = coalesce(original_market_line, market_line),
  original_market_odds = coalesce(original_market_odds, market_odds),
  original_bookmaker = coalesce(original_bookmaker, bookmaker),
  original_market_observed_at = coalesce(original_market_observed_at, market_observed_at),
  original_settlement_outcome = coalesce(original_settlement_outcome, settlement_outcome)
where confidence_bucket is null
   or original_selection is null
   or original_market_line is null
   or original_market_odds is null
   or (settlement_outcome is not null and original_settlement_outcome is null);
alter table public.multi_feature_decisions enable trigger multi_feature_decisions_immutable_lock;
-- Future settlement may append the original recommendation's outcome, but no
-- strategy field or original recommendation input may be changed after lock.
create or replace function public.multi_feature_enforce_decision_lock()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
declare
  mutable_or_generated_fields constant text[] := array[
    'result_home_score','result_away_score','settlement_outcome','original_settlement_outcome','profit_u',
    'result_source','settled_at','updated_at','is_primary','is_secondary'
  ];
begin
  if old.locked_at is not null
     and (to_jsonb(new) - mutable_or_generated_fields)
       is distinct from (to_jsonb(old) - mutable_or_generated_fields) then
    raise exception 'MFDR_LOCKED_DECISION_IMMUTABLE';
  end if;
  return new;
end $$;
revoke execute on function public.multi_feature_enforce_decision_lock() from public,anon,authenticated;
grant execute on function public.multi_feature_enforce_decision_lock() to service_role;
create index if not exists multi_feature_decisions_confidence_strategy_idx
  on public.multi_feature_decisions (confidence_strategy_direction, analysis_phase, locked_at desc);
comment on column public.multi_feature_decisions.confidence_strategy_direction is
  'Recommendation treatment determined from the original settled accuracy of its confidence bucket. Reverse is only used below 30% with the configured minimum sample.';
comment on column public.multi_feature_decisions.original_selection is
  'Immutable model selection before confidence-bucket strategy treatment; used to prevent feedback oscillation.';
comment on column public.multi_feature_decisions.original_settlement_outcome is
  'Settlement of the immutable original model selection; confidence-bucket accuracy is calculated from this value.';
