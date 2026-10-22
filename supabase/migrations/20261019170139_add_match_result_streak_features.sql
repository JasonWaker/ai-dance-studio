-- Independent match-result observations. No historical recommendation backfill.
do $$
declare definition text;
begin
  select pg_get_constraintdef(oid) into definition from pg_constraint
    where conrelid='public.football_feature_signals'::regclass and conname='football_feature_signals_kind_check';
  if definition is null or position('zero_low_odds' in definition)=0 then raise exception 'Unexpected feature kind constraint'; end if;
  definition:=replace(definition,'''zero_low_odds''::text','''zero_low_odds''::text, ''match_losing_streak''::text, ''match_winning_streak''::text');
  alter table public.football_feature_signals drop constraint football_feature_signals_kind_check;
  execute 'alter table public.football_feature_signals add constraint football_feature_signals_kind_check '||definition;
end $$;

create or replace function public.freeze_match_result_streak_evidence()
returns trigger language plpgsql security invoker set search_path=pg_catalog,public as $$
begin
  if OLD.kind in ('match_losing_streak','match_winning_streak') then
    NEW.evidence:=OLD.evidence; NEW.trigger_at:=OLD.trigger_at;
    NEW.source_platform:=OLD.source_platform; NEW.source_url:=OLD.source_url;
    NEW.source_count:=OLD.source_count; NEW.verification_status:=OLD.verification_status;
    NEW.included_in_stats:=OLD.included_in_stats;
  end if;
  return NEW;
end $$;
create trigger freeze_match_result_streak_evidence before update on public.football_feature_signals
for each row when (OLD.kind in ('match_losing_streak','match_winning_streak')) execute function public.freeze_match_result_streak_evidence();
revoke all on function public.freeze_match_result_streak_evidence() from public,anon,authenticated;
grant execute on function public.freeze_match_result_streak_evidence() to service_role;

create index football_result_streak_samples_idx on public.football_feature_signals(kind,trigger_at desc)
where kind in ('match_losing_streak','match_winning_streak');
;
