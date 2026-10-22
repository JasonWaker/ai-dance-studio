-- Authorized discard of the Data Center (5 major leagues) only.
-- Archive in a private, ungranted schema before clearing the active dataset.
create schema plus8_retired_20260914;
revoke all on schema plus8_retired_20260914 from public,anon,authenticated,service_role;
lock table public.plus8_matches, public.plus8_analyses, public.plus8_recommendations, public.plus8_settlements, public.plus8_daily_stats, public.plus8_admin_audit_log in access exclusive mode;
create table plus8_retired_20260914.plus8_matches as table public.plus8_matches;
alter table plus8_retired_20260914.plus8_matches enable row level security;
revoke all on table plus8_retired_20260914.plus8_matches from public,anon,authenticated,service_role;
do $verify$
begin
  if exists(select to_jsonb(s) from public.plus8_matches s except all select to_jsonb(a) from plus8_retired_20260914.plus8_matches a)
     or exists(select to_jsonb(a) from plus8_retired_20260914.plus8_matches a except all select to_jsonb(s) from public.plus8_matches s) then
    raise exception 'archive content mismatch: plus8_matches';
  end if;
end $verify$;
create table plus8_retired_20260914.plus8_analyses as table public.plus8_analyses;
alter table plus8_retired_20260914.plus8_analyses enable row level security;
revoke all on table plus8_retired_20260914.plus8_analyses from public,anon,authenticated,service_role;
do $verify$
begin
  if exists(select to_jsonb(s) from public.plus8_analyses s except all select to_jsonb(a) from plus8_retired_20260914.plus8_analyses a)
     or exists(select to_jsonb(a) from plus8_retired_20260914.plus8_analyses a except all select to_jsonb(s) from public.plus8_analyses s) then
    raise exception 'archive content mismatch: plus8_analyses';
  end if;
end $verify$;
create table plus8_retired_20260914.plus8_recommendations as table public.plus8_recommendations;
alter table plus8_retired_20260914.plus8_recommendations enable row level security;
revoke all on table plus8_retired_20260914.plus8_recommendations from public,anon,authenticated,service_role;
do $verify$
begin
  if exists(select to_jsonb(s) from public.plus8_recommendations s except all select to_jsonb(a) from plus8_retired_20260914.plus8_recommendations a)
     or exists(select to_jsonb(a) from plus8_retired_20260914.plus8_recommendations a except all select to_jsonb(s) from public.plus8_recommendations s) then
    raise exception 'archive content mismatch: plus8_recommendations';
  end if;
end $verify$;
create table plus8_retired_20260914.plus8_settlements as table public.plus8_settlements;
alter table plus8_retired_20260914.plus8_settlements enable row level security;
revoke all on table plus8_retired_20260914.plus8_settlements from public,anon,authenticated,service_role;
do $verify$
begin
  if exists(select to_jsonb(s) from public.plus8_settlements s except all select to_jsonb(a) from plus8_retired_20260914.plus8_settlements a)
     or exists(select to_jsonb(a) from plus8_retired_20260914.plus8_settlements a except all select to_jsonb(s) from public.plus8_settlements s) then
    raise exception 'archive content mismatch: plus8_settlements';
  end if;
end $verify$;
create table plus8_retired_20260914.plus8_daily_stats as table public.plus8_daily_stats;
alter table plus8_retired_20260914.plus8_daily_stats enable row level security;
revoke all on table plus8_retired_20260914.plus8_daily_stats from public,anon,authenticated,service_role;
do $verify$
begin
  if exists(select to_jsonb(s) from public.plus8_daily_stats s except all select to_jsonb(a) from plus8_retired_20260914.plus8_daily_stats a)
     or exists(select to_jsonb(a) from plus8_retired_20260914.plus8_daily_stats a except all select to_jsonb(s) from public.plus8_daily_stats s) then
    raise exception 'archive content mismatch: plus8_daily_stats';
  end if;
end $verify$;
create table plus8_retired_20260914.plus8_admin_audit_log as table public.plus8_admin_audit_log;
alter table plus8_retired_20260914.plus8_admin_audit_log enable row level security;
revoke all on table plus8_retired_20260914.plus8_admin_audit_log from public,anon,authenticated,service_role;
do $verify$
begin
  if exists(select to_jsonb(s) from public.plus8_admin_audit_log s except all select to_jsonb(a) from plus8_retired_20260914.plus8_admin_audit_log a)
     or exists(select to_jsonb(a) from plus8_retired_20260914.plus8_admin_audit_log a except all select to_jsonb(s) from public.plus8_admin_audit_log s) then
    raise exception 'archive content mismatch: plus8_admin_audit_log';
  end if;
end $verify$;
truncate table public.plus8_matches, public.plus8_analyses, public.plus8_recommendations, public.plus8_settlements, public.plus8_daily_stats, public.plus8_admin_audit_log restrict;
-- Keep the shared login and independent-module navigation settings.
update public.plus8_site_settings
set setting_value=jsonb_set(setting_value,'{items}',coalesce((select jsonb_agg(item order by ord)
from jsonb_array_elements(setting_value->'items') with ordinality as x(item,ord)
where item->>'key'<>'dashboard'),'[]'::jsonb)),updated_at=now()
where setting_key='navigation';
select cron.alter_job(jobid,active:=false) from cron.job where jobname='plus8-settle-confirmed-results';
-- Prevent any retired writer repopulating empty data-center tables.
create trigger plus8_discarded_match before insert on public.plus8_matches
for each row execute function public.plus8_reject_retired_prediction();
create trigger plus8_discarded_settlement before insert on public.plus8_settlements
for each row execute function public.plus8_reject_retired_prediction();
create trigger plus8_discarded_daily_stat before insert on public.plus8_daily_stats
for each row execute function public.plus8_reject_retired_prediction();
comment on schema plus8_retired_20260914 is 'Discarded Plus8 dataset; recovery-only archive, excluded from analysis, APIs and future models. User request 2026-09-14.';
;
