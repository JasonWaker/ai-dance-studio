-- Run after both the snapshot guard and the terminal-state guard. A caller
-- cannot restore the old formal-inclusion flag while the status stays abandoned.
create function public.enforce_abandoned_sample_exclusion() returns trigger
language plpgsql security invoker set search_path=pg_catalog,public as $$
begin
 if NEW.sample_status='abandoned_preflight_deviation' then
  NEW.included_in_stats:=false;
  if TG_OP='UPDATE' and OLD.sample_status='abandoned_preflight_deviation' then
   NEW.sample_excluded_at:=OLD.sample_excluded_at;
  end if;
 end if;
 return NEW;
end $$;
create trigger zzzzz_abandoned_sample_exclusion before insert or update on public.football_feature_signals
for each row execute function public.enforce_abandoned_sample_exclusion();
revoke all on function public.enforce_abandoned_sample_exclusion() from public,anon,authenticated;
grant execute on function public.enforce_abandoned_sample_exclusion() to service_role;
;
