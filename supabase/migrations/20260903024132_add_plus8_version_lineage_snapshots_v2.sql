alter table public.plus8_recommendations
  add column if not exists model_name text,
  add column if not exists model_version text,
  add column if not exists analysis_source text;

alter table public.plus8_recommendations
  drop constraint if exists plus8_recommendations_analysis_source_check;
alter table public.plus8_recommendations
  add constraint plus8_recommendations_analysis_source_check
  check (analysis_source is null or analysis_source in ('system_scan','manual_analysis','legacy_unclassified'));

create index if not exists idx_plus8_recommendations_version_source_market
  on public.plus8_recommendations(model_version, analysis_source, market_type);

create or replace function public.plus8_fill_recommendation_model_snapshot()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
declare
  v_analysis public.plus8_analyses%rowtype;
begin
  select * into v_analysis from public.plus8_analyses where id = new.analysis_id;
  if not found then
    raise exception using errcode='23503', message='analysis_id not found for recommendation';
  end if;
  new.model_name := v_analysis.model_name;
  new.model_version := v_analysis.model_version;
  new.analysis_source := v_analysis.analysis_source;
  return new;
end;
$function$;

drop trigger if exists plus8_recommendations_fill_model_snapshot on public.plus8_recommendations;
create trigger plus8_recommendations_fill_model_snapshot
before insert on public.plus8_recommendations
for each row execute function public.plus8_fill_recommendation_model_snapshot();

alter table public.plus8_settlements
  add column if not exists model_name text,
  add column if not exists model_version text,
  add column if not exists analysis_source text;

alter table public.plus8_settlements
  drop constraint if exists plus8_settlements_analysis_source_check;
alter table public.plus8_settlements
  add constraint plus8_settlements_analysis_source_check
  check (analysis_source is null or analysis_source in ('system_scan','manual_analysis','legacy_unclassified'));

update public.plus8_settlements s
set model_name = a.model_name,
    model_version = a.model_version,
    analysis_source = a.analysis_source
from public.plus8_analyses a
where a.id = s.final_analysis_id
  and (s.model_name is null or s.model_version is null or s.analysis_source is null);

create index if not exists idx_plus8_settlements_version_source
  on public.plus8_settlements(model_version, analysis_source);

create or replace function public.plus8_fill_settlement_model_snapshot()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
declare
  v_analysis public.plus8_analyses%rowtype;
begin
  if new.final_analysis_id is not null then
    select * into v_analysis from public.plus8_analyses where id = new.final_analysis_id;
    if found then
      new.model_name := v_analysis.model_name;
      new.model_version := v_analysis.model_version;
      new.analysis_source := v_analysis.analysis_source;
    end if;
  end if;
  return new;
end;
$function$;

drop trigger if exists plus8_settlements_fill_model_snapshot on public.plus8_settlements;
create trigger plus8_settlements_fill_model_snapshot
before insert or update of final_analysis_id on public.plus8_settlements
for each row execute function public.plus8_fill_settlement_model_snapshot();

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
  v_model_name text;
  v_model_version text;
begin
  if jsonb_typeof(p_recommendations) <> 'array' then
    raise exception using errcode = '22023', message = 'recommendations must be an array';
  end if;

  v_analysis_source := coalesce(nullif(p_analysis->>'analysis_source',''), 'manual_analysis');
  if v_analysis_source not in ('system_scan','manual_analysis','legacy_unclassified') then
    raise exception using errcode = '22023', message = 'analysis_source must be system_scan, manual_analysis, or legacy_unclassified';
  end if;

  v_model_name := nullif(p_analysis->>'model_name','');
  v_model_version := nullif(p_analysis->>'model_version','');
  if v_model_name is null or v_model_version is null then
    raise exception using errcode = '22023', message = 'model_name and model_version are required';
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
    v_match_id, p_analysis_key, v_model_name, v_model_version,
    p_analysis->>'analysis_type', (p_analysis->>'analysis_time')::timestamptz,
    coalesce((p_analysis->>'is_valid')::boolean, true),
    (p_analysis->>'data_completeness')::integer,
    (p_analysis->>'confidence')::integer,
    (p_analysis->>'model_total_lambda')::numeric,
    coalesce(p_analysis->'predicted_scores', '[]'::jsonb),
    p_analysis->>'notes', v_analysis_source
  )
  on conflict (analysis_key) do nothing
  returning id into v_analysis_id;

  if v_analysis_id is null then
    select id, match_id, model_name, model_version, analysis_source
      into v_analysis_id, v_match_id, v_model_name, v_model_version, v_analysis_source
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
    'model_name', v_model_name,
    'model_version', v_model_version,
    'recommendation_ids', to_jsonb(v_recommendation_ids),
    'idempotent_replay', not v_inserted
  );
end;
$function$;

create or replace function public.plus8_settle_match(
  p_match_key text,
  p_home_score integer,
  p_away_score integer,
  p_result_source text
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_match public.plus8_matches%rowtype;
  v_analysis public.plus8_analyses%rowtype;
  v_total public.plus8_recommendations%rowtype;
  v_handicap public.plus8_recommendations%rowtype;
  v_total_result text := 'not_applicable';
  v_handicap_result text := 'not_applicable';
  v_total_pnl numeric := 0;
  v_handicap_pnl numeric := 0;
  v_include_total boolean := false;
  v_include_handicap boolean := false;
  v_settlement_id uuid;
  v_settled_at timestamptz;
  v_was_replay boolean := false;
begin
  if p_home_score < 0 or p_away_score < 0 then
    raise exception using errcode = '22023', message = 'Scores cannot be negative';
  end if;
  select * into v_match from public.plus8_matches where match_key = p_match_key for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Match not found';
  end if;

  select a.* into v_analysis
  from public.plus8_analyses a
  where a.match_id = v_match.id
    and a.analysis_type in ('pre_match', 'pre_match_review')
    and a.analysis_time < v_match.kickoff_time
    and a.is_valid
  order by a.analysis_time desc, a.created_at desc, a.id desc
  limit 1;

  if v_analysis.id is not null then
    select * into v_total from public.plus8_recommendations
    where analysis_id = v_analysis.id and market_type = 'total_goals' and is_primary and is_official limit 1;
    select * into v_handicap from public.plus8_recommendations
    where analysis_id = v_analysis.id and market_type = 'asian_handicap' and is_primary and is_official limit 1;
  end if;

  if v_total.id is not null then
    v_total_result := public.plus8_settle_total(v_total.side, v_total.line, p_home_score + p_away_score);
    v_include_total := v_total.units > 0 and v_total.grade <> 'NONE';
    if v_include_total then v_total_pnl := public.plus8_calculate_pnl(v_total_result, v_total.odds, v_total.units); end if;
  end if;

  if v_handicap.id is not null then
    v_handicap_result := public.plus8_settle_handicap(v_handicap.side, v_handicap.line, p_home_score, p_away_score);
    v_include_handicap := v_handicap.units > 0 and v_handicap.grade <> 'NONE';
    if v_include_handicap then v_handicap_pnl := public.plus8_calculate_pnl(v_handicap_result, v_handicap.odds, v_handicap.units); end if;
  end if;

  update public.plus8_matches set
    status='finished', home_score=p_home_score, away_score=p_away_score,
    result_confirmed=true, result_source=p_result_source
  where id=v_match.id;

  select id, settled_at,
    home_score=p_home_score and away_score=p_away_score
    and coalesce(final_analysis_id=v_analysis.id, final_analysis_id is null and v_analysis.id is null)
  into v_settlement_id, v_settled_at, v_was_replay
  from public.plus8_settlements where match_id=v_match.id;

  insert into public.plus8_settlements (
    match_id, final_analysis_id, final_total_recommendation_id,
    final_handicap_recommendation_id, home_score, away_score,
    total_result, handicap_result, total_pnl_u, handicap_pnl_u,
    included_in_total_stats, included_in_handicap_stats
  ) values (
    v_match.id, v_analysis.id, v_total.id, v_handicap.id,
    p_home_score, p_away_score, v_total_result, v_handicap_result,
    v_total_pnl, v_handicap_pnl, v_include_total, v_include_handicap
  )
  on conflict (match_id) do update set
    final_analysis_id=excluded.final_analysis_id,
    final_total_recommendation_id=excluded.final_total_recommendation_id,
    final_handicap_recommendation_id=excluded.final_handicap_recommendation_id,
    home_score=excluded.home_score,
    away_score=excluded.away_score,
    total_result=excluded.total_result,
    handicap_result=excluded.handicap_result,
    total_pnl_u=excluded.total_pnl_u,
    handicap_pnl_u=excluded.handicap_pnl_u,
    included_in_total_stats=excluded.included_in_total_stats,
    included_in_handicap_stats=excluded.included_in_handicap_stats
  returning id, settled_at into v_settlement_id, v_settled_at;

  perform public.plus8_refresh_daily_stats((v_settled_at at time zone 'Asia/Shanghai')::date);

  return jsonb_build_object(
    'success',true,
    'match_id',v_match.id,
    'settlement_id',v_settlement_id,
    'final_analysis_id',v_analysis.id,
    'model_name',v_analysis.model_name,
    'model_version',v_analysis.model_version,
    'analysis_source',v_analysis.analysis_source,
    'final_total_recommendation_id',v_total.id,
    'final_handicap_recommendation_id',v_handicap.id,
    'total_result',v_total_result,
    'handicap_result',v_handicap_result,
    'total_pnl_u',v_total_pnl,
    'handicap_pnl_u',v_handicap_pnl,
    'idempotent_replay',coalesce(v_was_replay,false)
  );
end;
$function$;

create or replace view public.plus8_pending_settlements as
select
  m.id as match_id,
  m.match_key,
  m.kickoff_time,
  m.home_team,
  m.away_team,
  m.league_name,
  a.id as final_analysis_id,
  r.id as primary_total_recommendation_id,
  a.analysis_source,
  a.model_name,
  a.model_version
from public.plus8_matches m
join public.plus8_final_pre_match_analysis a on a.match_id=m.id
join public.plus8_recommendations r
  on r.analysis_id=a.id and r.market_type='total_goals' and r.is_primary and r.is_official
left join public.plus8_settlements s on s.match_id=m.id
where s.id is null
  and m.status not in ('cancelled','postponed')
  and m.kickoff_time >= now()-interval '24 hours'
  and m.kickoff_time <= now();

create or replace view public.plus8_settled_recommendations as
select
  s.id as settlement_id, s.match_id, s.final_analysis_id,
  s.final_total_recommendation_id as recommendation_id, s.settled_at,
  coalesce(s.model_name,r.model_name,a.model_name) as model_name,
  coalesce(s.model_version,r.model_version,a.model_version) as model_version,
  m.league_name,m.league_country,m.kickoff_time,
  r.market_type,r.side,r.line,r.odds,r.grade,r.units,
  coalesce(r.confidence,a.confidence) as confidence,
  s.total_result as result,s.total_pnl_u as pnl_u,
  s.included_in_total_stats as included_in_stats,
  coalesce(s.analysis_source,r.analysis_source,a.analysis_source) as analysis_source
from public.plus8_settlements s
join public.plus8_matches m on m.id=s.match_id
left join public.plus8_analyses a on a.id=s.final_analysis_id
left join public.plus8_recommendations r on r.id=s.final_total_recommendation_id
where r.id is not null
union all
select
  s.id as settlement_id, s.match_id, s.final_analysis_id,
  s.final_handicap_recommendation_id as recommendation_id, s.settled_at,
  coalesce(s.model_name,r.model_name,a.model_name) as model_name,
  coalesce(s.model_version,r.model_version,a.model_version) as model_version,
  m.league_name,m.league_country,m.kickoff_time,
  r.market_type,r.side,r.line,r.odds,r.grade,r.units,
  coalesce(r.confidence,a.confidence) as confidence,
  s.handicap_result as result,s.handicap_pnl_u as pnl_u,
  s.included_in_handicap_stats as included_in_stats,
  coalesce(s.analysis_source,r.analysis_source,a.analysis_source) as analysis_source
from public.plus8_settlements s
join public.plus8_matches m on m.id=s.match_id
left join public.plus8_analyses a on a.id=s.final_analysis_id
left join public.plus8_recommendations r on r.id=s.final_handicap_recommendation_id
where r.id is not null;

create or replace view public.plus8_match_version_ledger as
select
  m.id as match_id,m.match_key,m.league_name,m.home_team,m.away_team,m.kickoff_time,
  a.id as analysis_id,a.analysis_time,a.analysis_type,a.analysis_source,
  a.model_name,a.model_version,a.is_valid
from public.plus8_matches m
join public.plus8_analyses a on a.match_id=m.id;

create or replace view public.plus8_version_comparison_stats as
select
  model_version,analysis_source,market_type,
  count(*) filter (where included_in_stats)::integer as betting_sample_count,
  count(*) filter (where included_in_stats and result='full_win')::integer as full_win_count,
  count(*) filter (where included_in_stats and result='half_win')::integer as half_win_count,
  count(*) filter (where included_in_stats and result='push')::integer as push_count,
  count(*) filter (where included_in_stats and result='half_loss')::integer as half_loss_count,
  count(*) filter (where included_in_stats and result='full_loss')::integer as full_loss_count,
  (count(*) filter (where included_in_stats and result='full_win')::numeric
   +0.5*count(*) filter (where included_in_stats and result='half_win')::numeric)
   /nullif(count(*) filter (where included_in_stats and result in ('full_win','half_win','half_loss','full_loss')),0)::numeric as weighted_hit_rate,
  coalesce(sum(units) filter (where included_in_stats),0::numeric) as total_risk_u,
  coalesce(sum(pnl_u) filter (where included_in_stats),0::numeric) as total_pnl_u,
  coalesce(sum(pnl_u) filter (where included_in_stats),0::numeric)
   /nullif(sum(units) filter (where included_in_stats),0::numeric) as roi,
  avg(confidence) filter (where included_in_stats) as avg_confidence
from public.plus8_settled_recommendations
group by model_version,analysis_source,market_type;;
