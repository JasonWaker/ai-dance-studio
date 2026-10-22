-- Append-only review facts. Rollback: redeploy previous code and disable the
-- two capture triggers; retain this ledger for audit, never restore old prices.
create table public.feature_preflight_reviews (
 dataset text not null check(dataset in ('feature','under3')),
 match_key text not null, fixture_key text not null, kind text not null, point text not null,
 initial_direction text not null, group_key text not null,
 movement text not null check(movement in ('up','down','flat','line_changed')),
 kickoff_at timestamptz not null, locked_at timestamptz not null, verified_at timestamptz not null,
 initial_observed_at timestamptz not null, current_observed_at timestamptz not null,
 initial_selection jsonb not null, initial_price numeric not null check(initial_price>1),
 current_line numeric not null, current_price numeric not null check(current_price>1),
 initial_plan jsonb not null, review_recommendation jsonb not null,
 created_at timestamptz not null default clock_timestamp(),
 primary key(dataset,match_key,kind,point,initial_direction),
 check(locked_at<kickoff_at),
 check(initial_observed_at<=locked_at+interval '5 seconds'),
 check(current_observed_at<=verified_at+interval '5 seconds'),
 check(verified_at>=kickoff_at-interval '30 minutes' and verified_at<=kickoff_at-interval '25 minutes')
);
create index on public.feature_preflight_reviews(group_key,verified_at);
alter table public.feature_preflight_reviews enable row level security;
revoke all on public.feature_preflight_reviews from public,anon,authenticated;
grant select,insert on public.feature_preflight_reviews to service_role;

create function public.capture_two_stage_review() returns trigger language plpgsql security invoker
set search_path=pg_catalog,public as $$
declare plan jsonb; root jsonb; selection jsonb; at timestamptz; locked timestamptz; dataset_name text;
begin
 root:=NEW.investment_recommendation_snapshot;
 if root is null or root->>'snapshot_origin' is distinct from 'pre_match' then return NEW; end if;
 locked:=NEW.investment_recommendation_locked_at;
 if locked is null or locked>=NEW.kickoff_at or NEW.kickoff_at<=clock_timestamp() then return NEW; end if;
 dataset_name:=case when TG_TABLE_NAME='under3_low_odds_matches' then 'under3' else 'feature' end;
 for plan in select value from jsonb_array_elements(coalesce(root->'candidates','[]'::jsonb)||jsonb_build_array(root)) loop
  if plan->>'review_policy' is distinct from 'two-stage-v1' or plan->>'status' is distinct from 'recommended'
   or plan->>'preflight_status' not in ('verified','line_changed') then continue; end if;
  at:=(plan->>'preflight_verified_at')::timestamptz;
  if at is null or at<NEW.kickoff_at-interval '30 minutes' or at>NEW.kickoff_at-interval '25 minutes'
   or at>clock_timestamp()+interval '5 seconds' then continue; end if;
  selection:=case when jsonb_typeof(plan->'selection')='object' then plan->'selection'
   else jsonb_build_object('market','total_goals','side',plan->>'side','line',plan->'line') end;
  insert into public.feature_preflight_reviews(dataset,match_key,fixture_key,kind,point,initial_direction,group_key,movement,kickoff_at,locked_at,verified_at,initial_observed_at,current_observed_at,initial_selection,initial_price,current_line,current_price,initial_plan,review_recommendation)
  values(dataset_name,NEW.match_key,coalesce(to_jsonb(NEW)->>'fixture_key',NEW.match_key),plan->>'kind',plan->>'point',coalesce(plan->>'direction',plan->>'side','forward'),
   plan->'review_recommendation'->>'group_key',plan->>'review_movement',NEW.kickoff_at,locked,at,
   coalesce((plan->'preflight_audit'->>'original_observed_at')::timestamptz,(plan->>'locked_market_observed_at')::timestamptz,(plan->>'generated_at')::timestamptz,locked),
   coalesce((plan->'preflight_audit'->>'current_observed_at')::timestamptz,at),selection,
   (plan->'preflight_audit'->>'original_price')::numeric,(plan->'preflight_audit'->>'current_line')::numeric,(plan->'preflight_audit'->>'current_price')::numeric,
   plan-'review_recommendation'-'candidates',plan->'review_recommendation')
  on conflict do nothing;
 end loop;
 return NEW;
end $$;
revoke all on function public.capture_two_stage_review() from public,anon,authenticated;
create trigger capture_feature_two_stage_review after update of investment_recommendation_snapshot on public.football_feature_matches
for each row execute function public.capture_two_stage_review();
create trigger capture_under3_two_stage_review after update of investment_recommendation_snapshot on public.under3_low_odds_matches
for each row execute function public.capture_two_stage_review();

-- Results are joined from authoritative settlement tables, not copied into
-- recommendation snapshots. Corrections change analytics, never past decisions.
create view public.feature_preflight_review_results with (security_invoker=true) as
 select r.*,m.competition_name,m.home_team,m.away_team,
 case when m.result->>'status'='finished' then (m.result->>'home_score')::integer end home_score,
 case when m.result->>'status'='finished' then (m.result->>'away_score')::integer end away_score,
 case when m.result->>'status'='finished' then (select min(s.settled_at) from public.football_feature_signals s where s.match_key=r.match_key and s.kind=r.kind and s.outcome is not null) end settled_at,
 m.result->>'result_source' result_source
 from public.feature_preflight_reviews r join public.football_feature_matches m on m.match_key=r.match_key
 where r.dataset='feature' and not coalesce(m.identity_conflict_active,false)
 union all
 select r.*,m.competition_name,m.home_team,m.away_team,
 case when m.status='settled' then m.home_score end,case when m.status='settled' then m.away_score end,
 case when m.status='settled' then m.settled_at end,m.result_source
 from public.feature_preflight_reviews r join public.under3_low_odds_matches m on m.match_key=r.match_key
 where r.dataset='under3';
revoke all on public.feature_preflight_review_results from public,anon,authenticated;
grant select on public.feature_preflight_review_results to service_role;
;
