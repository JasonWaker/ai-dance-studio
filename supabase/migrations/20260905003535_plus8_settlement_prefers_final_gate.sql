create or replace function public.plus8_settle_match(
  p_match_key text,
  p_home_score integer,
  p_away_score integer,
  p_result_source text
)
returns jsonb
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
  if p_home_score<0 or p_away_score<0 then
    raise exception using errcode='22023', message='Scores cannot be negative';
  end if;

  select * into v_match
  from public.plus8_matches
  where match_key=p_match_key
  for update;
  if not found then
    raise exception using errcode='P0002', message='Match not found';
  end if;

  select a.* into v_analysis
  from public.plus8_analyses a
  where a.match_id=v_match.id
    and a.analysis_type in ('pre_match','pre_match_review')
    and a.analysis_time<v_match.kickoff_time
    and a.is_valid
  order by a.is_final_pre_match desc,a.analysis_time desc,a.created_at desc,a.id desc
  limit 1;

  if v_analysis.id is not null then
    select * into v_total from public.plus8_recommendations
    where analysis_id=v_analysis.id and market_type='total_goals' and is_primary and is_official limit 1;
    select * into v_handicap from public.plus8_recommendations
    where analysis_id=v_analysis.id and market_type='asian_handicap' and is_primary and is_official limit 1;
  end if;

  if v_total.id is not null then
    v_total_result := public.plus8_settle_total(v_total.side,v_total.line,p_home_score+p_away_score);
    v_include_total := v_total.units>0 and v_total.grade<>'NONE';
    if v_include_total then v_total_pnl := public.plus8_calculate_pnl(v_total_result,v_total.odds,v_total.units); end if;
  end if;

  if v_handicap.id is not null then
    v_handicap_result := public.plus8_settle_handicap(v_handicap.side,v_handicap.line,p_home_score,p_away_score);
    v_include_handicap := v_handicap.units>0 and v_handicap.grade<>'NONE';
    if v_include_handicap then v_handicap_pnl := public.plus8_calculate_pnl(v_handicap_result,v_handicap.odds,v_handicap.units); end if;
  end if;

  update public.plus8_matches set
    status='finished',home_score=p_home_score,away_score=p_away_score,
    result_confirmed=true,result_source=p_result_source
  where id=v_match.id;

  select id,settled_at,
    home_score=p_home_score and away_score=p_away_score
    and coalesce(final_analysis_id=v_analysis.id,final_analysis_id is null and v_analysis.id is null)
  into v_settlement_id,v_settled_at,v_was_replay
  from public.plus8_settlements where match_id=v_match.id;

  insert into public.plus8_settlements(
    match_id,final_analysis_id,final_total_recommendation_id,final_handicap_recommendation_id,
    home_score,away_score,total_result,handicap_result,total_pnl_u,handicap_pnl_u,
    included_in_total_stats,included_in_handicap_stats
  ) values(
    v_match.id,v_analysis.id,v_total.id,v_handicap.id,p_home_score,p_away_score,
    v_total_result,v_handicap_result,v_total_pnl,v_handicap_pnl,v_include_total,v_include_handicap
  )
  on conflict(match_id) do update set
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
  returning id,settled_at into v_settlement_id,v_settled_at;

  perform public.plus8_refresh_daily_stats((v_settled_at at time zone 'Asia/Shanghai')::date);

  return jsonb_build_object(
    'success',true,'match_id',v_match.id,'settlement_id',v_settlement_id,
    'final_analysis_id',v_analysis.id,'final_gate_passed',coalesce(v_analysis.is_final_pre_match,false),
    'model_name',v_analysis.model_name,'model_version',v_analysis.model_version,
    'analysis_source',v_analysis.analysis_source,'final_total_recommendation_id',v_total.id,
    'final_handicap_recommendation_id',v_handicap.id,'total_result',v_total_result,
    'handicap_result',v_handicap_result,'total_pnl_u',v_total_pnl,'handicap_pnl_u',v_handicap_pnl,
    'idempotent_replay',coalesce(v_was_replay,false)
  );
end;
$function$;;
