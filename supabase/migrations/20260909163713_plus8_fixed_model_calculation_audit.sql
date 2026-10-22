-- Additive only: preserve all historical versions, recommendations and locked settlements.
alter table public.plus8_analyses
  add column if not exists analysis_json jsonb,
  add column if not exists implementation_revision text,
  add column if not exists calculation_checksum text,
  add column if not exists lambda_home numeric generated always as ((analysis_json->>'lambda_home')::numeric) stored,
  add column if not exists lambda_away numeric generated always as ((analysis_json->>'lambda_away')::numeric) stored;
alter table public.plus8_recommendations
  add column if not exists outcome_probabilities jsonb,
  add column if not exists probability_semantics text,
  add column if not exists execution_reason text;

CREATE OR REPLACE FUNCTION public.plus8_sync_analysis(p_match jsonb, p_analysis jsonb, p_recommendations jsonb, p_analysis_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
  if v_analysis_source = 'manual' then v_analysis_source := 'manual_analysis'; end if;
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

  if v_model_name <> 'Plus8' or v_model_version <> 'v8.2026.08.25.01' then
    raise exception using errcode='22023', message='New analyses require Plus8 v8.2026.08.25.01; historical rows are unchanged';
  end if;
  if p_analysis ? 'analysis_json' and p_analysis->'analysis_json'->>'model_version' is distinct from v_model_version then
    raise exception 'analysis_json model version mismatch';
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
    is_final_pre_match,data_completeness,confidence,model_total_lambda,predicted_scores,notes,analysis_source,analysis_json,implementation_revision,calculation_checksum
  ) values(
    v_match_id,p_analysis_key,v_model_name,v_model_version,p_analysis->>'analysis_type',
    (p_analysis->>'analysis_time')::timestamptz,coalesce((p_analysis->>'is_valid')::boolean,true),
    v_is_final_pre_match,v_data_completeness,(p_analysis->>'confidence')::integer,
    (p_analysis->>'model_total_lambda')::numeric,coalesce(p_analysis->'predicted_scores','[]'::jsonb),
    p_analysis->>'notes',v_analysis_source,p_analysis->'analysis_json',p_analysis->>'implementation_revision',p_analysis->>'calculation_checksum'
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
        model_probability,market_probability,edge_pp,fair_odds,ev,confidence,outcome_probabilities,probability_semantics,execution_reason
      ) values(
        v_analysis_id,v_match_id,v_recommendation->>'market_type',v_recommendation->>'side',
        (v_recommendation->>'line')::numeric,(v_recommendation->>'odds')::numeric,v_grade,v_units,
        coalesce((v_recommendation->>'is_primary')::boolean,false),
        coalesce((v_recommendation->>'is_official')::boolean,true),
        (v_recommendation->>'model_probability')::numeric,(v_recommendation->>'market_probability')::numeric,
        (v_recommendation->>'edge_pp')::numeric,(v_recommendation->>'fair_odds')::numeric,v_post_ev,
        (v_recommendation->>'confidence')::integer,v_recommendation->'outcome_probabilities',v_recommendation->>'probability_semantics',v_recommendation->>'execution_reason'
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
$function$
;

-- Validate new recommendations at the database boundary, including non-dashboard writers.
create or replace function public.plus8_validate_new_recommendation()
returns trigger language plpgsql security invoker set search_path=public as $guard$
declare
  a public.plus8_analyses%rowtype;
  m public.plus8_matches%rowtype;
  weekday integer;
  w numeric; l numeric; mass numeric; expected numeric;
begin
  select * into strict a from public.plus8_analyses where id=new.analysis_id;
  select * into strict m from public.plus8_matches where id=new.match_id;
  if a.match_id<>new.match_id then raise exception 'analysis/match mismatch'; end if;
  if a.model_name <> 'Plus8' or a.model_version <> 'v8.2026.08.25.01' then raise exception 'new recommendation version mismatch'; end if;
  weekday := extract(isodow from m.kickoff_time at time zone 'Asia/Shanghai');
  if new.units>0 and weekday between 1 and 4 and m.league_name not in
    ('英超','西甲','意甲','德甲','法甲','欧冠','欧联','欧协联','English Premier League','Spanish La Liga','Italian Serie A',
     'German Bundesliga','French Ligue 1','UEFA Champions League','UEFA Europa League','UEFA Conference League') then
    raise exception '周一至周四非白名单赛事必须0U';
  end if;
  if new.units>0 and (new.ev is null or new.ev<=0 or new.odds<=1) then raise exception 'formal stake requires positive EV and decimal odds'; end if;
  if new.units>0 and new.units<>(case new.grade when 'A' then 5 when 'B' then 4 when 'C' then 3 when 'D' then 2 else 0 end) then
    raise exception 'grade/stake mismatch: A5 B4 C3 D2 NONE0';
  end if;
  if new.units>0 and a.analysis_time>=m.kickoff_time and a.analysis_type<>'live' then raise exception 'prematch analysis cannot follow kickoff'; end if;
  if new.edge_pp is not null and new.model_probability is not null and new.market_probability is not null and
     abs(new.edge_pp-(new.model_probability-new.market_probability))>0.0001 then raise exception 'edge_pp must store probability difference in 0..1 scale'; end if;
  if new.outcome_probabilities is not null then
    if not (new.outcome_probabilities ?& array['full_win','half_win','push','half_loss','full_loss']) then raise exception 'five outcome probabilities required'; end if;
    if (select count(*) from jsonb_each(new.outcome_probabilities))<>5 then raise exception 'exactly five outcomes required'; end if;
    if exists(select 1 from jsonb_each_text(new.outcome_probabilities) p where p.value is null or p.value::numeric<0 or p.value::numeric>1) then raise exception 'invalid outcome probability'; end if;
    select sum(value::numeric) into mass from jsonb_each_text(new.outcome_probabilities);
    if abs(mass-1)>0.000001 then raise exception 'probability mass must sum to one'; end if;
    w := (new.outcome_probabilities->>'full_win')::numeric+0.5*(new.outcome_probabilities->>'half_win')::numeric;
    l := (new.outcome_probabilities->>'full_loss')::numeric+0.5*(new.outcome_probabilities->>'half_loss')::numeric;
    expected := w*(new.odds-1)-l;
    if new.ev is null or abs(new.ev-expected)>0.00001 then raise exception 'Asian EV inconsistent with outcome distribution'; end if;
    if w>0 and (new.fair_odds is null or abs(new.fair_odds-(1+l/w))>0.0001) then raise exception 'Asian fair odds inconsistent'; end if;
    if w+l>0 and (new.model_probability is null or abs(new.model_probability-w/(w+l))>0.00001) then raise exception 'effective probability inconsistent'; end if;
  end if;
  return new;
end;
$guard$;
revoke all on function public.plus8_validate_new_recommendation() from public,anon,authenticated;
drop trigger if exists plus8_validate_new_recommendation on public.plus8_recommendations;
create trigger plus8_validate_new_recommendation before insert on public.plus8_recommendations
for each row execute function public.plus8_validate_new_recommendation();

create or replace view public.plus8_replay_audit with (security_invoker=true) as
select a.id analysis_id,a.match_id,a.model_version,a.analysis_source,a.implementation_revision,a.calculation_checksum,
  a.analysis_time,a.created_at,m.kickoff_time,
  a.created_at < m.kickoff_time as inserted_before_kickoff,
  a.analysis_time < m.kickoff_time as timestamp_before_kickoff,
  a.analysis_json is not null as has_input_snapshot,
  (a.created_at < m.kickoff_time and a.analysis_time < m.kickoff_time and a.analysis_json is not null
   and a.calculation_checksum is not null and a.analysis_type in ('pre_match','pre_match_review')) as replay_candidate
from public.plus8_analyses a join public.plus8_matches m on m.id=a.match_id;
grant select on public.plus8_replay_audit to service_role;
revoke all on public.plus8_replay_audit from anon,authenticated;

create or replace function public.plus8_validate_new_analysis()
returns trigger language plpgsql security invoker set search_path=public as $analysis_guard$
begin
  if new.model_name <> 'Plus8' or new.model_version <> 'v8.2026.08.25.01' then
    raise exception 'New analyses require Plus8 v8.2026.08.25.01';
  end if;
  if new.analysis_source='manual' then new.analysis_source:='manual_analysis'; end if;
  if new.analysis_source not in ('manual_analysis','system_scan') then raise exception 'source must be manual or system_scan'; end if;
  if new.analysis_json is not null then
    if new.analysis_json->>'model_version' is distinct from new.model_version then raise exception 'calculation version mismatch'; end if;
    if new.analysis_json->'input_snapshot'->>'demo_only' = 'true' then raise exception 'demo input cannot be saved'; end if;
    if new.calculation_checksum is null or new.calculation_checksum !~ '^[a-f0-9]{64}$' then raise exception 'calculation checksum required'; end if;
    if new.implementation_revision is null then raise exception 'implementation revision required'; end if;
  end if;
  return new;
end;
$analysis_guard$;
revoke all on function public.plus8_validate_new_analysis() from public,anon,authenticated;
create trigger plus8_validate_new_analysis before insert on public.plus8_analyses
for each row execute function public.plus8_validate_new_analysis();
;
