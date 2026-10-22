alter table public.plus8_analyses
  add column if not exists analysis_source text not null default 'manual_analysis';

alter table public.plus8_analyses
  drop constraint if exists plus8_analyses_analysis_source_check;

alter table public.plus8_analyses
  add constraint plus8_analyses_analysis_source_check
  check (analysis_source in ('system_scan','manual_analysis','legacy_unclassified'));

create index if not exists idx_plus8_analyses_source
  on public.plus8_analyses (analysis_source, model_version, analysis_time desc);

create or replace function public.plus8_sync_analysis(
  p_match jsonb,
  p_analysis jsonb,
  p_recommendations jsonb,
  p_analysis_key text
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_match_id uuid;
  v_analysis_id uuid;
  v_recommendation_ids uuid[] := array[]::uuid[];
  v_recommendation jsonb;
  v_recommendation_id uuid;
  v_inserted boolean := false;
  v_analysis_source text;
begin
  if jsonb_typeof(p_recommendations) <> 'array' then
    raise exception using errcode = '22023', message = 'recommendations must be an array';
  end if;

  v_analysis_source := coalesce(nullif(p_analysis->>'analysis_source',''), 'manual_analysis');
  if v_analysis_source not in ('system_scan','manual_analysis','legacy_unclassified') then
    raise exception using errcode = '22023', message = 'analysis_source must be system_scan, manual_analysis, or legacy_unclassified';
  end if;

  insert into public.plus8_matches (
    match_key, league_name, league_country, league_level,
    home_team, away_team, kickoff_time
  ) values (
    p_match->>'match_key', p_match->>'league_name', p_match->>'league_country',
    p_match->>'league_level', p_match->>'home_team', p_match->>'away_team',
    (p_match->>'kickoff_time')::timestamptz
  )
  on conflict (match_key) do update set
    league_name = excluded.league_name,
    league_country = coalesce(excluded.league_country, plus8_matches.league_country),
    league_level = coalesce(excluded.league_level, plus8_matches.league_level),
    home_team = excluded.home_team,
    away_team = excluded.away_team,
    kickoff_time = excluded.kickoff_time
  returning id into v_match_id;

  insert into public.plus8_analyses (
    match_id, analysis_key, model_name, model_version, analysis_type,
    analysis_time, is_valid, data_completeness, confidence,
    model_total_lambda, predicted_scores, notes, analysis_source
  ) values (
    v_match_id, p_analysis_key, p_analysis->>'model_name', p_analysis->>'model_version',
    p_analysis->>'analysis_type', (p_analysis->>'analysis_time')::timestamptz,
    coalesce((p_analysis->>'is_valid')::boolean, true),
    (p_analysis->>'data_completeness')::integer,
    (p_analysis->>'confidence')::integer,
    (p_analysis->>'model_total_lambda')::numeric,
    coalesce(p_analysis->'predicted_scores', '[]'::jsonb),
    p_analysis->>'notes',
    v_analysis_source
  )
  on conflict (analysis_key) do nothing
  returning id into v_analysis_id;

  if v_analysis_id is null then
    select id, match_id into v_analysis_id, v_match_id
    from public.plus8_analyses where analysis_key = p_analysis_key;
    select coalesce(array_agg(id order by created_at, id), array[]::uuid[])
      into v_recommendation_ids
    from public.plus8_recommendations where analysis_id = v_analysis_id;
  else
    v_inserted := true;
    for v_recommendation in select value from jsonb_array_elements(p_recommendations)
    loop
      insert into public.plus8_recommendations (
        analysis_id, match_id, market_type, side, line, odds, grade, units,
        is_primary, is_official, model_probability, market_probability,
        edge_pp, fair_odds, ev, confidence
      ) values (
        v_analysis_id, v_match_id, v_recommendation->>'market_type',
        v_recommendation->>'side', (v_recommendation->>'line')::numeric,
        (v_recommendation->>'odds')::numeric,
        coalesce(v_recommendation->>'grade', 'NONE'),
        coalesce((v_recommendation->>'units')::numeric, 0),
        coalesce((v_recommendation->>'is_primary')::boolean, false),
        coalesce((v_recommendation->>'is_official')::boolean, true),
        (v_recommendation->>'model_probability')::numeric,
        (v_recommendation->>'market_probability')::numeric,
        (v_recommendation->>'edge_pp')::numeric,
        (v_recommendation->>'fair_odds')::numeric,
        (v_recommendation->>'ev')::numeric,
        (v_recommendation->>'confidence')::integer
      ) returning id into v_recommendation_id;
      v_recommendation_ids := array_append(v_recommendation_ids, v_recommendation_id);
    end loop;
  end if;

  return jsonb_build_object(
    'success', true,
    'match_id', v_match_id,
    'analysis_id', v_analysis_id,
    'analysis_source', v_analysis_source,
    'recommendation_ids', to_jsonb(v_recommendation_ids),
    'idempotent_replay', not v_inserted
  );
end;
$function$;

create or replace view public.plus8_final_pre_match_analysis
with (security_invoker=true) as
select distinct on (a.match_id)
  a.id,
  a.match_id,
  a.analysis_key,
  a.model_name,
  a.model_version,
  a.analysis_type,
  a.analysis_time,
  a.is_valid,
  a.is_final_pre_match,
  a.data_completeness,
  a.confidence,
  a.model_total_lambda,
  a.predicted_scores,
  a.notes,
  a.created_at,
  a.analysis_source
from public.plus8_analyses a
join public.plus8_matches m on m.id = a.match_id
where a.analysis_type in ('pre_match','pre_match_review')
  and a.analysis_time < m.kickoff_time
  and a.is_valid
order by a.match_id, a.analysis_time desc, a.created_at desc, a.id desc;

create or replace view public.plus8_final_primary_recommendations
with (security_invoker=true) as
select
  r.id,
  r.analysis_id,
  r.match_id,
  r.market_type,
  r.side,
  r.line,
  r.odds,
  r.grade,
  r.units,
  r.is_primary,
  r.is_official,
  r.model_probability,
  r.market_probability,
  r.edge_pp,
  r.fair_odds,
  r.ev,
  r.confidence,
  r.created_at,
  a.model_name,
  a.model_version,
  a.analysis_time,
  a.analysis_source
from public.plus8_final_pre_match_analysis a
join public.plus8_recommendations r on r.analysis_id = a.id
where r.is_primary and r.is_official;

create or replace view public.plus8_pending_settlements
with (security_invoker=true) as
select
  m.id as match_id,
  m.match_key,
  m.kickoff_time,
  m.home_team,
  m.away_team,
  m.league_name,
  a.id as final_analysis_id,
  r.id as primary_total_recommendation_id,
  a.analysis_source
from public.plus8_matches m
join public.plus8_final_pre_match_analysis a on a.match_id = m.id
join public.plus8_recommendations r
  on r.analysis_id = a.id
 and r.market_type = 'total_goals'
 and r.is_primary
 and r.is_official
left join public.plus8_settlements s on s.match_id = m.id
where s.id is null
  and m.status not in ('cancelled','postponed')
  and m.kickoff_time >= now() - interval '24 hours'
  and m.kickoff_time <= now();

create or replace view public.plus8_settled_recommendations
with (security_invoker=true) as
select
  s.id as settlement_id,
  s.match_id,
  s.final_analysis_id,
  s.final_total_recommendation_id as recommendation_id,
  s.settled_at,
  a.model_name,
  a.model_version,
  m.league_name,
  m.league_country,
  m.kickoff_time,
  r.market_type,
  r.side,
  r.line,
  r.odds,
  r.grade,
  r.units,
  coalesce(r.confidence, a.confidence) as confidence,
  s.total_result as result,
  s.total_pnl_u as pnl_u,
  s.included_in_total_stats as included_in_stats,
  a.analysis_source
from public.plus8_settlements s
join public.plus8_matches m on m.id = s.match_id
left join public.plus8_analyses a on a.id = s.final_analysis_id
left join public.plus8_recommendations r on r.id = s.final_total_recommendation_id
where r.id is not null
union all
select
  s.id as settlement_id,
  s.match_id,
  s.final_analysis_id,
  s.final_handicap_recommendation_id as recommendation_id,
  s.settled_at,
  a.model_name,
  a.model_version,
  m.league_name,
  m.league_country,
  m.kickoff_time,
  r.market_type,
  r.side,
  r.line,
  r.odds,
  r.grade,
  r.units,
  coalesce(r.confidence, a.confidence) as confidence,
  s.handicap_result as result,
  s.handicap_pnl_u as pnl_u,
  s.included_in_handicap_stats as included_in_stats,
  a.analysis_source
from public.plus8_settlements s
join public.plus8_matches m on m.id = s.match_id
left join public.plus8_analyses a on a.id = s.final_analysis_id
left join public.plus8_recommendations r on r.id = s.final_handicap_recommendation_id
where r.id is not null;

create or replace view public.plus8_stats_by_source
with (security_invoker=true) as
select
  model_version,
  analysis_source,
  market_type,
  count(*)::integer as sample_count,
  count(*) filter (where result='full_win')::integer as full_win_count,
  count(*) filter (where result='half_win')::integer as half_win_count,
  count(*) filter (where result='push')::integer as push_count,
  count(*) filter (where result='half_loss')::integer as half_loss_count,
  count(*) filter (where result='full_loss')::integer as full_loss_count,
  (
    (count(*) filter (where result='full_win'))::numeric
    + 0.5 * (count(*) filter (where result='half_win'))::numeric
  ) / nullif(count(*) filter (where result in ('full_win','half_win','half_loss','full_loss')),0)::numeric
    as weighted_hit_rate,
  (count(*) filter (where result in ('full_win','half_win','push')))::numeric
    / nullif(count(*),0)::numeric as non_loss_rate,
  coalesce(sum(units),0)::numeric as total_risk_u,
  coalesce(sum(pnl_u),0)::numeric as total_pnl_u,
  coalesce(sum(pnl_u),0)::numeric / nullif(sum(units),0)::numeric as roi
from public.plus8_settled_recommendations
where included_in_stats
group by model_version, analysis_source, market_type;;
