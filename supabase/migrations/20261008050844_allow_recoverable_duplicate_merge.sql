-- Locked recommendation rows remain immutable for normal writes. The only
-- exception is the audited SECURITY DEFINER duplicate merge, identified by an
-- unfinished snapshot row created in the same transaction.

create or replace function public.guard_pre_kickoff_recommendation_snapshot()
returns trigger
language plpgsql
set search_path=pg_catalog,public
as $function$
declare
  snapshot_changed boolean;
  generated_at timestamptz;
begin
  if current_user='postgres' and exists(
    select 1 from public.football_duplicate_merge_audit a
    where a.completed_at is null
      and (a.canonical_match_key=NEW.match_key or a.duplicate_match_key=NEW.match_key
        or (TG_OP='UPDATE' and (a.canonical_match_key=OLD.match_key or a.duplicate_match_key=OLD.match_key)))
  ) then return NEW; end if;

  if TG_OP='INSERT' then
    snapshot_changed:=NEW.investment_recommendation_snapshot is not null;
  else
    snapshot_changed:=NEW.investment_recommendation_snapshot is distinct from OLD.investment_recommendation_snapshot
      or NEW.investment_recommendation_locked_at is distinct from OLD.investment_recommendation_locked_at;
  end if;
  if not snapshot_changed or NEW.investment_recommendation_snapshot is null then return NEW; end if;
  if NEW.investment_recommendation_locked_at is null
    or NEW.investment_recommendation_locked_at>=NEW.kickoff_at
    or NEW.investment_recommendation_locked_at>clock_timestamp()+interval '5 seconds'
    or clock_timestamp()>=NEW.kickoff_at or NEW.status<>'scheduled'
    or nullif(to_jsonb(NEW)->>'settled_at','') is not null
    or nullif(to_jsonb(NEW)->>'result','') is not null then
    raise exception 'Recommendation snapshots must be locked before kickoff for scheduled, unsettled matches' using errcode='23514';
  end if;
  if NEW.investment_recommendation_snapshot ? 'generated_at' then
    generated_at:=(NEW.investment_recommendation_snapshot->>'generated_at')::timestamptz;
    if generated_at>=NEW.kickoff_at then raise exception 'Recommendation generated_at must precede kickoff' using errcode='23514'; end if;
  end if;
  return NEW;
end;
$function$;

create or replace function public.multi_feature_enforce_decision_lock()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
declare
  mutable_or_generated_fields constant text[] := array[
    'result_home_score','result_away_score','settlement_outcome','original_settlement_outcome','profit_u',
    'result_source','settled_at','updated_at','is_primary','is_secondary'
  ];
begin
  if current_user='postgres' and exists(
    select 1 from public.football_duplicate_merge_audit a
    where a.completed_at is null
      and (a.canonical_match_key=NEW.match_key or a.duplicate_match_key=NEW.match_key
        or a.canonical_match_key=OLD.match_key or a.duplicate_match_key=OLD.match_key)
  ) then return NEW; end if;
  if OLD.locked_at is not null
    and (to_jsonb(NEW)-mutable_or_generated_fields) is distinct from (to_jsonb(OLD)-mutable_or_generated_fields) then
    raise exception 'MFDR_LOCKED_DECISION_IMMUTABLE';
  end if;
  return NEW;
end $$;

revoke execute on function public.guard_pre_kickoff_recommendation_snapshot() from public,anon,authenticated;
revoke execute on function public.multi_feature_enforce_decision_lock() from public,anon,authenticated;
grant execute on function public.guard_pre_kickoff_recommendation_snapshot() to service_role;
grant execute on function public.multi_feature_enforce_decision_lock() to service_role;
;
