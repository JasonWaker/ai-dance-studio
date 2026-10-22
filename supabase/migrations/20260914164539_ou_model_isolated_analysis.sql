-- Private research store for user-requested match analyses.
-- No foreign keys, grants, views, or writes to the football site's public tables.
create schema if not exists ou_model;
revoke all on schema ou_model from public, anon, authenticated;
grant usage on schema ou_model to service_role;

create table ou_model.fixtures (
  fixture_key text primary key,
  competition text not null,
  season text not null,
  kickoff_utc timestamptz not null,
  home_team text not null,
  away_team text not null,
  match_url text,
  created_at timestamptz not null default now(),
  constraint fixture_key_nonempty check (length(trim(fixture_key)) > 0),
  constraint distinct_teams check (home_team <> away_team)
);

create table ou_model.analyses (
  analysis_key text primary key,
  fixture_key text not null references ou_model.fixtures(fixture_key),
  analysis_type text not null check (analysis_type in ('pre_match', 'after_kickoff_no_live', 'post_match_replay')),
  published_at_utc timestamptz,
  imported_at_utc timestamptz not null default now(),
  model_name text not null,
  model_version text,
  summary text not null,
  data_quality text not null check (data_quality in ('verified_snapshot', 'mixed', 'incomplete')),
  source_refs jsonb not null default '[]'::jsonb check (jsonb_typeof(source_refs) = 'array'),
  evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(evidence) = 'object'),
  limitations text,
  constraint analysis_key_nonempty check (length(trim(analysis_key)) > 0)
);

create table ou_model.predictions (
  prediction_key text primary key,
  analysis_key text not null references ou_model.analyses(analysis_key),
  market text not null check (market in ('total_goals', 'match_result', 'correct_score')),
  line numeric(5,2),
  selection text not null,
  probability numeric(7,5) check (probability between 0 and 1),
  probability_meaning text,
  decimal_odds numeric(8,3) check (decimal_odds is null or decimal_odds > 1),
  decision text not null check (decision in ('forecast', 'weak_lean', 'no_bet')),
  rationale text,
  constraint total_goals_line check (
    (market = 'total_goals' and line is not null and line >= 0 and line * 4 = trunc(line * 4) and selection in ('over', 'under'))
    or (market <> 'total_goals' and line is null)
  )
);

create table ou_model.results (
  fixture_key text primary key references ou_model.fixtures(fixture_key),
  home_goals integer not null check (home_goals >= 0),
  away_goals integer not null check (away_goals >= 0),
  result_source text not null,
  recorded_at_utc timestamptz not null default now()
);

create index analyses_fixture_idx on ou_model.analyses(fixture_key, imported_at_utc);
create index predictions_analysis_idx on ou_model.predictions(analysis_key);
create index fixtures_kickoff_idx on ou_model.fixtures(kickoff_utc desc);

alter table ou_model.fixtures enable row level security;
alter table ou_model.analyses enable row level security;
alter table ou_model.predictions enable row level security;
alter table ou_model.results enable row level security;

revoke all on all tables in schema ou_model from public, anon, authenticated;
grant select, insert on ou_model.fixtures, ou_model.analyses, ou_model.predictions, ou_model.results to service_role;
grant update on ou_model.fixtures, ou_model.results to service_role;

-- Only the server-side service role can access this unexposed schema.
-- No anon/authenticated policies or grants are added. Website access needs a
-- separately reviewed API/view later; never embed a service key in the client.
;
