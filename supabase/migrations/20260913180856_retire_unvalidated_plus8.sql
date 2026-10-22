-- User-requested retirement. No historical analysis, recommendation or settlement is deleted/rewritten.
create or replace function public.plus8_reject_retired_prediction()
returns trigger language plpgsql security invoker set search_path=public as $guard$
begin
  if TG_OP='UPDATE' then
    if new.units>old.units or (new.is_official is true and old.is_official is not true) then
      raise exception using errcode='55000',message='PLUS8_MODEL_RETIRED: cannot increase stake or promote an archived recommendation';
    end if;
    return new;
  end if;
  raise exception using errcode='55000',message='PLUS8_MODEL_RETIRED: model has no independently validated predictive advantage; new predictions are disabled';
end;
$guard$;
revoke all on function public.plus8_reject_retired_prediction() from public,anon,authenticated;
create trigger plus8_retired_analysis before insert on public.plus8_analyses
for each row execute function public.plus8_reject_retired_prediction();
create trigger plus8_retired_recommendation before insert or update of units,is_official on public.plus8_recommendations
for each row execute function public.plus8_reject_retired_prediction();
comment on function public.plus8_reject_retired_prediction() is 'Retired at user request 2026-09-14 Asia/Shanghai. Historical reading and settlement remain available.';
;
