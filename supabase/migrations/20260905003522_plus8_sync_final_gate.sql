create or replace function public.plus8_sync_analysis(
  p_match jsonb,
  p_analysis jsonb,
  p_recommendations jsonb,
  p_analysis_key text
)
returns jsonb
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
  v_is_final_pre_match boolean;
  v_data_completeness integer;
  v_grade text;
  v_units numeric;
  v_base_ev numeric;
  v_post_ev numeric;
  v_hard_evidence_count integer;
  v_key_injuries_confirmed boolean;
begin
  if jsonb_typeof(p_recommendations) <> 'array' then
    raise exception using errcode='22023', message='recommendations must be an array';
  end if;

  v_analysis_source := coalesce(nullif(p_analysis->>'analysis_source',''),'manual_analysis');
  if v_analysis_source not in ('system_scan','manual_analysis','legacy_unclassified') then
    raise exception using errcode='22023', message='invalid analysis_source';
  end if;

  v_model_name := nullif(p_analysis->>'model_name','');
  v_model_version := nullif(p_analysis->>'model_version','');
  if v_model_name is null or v_model_version is null then
    raise exception using errcode='22023', message='model_name and model_version are required';
  end if;

  if lower(v_model_name)='plus8' then
    v_model_name := 'Plus8';
    v_model_version := regexp_replace(v_model_version,'^Plus8[[:space:]]+','','i');
  end if;

  v_is_final_pre_match := coalesce((p_analysis->>'is_final_pre_match')::boolean,false);
  v_data_completeness := (p_analysis->>'data_completeness')::integer;
  v_hard_evidence_count := coalesce((p_analysis->>'independent_hard_evidence_count')::integer,0);
  v_key_injuries_confirmed := coalesce((p_analysis->>'key_injuries_confirmed')::boolean,false);

  insert into public.plus8_matches(match_key,league_name,league_country,league_level,home_team,away_team,kickoff_time)
  values(
    p_match->>'match_key',p_match->>'league_name',p_match->>'league_country',p_match->>'league_level',
    p_match->>'home_team',p_match->>'away_team',(p_match->>'kickoff_time')::timestamptz
  )
  on conflict(match_key) do update set
    league_name=excluded.league_name,
    league_country=coalesce(excluded.league_country,plus8_matches.league_country),
    league_level=coalesce(excluded.league_level,plus8_matches.league_level),
    home_team=excluded.home_team,
    away_team=excluded.away_team,
    kickoff_time=excluded.kickoff_time
  returning id into v_match_id;

  insert into public.plus8_analyses(
    match_id,analysis_key,model_name,model_version,analysis_type,analysis_time,is_valid,
    is_final_pre_match,data_completeness,confidence,model_total_lambda,predicted_scores,notes,analysis_source
  ) values(
    v_match_id,p_analysis_key,v_model_name,v_model_version,p_analysis->>'analysis_type',
    (p_analysis->>'analysis_time')::timestamptz,coalesce((p_analysis->>'is_valid')::boolean,true),
    v_is_final_pre_match,v_data_completeness,(p_analysis->>'confidence')::integer,
    (p_analysis->>'model_total_lambda')::numeric,coalesce(p_analysis->'predicted_scores','[]'::jsonb),
    p_analysis->>'notes',v_analysis_source
  )
  on conflict(analysis_key) do nothing
  returning id into v_analysis_id;

  if v_analysis_id is null then
    select id,match_id,model_name,model_version,analysis_source
      into v_analysis_id,v_match_id,v_model_name,v_model_version,v_analysis_source
    from public.plus8_analyses where analysis_key=p_analysis_key;
    select coalesce(array_agg(id order by created_at,id),array[]::uuid[])
      into v_recommendation_ids
    from public.plus8_recommendations where analysis_id=v_analysis_id;
  else
    v_inserted := true;
    for v_recommendation in select value from jsonb_array_elements(p_recommendations)
    loop
      v_grade := coalesce(v_recommendation->>'grade','NONE');
      v_units := coalesce((v_recommendation->>'units')::numeric,0);
      v_post_ev := (v_recommendation->>'ev')::numeric;
      v_base_ev := nullif(v_recommendation->>'base_ev','')::numeric;

      if not v_is_final_pre_match and v_units>0 and v_grade in ('A','B','C') then
        v_grade := 'D';
        v_units := least(v_units,2);
      elsif not v_is_final_pre_match and v_units>2 then
        v_units := 2;
        if v_grade<>'NONE' then v_grade := 'D'; end if;
      end if;

      if v_base_ev is not null and v_base_ev<0 and v_post_ev>0 then
        if v_post_ev<0.06
           or coalesce(v_data_completeness,0)<92
           or not v_key_injuries_confirmed
           or v_hard_evidence_count<2 then
          v_grade := 'NONE';
          v_units := 0;
        end if;
      end if;

      insert into public.plus8_recommendations(
        analysis_id,match_id,market_type,side,line,odds,grade,units,is_primary,is_official,
        model_probability,market_probability,edge_pp,fair_odds,ev,confidence
      ) values(
        v_analysis_id,v_match_id,v_recommendation->>'market_type',v_recommendation->>'side',
        (v_recommendation->>'line')::numeric,(v_recommendation->>'odds')::numeric,v_grade,v_units,
        coalesce((v_recommendation->>'is_primary')::boolean,false),
        coalesce((v_recommendation->>'is_official')::boolean,true),
        (v_recommendation->>'model_probability')::numeric,(v_recommendation->>'market_probability')::numeric,
        (v_recommendation->>'edge_pp')::numeric,(v_recommendation->>'fair_odds')::numeric,v_post_ev,
        (v_recommendation->>'confidence')::integer
      ) returning id into v_recommendation_id;
      v_recommendation_ids := array_append(v_recommendation_ids,v_recommendation_id);
    end loop;
  end if;

  return jsonb_build_object(
    'success',true,'match_id',v_match_id,'analysis_id',v_analysis_id,
    'analysis_source',v_analysis_source,'model_name',v_model_name,'model_version',v_model_version,
    'is_final_pre_match',v_is_final_pre_match,'recommendation_ids',to_jsonb(v_recommendation_ids),
    'idempotent_replay',not v_inserted
  );
end;
$function$;;
