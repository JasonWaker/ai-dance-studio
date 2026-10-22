create schema if not exists feature_pool_internal;
revoke all on schema feature_pool_internal from public,anon,authenticated;
create table feature_pool_internal.refresh_state(id boolean primary key default true check(id),dirty_at timestamptz,last_requested_at timestamptz);
insert into feature_pool_internal.refresh_state(id) values(true);
create function feature_pool_internal.mark_dirty() returns trigger language plpgsql security definer set search_path='' as $$
begin
 update feature_pool_internal.refresh_state set dirty_at=coalesce(dirty_at,clock_timestamp()) where id=true;
 return null;
end $$;
revoke all on function feature_pool_internal.mark_dirty() from public,anon,authenticated;
create trigger pool_feature_plan_changed after update of investment_recommendation_snapshot,result on public.football_feature_matches
for each row when (old.investment_recommendation_snapshot is distinct from new.investment_recommendation_snapshot or old.result is distinct from new.result)
execute function feature_pool_internal.mark_dirty();
create trigger pool_under3_plan_changed after update of investment_recommendation_snapshot,settled_at on public.under3_low_odds_matches
for each row when (old.investment_recommendation_snapshot is distinct from new.investment_recommendation_snapshot or old.settled_at is distinct from new.settled_at)
execute function feature_pool_internal.mark_dirty();
create trigger pool_feature_settled after update of outcome on public.football_feature_signals
for each row when (old.outcome is distinct from new.outcome) execute function feature_pool_internal.mark_dirty();
create function feature_pool_internal.dispatch_refresh() returns bigint language plpgsql security definer set search_path='' as $$
declare request_id bigint;
begin
 update feature_pool_internal.refresh_state set dirty_at=null,last_requested_at=clock_timestamp()
 where id=true and dirty_at<clock_timestamp()-interval '30 seconds'
 and (last_requested_at is null or last_requested_at<clock_timestamp()-interval '90 seconds');
 if not found then return null; end if;
 select net.http_post(url:='https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/football-feature-scan/push-sync',
 headers:=jsonb_build_object('Content-Type','application/json','x-scan-key',(select scan_key from public.ah0_scanner_config where id=true)),
 body:='{}'::jsonb,timeout_milliseconds:=120000) into request_id;
 return request_id;
end $$;
revoke all on function feature_pool_internal.dispatch_refresh() from public,anon,authenticated;
select cron.alter_job((select jobid from cron.job where jobname='football-feature-push-sync'),schedule:='*/10 * * * *');
select cron.schedule('football-feature-pool-dirty-dispatch','* * * * *','select feature_pool_internal.dispatch_refresh();');
;
