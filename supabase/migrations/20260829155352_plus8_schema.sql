begin;

create extension if not exists pgcrypto with schema extensions;

create or replace function public.plus8_set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.plus8_matches (
  id uuid primary key default gen_random_uuid(),
  match_key text not null unique,
  league_name text not null,
  league_country text,
  league_level text,
  home_team text not null,
  away_team text not null,
  kickoff_time timestamptz not null,
  status text not null default 'scheduled'
    check (status in ('scheduled', 'live', 'finished', 'cancelled', 'postponed')),
  home_score integer check (home_score >= 0),
  away_score integer check (away_score >= 0),
  total_goals integer generated always as (
    case when home_score is not null and away_score is not null
      then home_score + away_score
    end
  ) stored,
  result_confirmed boolean not null default false,
  result_source text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((home_score is null) = (away_score is null))
);

create table public.plus8_analyses (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.plus8_matches(id) on delete restrict,
  analysis_key text not null unique check (analysis_key ~ '^[0-9a-f]{64}$'),
  model_name text not null,
  model_version text not null,
  analysis_type text not null
    check (analysis_type in ('pre_match', 'pre_match_review', 'live')),
  analysis_time timestamptz not null,
  is_valid boolean not null default true,
  -- Kept for compatibility; the dynamic final-analysis view is authoritative.
  is_final_pre_match boolean not null default false,
  data_completeness integer check (data_completeness between 0 and 100),
  confidence integer check (confidence between 0 and 100),
  model_total_lambda numeric check (model_total_lambda >= 0),
  predicted_scores jsonb not null default '[]'::jsonb
    check (jsonb_typeof(predicted_scores) in ('array', 'object')),
  notes text,
  created_at timestamptz not null default now()
);

create table public.plus8_recommendations (
  id uuid primary key default gen_random_uuid(),
  analysis_id uuid not null references public.plus8_analyses(id) on delete restrict,
  match_id uuid not null references public.plus8_matches(id) on delete restrict,
  market_type text not null check (market_type in ('total_goals', 'asian_handicap')),
  side text not null check (
    (market_type = 'total_goals' and side in ('over', 'under')) or
    (market_type = 'asian_handicap' and side in ('home', 'away'))
  ),
  line numeric not null check (line * 4 = trunc(line * 4)),
  odds numeric not null check (odds >= 1),
  grade text not null default 'NONE' check (grade in ('A', 'B', 'C', 'D', 'NONE')),
  units numeric not null default 0 check (units >= 0),
  is_primary boolean not null default false,
  is_official boolean not null default true,
  model_probability numeric check (model_probability between 0 and 1),
  market_probability numeric check (market_probability between 0 and 1),
  edge_pp numeric,
  fair_odds numeric check (fair_odds is null or fair_odds >= 1),
  ev numeric,
  confidence integer check (confidence between 0 and 100),
  created_at timestamptz not null default now()
);

create unique index plus8_one_primary_per_analysis_market
  on public.plus8_recommendations (analysis_id, market_type)
  where is_primary;

create table public.plus8_settlements (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null unique references public.plus8_matches(id) on delete restrict,
  final_analysis_id uuid references public.plus8_analyses(id) on delete restrict,
  final_total_recommendation_id uuid references public.plus8_recommendations(id) on delete restrict,
  final_handicap_recommendation_id uuid references public.plus8_recommendations(id) on delete restrict,
  home_score integer not null check (home_score >= 0),
  away_score integer not null check (away_score >= 0),
  total_goals integer generated always as (home_score + away_score) stored,
  total_result text not null check (total_result in (
    'full_win', 'half_win', 'push', 'half_loss', 'full_loss', 'not_applicable'
  )),
  handicap_result text not null check (handicap_result in (
    'full_win', 'half_win', 'push', 'half_loss', 'full_loss', 'not_applicable'
  )),
  total_pnl_u numeric not null default 0,
  handicap_pnl_u numeric not null default 0,
  included_in_total_stats boolean not null default false,
  included_in_handicap_stats boolean not null default false,
  settled_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.plus8_daily_stats (
  id uuid primary key default gen_random_uuid(),
  stat_date date not null,
  model_version text not null,
  sample_count integer not null default 0,
  full_win_count integer not null default 0,
  half_win_count integer not null default 0,
  push_count integer not null default 0,
  half_loss_count integer not null default 0,
  full_loss_count integer not null default 0,
  strict_win_rate numeric,
  positive_result_rate numeric,
  asian_weighted_hit_rate numeric,
  total_risk_u numeric not null default 0,
  total_pnl_u numeric not null default 0,
  roi numeric,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (stat_date, model_version)
);

create index plus8_matches_kickoff_idx on public.plus8_matches (kickoff_time);
create index plus8_matches_status_idx on public.plus8_matches (status);
create index plus8_analyses_match_time_idx
  on public.plus8_analyses (match_id, analysis_time desc)
  where is_valid and analysis_type in ('pre_match', 'pre_match_review');
create index plus8_analyses_model_version_idx on public.plus8_analyses (model_version);
create index plus8_recommendations_match_market_idx
  on public.plus8_recommendations (match_id, market_type);
create index plus8_recommendations_analysis_idx
  on public.plus8_recommendations (analysis_id);
create index plus8_settlements_settled_at_idx on public.plus8_settlements (settled_at);

create trigger plus8_matches_updated_at
before update on public.plus8_matches
for each row execute function public.plus8_set_updated_at();

create trigger plus8_settlements_updated_at
before update on public.plus8_settlements
for each row execute function public.plus8_set_updated_at();

create trigger plus8_daily_stats_updated_at
before update on public.plus8_daily_stats
for each row execute function public.plus8_set_updated_at();

-- Historical analysis rows and recommendations are append-only, including for service_role.
create or replace function public.plus8_prevent_history_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception using
    errcode = '55000',
    message = format('%s is append-only; insert a new analysis instead', tg_table_name);
end;
$$;

create trigger plus8_analyses_append_only
before update or delete on public.plus8_analyses
for each row execute function public.plus8_prevent_history_mutation();

create trigger plus8_recommendations_append_only
before update or delete on public.plus8_recommendations
for each row execute function public.plus8_prevent_history_mutation();

create or replace view public.plus8_final_pre_match_analysis
with (security_invoker = true)
as
select distinct on (a.match_id)
  a.*
from public.plus8_analyses a
join public.plus8_matches m on m.id = a.match_id
where a.analysis_type in ('pre_match', 'pre_match_review')
  and a.analysis_time < m.kickoff_time
  and a.is_valid
order by a.match_id, a.analysis_time desc, a.created_at desc, a.id desc;

create or replace view public.plus8_final_primary_recommendations
with (security_invoker = true)
as
select
  r.*,
  a.model_name,
  a.model_version,
  a.analysis_time
from public.plus8_final_pre_match_analysis a
join public.plus8_recommendations r on r.analysis_id = a.id
where r.is_primary and r.is_official;

create or replace view public.plus8_settled_recommendations
with (security_invoker = true)
as
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
  s.included_in_total_stats as included_in_stats
from public.plus8_settlements s
join public.plus8_matches m on m.id = s.match_id
left join public.plus8_analyses a on a.id = s.final_analysis_id
left join public.plus8_recommendations r on r.id = s.final_total_recommendation_id
where r.id is not null
union all
select
  s.id,
  s.match_id,
  s.final_analysis_id,
  s.final_handicap_recommendation_id,
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
  coalesce(r.confidence, a.confidence),
  s.handicap_result,
  s.handicap_pnl_u,
  s.included_in_handicap_stats
from public.plus8_settlements s
join public.plus8_matches m on m.id = s.match_id
left join public.plus8_analyses a on a.id = s.final_analysis_id
left join public.plus8_recommendations r on r.id = s.final_handicap_recommendation_id
where r.id is not null;

create or replace view public.plus8_model_stats
with (security_invoker = true)
as
select
  model_version,
  count(*)::integer as sample_count,
  count(*) filter (where result = 'full_win')::integer as full_win_count,
  count(*) filter (where result = 'half_win')::integer as half_win_count,
  count(*) filter (where result = 'push')::integer as push_count,
  count(*) filter (where result = 'half_loss')::integer as half_loss_count,
  count(*) filter (where result = 'full_loss')::integer as full_loss_count,
  count(*) filter (where result = 'full_win')::numeric / nullif(count(*), 0) as strict_win_rate,
  count(*) filter (where result in ('full_win', 'half_win'))::numeric / nullif(count(*), 0)
    as positive_result_rate,
  (count(*) filter (where result = 'full_win') +
    0.5 * count(*) filter (where result = 'half_win'))::numeric /
    nullif(count(*) filter (where result in ('full_win', 'half_win', 'half_loss', 'full_loss')), 0)
    as asian_weighted_hit_rate,
  coalesce(sum(units), 0) as total_risk_u,
  coalesce(sum(pnl_u), 0) as total_pnl_u,
  coalesce(sum(pnl_u), 0) / nullif(sum(units), 0) as roi
from public.plus8_settled_recommendations
where included_in_stats
group by model_version;

create or replace view public.plus8_stats_by_grade
with (security_invoker = true)
as
with grades(grade) as (values ('A'::text), ('B'), ('C'), ('D'))
select
  g.grade,
  count(r.recommendation_id)::integer as sample_count,
  (count(r.recommendation_id) filter (where r.result = 'full_win') +
    0.5 * count(r.recommendation_id) filter (where r.result = 'half_win'))::numeric /
    nullif(count(r.recommendation_id) filter (
      where r.result in ('full_win', 'half_win', 'half_loss', 'full_loss')
    ), 0) as weighted_hit_rate,
  coalesce(sum(r.pnl_u), 0) / nullif(sum(r.units), 0) as roi,
  coalesce(sum(r.pnl_u), 0) as pnl
from grades g
left join public.plus8_settled_recommendations r
  on r.grade = g.grade and r.included_in_stats
group by g.grade
order by array_position(array['A', 'B', 'C', 'D'], g.grade);

create or replace view public.plus8_stats_by_market_line
with (security_invoker = true)
as
select
  market_type,
  side,
  line,
  initcap(side) || ' ' || line::text as market_line,
  count(*)::integer as sample_count,
  (count(*) filter (where result = 'full_win') +
    0.5 * count(*) filter (where result = 'half_win'))::numeric /
    nullif(count(*) filter (where result in ('full_win', 'half_win', 'half_loss', 'full_loss')), 0)
    as weighted_hit_rate,
  sum(pnl_u) / nullif(sum(units), 0) as roi,
  sum(pnl_u) as pnl
from public.plus8_settled_recommendations
where included_in_stats
group by market_type, side, line;

create or replace view public.plus8_stats_by_league
with (security_invoker = true)
as
select
  league_name,
  league_country,
  count(*)::integer as sample_count,
  (count(*) filter (where result = 'full_win') +
    0.5 * count(*) filter (where result = 'half_win'))::numeric /
    nullif(count(*) filter (where result in ('full_win', 'half_win', 'half_loss', 'full_loss')), 0)
    as weighted_hit_rate,
  sum(pnl_u) / nullif(sum(units), 0) as roi,
  sum(pnl_u) as pnl
from public.plus8_settled_recommendations
where included_in_stats
group by league_name, league_country;

create or replace view public.plus8_stats_by_confidence_bucket
with (security_invoker = true)
as
select
  case
    when confidence < 60 then '<60'
    when confidence between 60 and 69 then '60-69'
    when confidence between 70 and 74 then '70-74'
    when confidence between 75 and 79 then '75-79'
    when confidence between 80 and 84 then '80-84'
    else '85+'
  end as confidence_bucket,
  count(*)::integer as sample_count,
  (count(*) filter (where result = 'full_win') +
    0.5 * count(*) filter (where result = 'half_win'))::numeric /
    nullif(count(*) filter (where result in ('full_win', 'half_win', 'half_loss', 'full_loss')), 0)
    as weighted_hit_rate,
  sum(pnl_u) / nullif(sum(units), 0) as roi,
  sum(pnl_u) as pnl
from public.plus8_settled_recommendations
where included_in_stats and confidence is not null
group by 1;

create or replace view public.plus8_pending_settlements
with (security_invoker = true)
as
select
  m.id as match_id,
  m.match_key,
  m.kickoff_time,
  m.home_team,
  m.away_team,
  m.league_name,
  a.id as final_analysis_id,
  r.id as primary_total_recommendation_id
from public.plus8_matches m
join public.plus8_final_pre_match_analysis a on a.match_id = m.id
join public.plus8_recommendations r
  on r.analysis_id = a.id
  and r.market_type = 'total_goals'
  and r.is_primary
  and r.is_official
left join public.plus8_settlements s on s.match_id = m.id
where s.id is null
  and m.status not in ('cancelled', 'postponed')
  and m.kickoff_time >= now() - interval '24 hours'
  and m.kickoff_time <= now();

-- Convert a signed component margin to -1/loss, 0/push, or 1/win.
create or replace function public.plus8_component_outcome(p_margin numeric)
returns integer
language sql
immutable
strict
as $$
  select case when p_margin > 0 then 1 when p_margin < 0 then -1 else 0 end;
$$;

create or replace function public.plus8_combine_component_outcomes(p_first integer, p_second integer)
returns text
language plpgsql
immutable
strict
as $$
begin
  if p_first not between -1 and 1 or p_second not between -1 and 1 then
    raise exception 'Invalid component outcome';
  end if;
  if p_first = 1 and p_second = 1 then return 'full_win'; end if;
  if p_first = -1 and p_second = -1 then return 'full_loss'; end if;
  if p_first = 0 and p_second = 0 then return 'push'; end if;
  if (p_first = 1 and p_second = 0) or (p_first = 0 and p_second = 1) then
    return 'half_win';
  end if;
  if (p_first = -1 and p_second = 0) or (p_first = 0 and p_second = -1) then
    return 'half_loss';
  end if;
  raise exception 'Inconsistent split outcomes: %, %', p_first, p_second;
end;
$$;

create or replace function public.plus8_settle_total(p_side text, p_line numeric, p_total_goals integer)
returns text
language plpgsql
immutable
strict
as $$
declare
  v_lower numeric;
  v_upper numeric;
  v_direction integer;
begin
  if p_side not in ('over', 'under') then raise exception 'Invalid total side: %', p_side; end if;
  if p_total_goals < 0 then raise exception 'Total goals cannot be negative'; end if;
  if p_line * 4 <> trunc(p_line * 4) then raise exception 'Line must use 0.25 increments'; end if;
  v_lower := floor(p_line * 2) / 2;
  v_upper := ceil(p_line * 2) / 2;
  v_direction := case when p_side = 'over' then 1 else -1 end;
  return public.plus8_combine_component_outcomes(
    public.plus8_component_outcome(v_direction * (p_total_goals - v_lower)),
    public.plus8_component_outcome(v_direction * (p_total_goals - v_upper))
  );
end;
$$;

create or replace function public.plus8_settle_handicap(
  p_side text,
  p_line numeric,
  p_home_score integer,
  p_away_score integer
)
returns text
language plpgsql
immutable
strict
as $$
declare
  v_lower numeric;
  v_upper numeric;
  v_goal_difference integer;
begin
  if p_side not in ('home', 'away') then raise exception 'Invalid handicap side: %', p_side; end if;
  if p_home_score < 0 or p_away_score < 0 then raise exception 'Scores cannot be negative'; end if;
  if p_line * 4 <> trunc(p_line * 4) then raise exception 'Line must use 0.25 increments'; end if;
  v_goal_difference := case
    when p_side = 'home' then p_home_score - p_away_score
    else p_away_score - p_home_score
  end;
  v_lower := floor(p_line * 2) / 2;
  v_upper := ceil(p_line * 2) / 2;
  return public.plus8_combine_component_outcomes(
    public.plus8_component_outcome(v_goal_difference + v_lower),
    public.plus8_component_outcome(v_goal_difference + v_upper)
  );
end;
$$;

create or replace function public.plus8_calculate_pnl(p_result text, p_odds numeric, p_units numeric)
returns numeric
language sql
immutable
strict
as $$
  select case p_result
    when 'full_win' then p_units * (p_odds - 1)
    when 'half_win' then p_units * 0.5 * (p_odds - 1)
    when 'push' then 0
    when 'half_loss' then -p_units * 0.5
    when 'full_loss' then -p_units
    when 'not_applicable' then 0
    else null
  end;
$$;

create or replace function public.plus8_sync_analysis(
  p_match jsonb,
  p_analysis jsonb,
  p_recommendations jsonb,
  p_analysis_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_match_id uuid;
  v_analysis_id uuid;
  v_recommendation_ids uuid[] := array[]::uuid[];
  v_recommendation jsonb;
  v_recommendation_id uuid;
  v_inserted boolean := false;
begin
  if jsonb_typeof(p_recommendations) <> 'array' then
    raise exception using errcode = '22023', message = 'recommendations must be an array';
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
    model_total_lambda, predicted_scores, notes
  ) values (
    v_match_id, p_analysis_key, p_analysis->>'model_name', p_analysis->>'model_version',
    p_analysis->>'analysis_type', (p_analysis->>'analysis_time')::timestamptz,
    coalesce((p_analysis->>'is_valid')::boolean, true),
    (p_analysis->>'data_completeness')::integer,
    (p_analysis->>'confidence')::integer,
    (p_analysis->>'model_total_lambda')::numeric,
    coalesce(p_analysis->'predicted_scores', '[]'::jsonb),
    p_analysis->>'notes'
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
    'recommendation_ids', to_jsonb(v_recommendation_ids),
    'idempotent_replay', not v_inserted
  );
end;
$$;

create or replace function public.plus8_refresh_daily_stats(p_stat_date date)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.plus8_daily_stats where stat_date = p_stat_date;
  insert into public.plus8_daily_stats (
    stat_date, model_version, sample_count, full_win_count, half_win_count,
    push_count, half_loss_count, full_loss_count, strict_win_rate,
    positive_result_rate, asian_weighted_hit_rate, total_risk_u, total_pnl_u, roi
  )
  select
    p_stat_date,
    model_version,
    count(*)::integer,
    count(*) filter (where result = 'full_win')::integer,
    count(*) filter (where result = 'half_win')::integer,
    count(*) filter (where result = 'push')::integer,
    count(*) filter (where result = 'half_loss')::integer,
    count(*) filter (where result = 'full_loss')::integer,
    count(*) filter (where result = 'full_win')::numeric / nullif(count(*), 0),
    count(*) filter (where result in ('full_win', 'half_win'))::numeric / nullif(count(*), 0),
    (count(*) filter (where result = 'full_win') +
      0.5 * count(*) filter (where result = 'half_win'))::numeric /
      nullif(count(*) filter (where result in ('full_win', 'half_win', 'half_loss', 'full_loss')), 0),
    coalesce(sum(units), 0),
    coalesce(sum(pnl_u), 0),
    coalesce(sum(pnl_u), 0) / nullif(sum(units), 0)
  from public.plus8_settled_recommendations
  where included_in_stats
    and (settled_at at time zone 'Asia/Shanghai')::date = p_stat_date
  group by model_version;
end;
$$;

create or replace function public.plus8_settle_match(
  p_match_key text,
  p_home_score integer,
  p_away_score integer,
  p_result_source text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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
    where analysis_id = v_analysis.id and market_type = 'total_goals'
      and is_primary and is_official limit 1;
    select * into v_handicap from public.plus8_recommendations
    where analysis_id = v_analysis.id and market_type = 'asian_handicap'
      and is_primary and is_official limit 1;
  end if;

  if v_total.id is not null then
    v_total_result := public.plus8_settle_total(v_total.side, v_total.line, p_home_score + p_away_score);
    v_include_total := v_total.units > 0 and v_total.grade <> 'NONE';
    if v_include_total then
      v_total_pnl := public.plus8_calculate_pnl(v_total_result, v_total.odds, v_total.units);
    end if;
  end if;
  if v_handicap.id is not null then
    v_handicap_result := public.plus8_settle_handicap(
      v_handicap.side, v_handicap.line, p_home_score, p_away_score
    );
    v_include_handicap := v_handicap.units > 0 and v_handicap.grade <> 'NONE';
    if v_include_handicap then
      v_handicap_pnl := public.plus8_calculate_pnl(v_handicap_result, v_handicap.odds, v_handicap.units);
    end if;
  end if;

  update public.plus8_matches set
    status = 'finished', home_score = p_home_score, away_score = p_away_score,
    result_confirmed = true, result_source = p_result_source
  where id = v_match.id;

  select id, settled_at,
    home_score = p_home_score and away_score = p_away_score
    and coalesce(final_analysis_id = v_analysis.id, final_analysis_id is null and v_analysis.id is null)
  into v_settlement_id, v_settled_at, v_was_replay
  from public.plus8_settlements where match_id = v_match.id;

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
    final_analysis_id = excluded.final_analysis_id,
    final_total_recommendation_id = excluded.final_total_recommendation_id,
    final_handicap_recommendation_id = excluded.final_handicap_recommendation_id,
    home_score = excluded.home_score,
    away_score = excluded.away_score,
    total_result = excluded.total_result,
    handicap_result = excluded.handicap_result,
    total_pnl_u = excluded.total_pnl_u,
    handicap_pnl_u = excluded.handicap_pnl_u,
    included_in_total_stats = excluded.included_in_total_stats,
    included_in_handicap_stats = excluded.included_in_handicap_stats
  returning id, settled_at into v_settlement_id, v_settled_at;

  perform public.plus8_refresh_daily_stats((v_settled_at at time zone 'Asia/Shanghai')::date);

  return jsonb_build_object(
    'success', true,
    'match_id', v_match.id,
    'settlement_id', v_settlement_id,
    'final_analysis_id', v_analysis.id,
    'final_total_recommendation_id', v_total.id,
    'final_handicap_recommendation_id', v_handicap.id,
    'total_result', v_total_result,
    'handicap_result', v_handicap_result,
    'total_pnl_u', v_total_pnl,
    'handicap_pnl_u', v_handicap_pnl,
    'idempotent_replay', coalesce(v_was_replay, false)
  );
end;
$$;

alter table public.plus8_matches enable row level security;
alter table public.plus8_analyses enable row level security;
alter table public.plus8_recommendations enable row level security;
alter table public.plus8_settlements enable row level security;
alter table public.plus8_daily_stats enable row level security;

create policy plus8_matches_public_read on public.plus8_matches for select to anon, authenticated using (true);
create policy plus8_analyses_public_read on public.plus8_analyses for select to anon, authenticated using (true);
create policy plus8_recommendations_public_read on public.plus8_recommendations for select to anon, authenticated using (true);
create policy plus8_settlements_public_read on public.plus8_settlements for select to anon, authenticated using (true);
create policy plus8_daily_stats_public_read on public.plus8_daily_stats for select to anon, authenticated using (true);

revoke all on public.plus8_matches, public.plus8_analyses,
  public.plus8_recommendations, public.plus8_settlements,
  public.plus8_daily_stats, public.plus8_final_pre_match_analysis,
  public.plus8_final_primary_recommendations,
  public.plus8_settled_recommendations, public.plus8_model_stats,
  public.plus8_stats_by_grade, public.plus8_stats_by_market_line,
  public.plus8_stats_by_league, public.plus8_stats_by_confidence_bucket,
  public.plus8_pending_settlements from anon, authenticated;
grant select on public.plus8_matches, public.plus8_analyses, public.plus8_recommendations,
  public.plus8_settlements, public.plus8_daily_stats,
  public.plus8_final_pre_match_analysis, public.plus8_final_primary_recommendations,
  public.plus8_settled_recommendations, public.plus8_model_stats,
  public.plus8_stats_by_grade, public.plus8_stats_by_market_line,
  public.plus8_stats_by_league, public.plus8_stats_by_confidence_bucket,
  public.plus8_pending_settlements to anon, authenticated;

revoke execute on function public.plus8_sync_analysis(jsonb, jsonb, jsonb, text) from public, anon, authenticated;
revoke execute on function public.plus8_settle_match(text, integer, integer, text) from public, anon, authenticated;
revoke execute on function public.plus8_refresh_daily_stats(date) from public, anon, authenticated;
grant execute on function public.plus8_sync_analysis(jsonb, jsonb, jsonb, text) to service_role;
grant execute on function public.plus8_settle_match(text, integer, integer, text) to service_role;
grant execute on function public.plus8_refresh_daily_stats(date) to service_role;

commit;
;
