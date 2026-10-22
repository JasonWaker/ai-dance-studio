-- Complete the existing settlement workflow; never infer or fabricate a score.
create or replace view public.plus8_pending_settlements with (security_invoker=true) as
select m.id as match_id,m.match_key,m.kickoff_time,m.home_team,m.away_team,m.league_name,
 a.id as final_analysis_id,rt.id as primary_total_recommendation_id,a.analysis_source,a.model_name,a.model_version
from public.plus8_matches m
join public.plus8_final_pre_match_analysis a on a.match_id=m.id
left join public.plus8_recommendations rt on rt.analysis_id=a.id and rt.market_type='total_goals' and rt.is_primary and rt.is_official
left join public.plus8_recommendations rh on rh.analysis_id=a.id and rh.market_type='asian_handicap' and rh.is_primary and rh.is_official
left join public.plus8_settlements s on s.match_id=m.id
where s.id is null and m.status not in ('cancelled','postponed') and m.kickoff_time<=now()
  and (rt.id is not null or rh.id is not null);

create schema if not exists plus8_internal;
revoke all on schema plus8_internal from public,anon,authenticated;
grant usage on schema plus8_internal to service_role;
create or replace function plus8_internal.settle_confirmed_results()
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $body$
declare m public.plus8_matches%rowtype; n integer:=0;
begin
 for m in
   select p.* from public.plus8_matches p
   where p.status='finished' and p.result_confirmed=true and p.home_score is not null and p.away_score is not null
     and p.kickoff_time<now() and nullif(trim(p.result_source),'') is not null
     and not exists(select 1 from public.plus8_settlements s where s.match_id=p.id)
   order by p.kickoff_time,p.id limit 100 for update skip locked
 loop
   perform public.plus8_settle_match(m.match_key,m.home_score,m.away_score,m.result_source);
   n:=n+1;
 end loop;
 return jsonb_build_object('settled_count',n,'score_policy','existing confirmed 90-minute scores only');
end;
$body$;
revoke all on function plus8_internal.settle_confirmed_results() from public,anon,authenticated;
grant execute on function plus8_internal.settle_confirmed_results() to service_role;
select cron.schedule('plus8-settle-confirmed-results','*/10 * * * *','select plus8_internal.settle_confirmed_results();');
;
