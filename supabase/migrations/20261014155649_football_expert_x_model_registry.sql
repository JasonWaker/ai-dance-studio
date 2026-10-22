-- Private champion/challenger registry and immutable post-match learning log.
-- This extends ou_model only; it does not write to the football website's public tables.
create table ou_model.model_versions (
  model_slug text not null,
  version text not null,
  display_name text not null,
  status text not null check (status in ('challenger', 'champion', 'retired')),
  parent_version text,
  config jsonb not null check (jsonb_typeof(config) = 'object'),
  validation_metrics jsonb not null default '{}'::jsonb check (jsonb_typeof(validation_metrics) = 'object'),
  created_at_utc timestamptz not null default now(),
  promoted_at_utc timestamptz,
  notes text,
  primary key (model_slug, version),
  constraint model_version_nonempty check (length(trim(model_slug)) > 0 and length(trim(version)) > 0),
  constraint promotion_time_consistent check (status = 'champion' or promoted_at_utc is null)
);

create unique index model_versions_one_champion_idx
  on ou_model.model_versions(model_slug)
  where status = 'champion';

create table ou_model.post_match_reviews (
  review_key text primary key,
  fixture_key text not null references ou_model.fixtures(fixture_key),
  analysis_key text references ou_model.analyses(analysis_key),
  model_slug text not null,
  model_version text not null,
  feature_snapshot_sha256 text not null,
  reviewed_at_utc timestamptz not null default now(),
  result_source text not null,
  primary_settlement text not null check (primary_settlement in ('win', 'half_win', 'push', 'half_loss', 'loss', 'mixed')),
  market_reviews jsonb not null check (jsonb_typeof(market_reviews) = 'array'),
  error_tags jsonb not null default '[]'::jsonb check (jsonb_typeof(error_tags) = 'array'),
  learning_note text,
  candidate_change jsonb check (candidate_change is null or jsonb_typeof(candidate_change) = 'object'),
  created_at_utc timestamptz not null default now(),
  foreign key (model_slug, model_version) references ou_model.model_versions(model_slug, version),
  constraint review_key_nonempty check (length(trim(review_key)) > 0),
  constraint feature_hash_format check (feature_snapshot_sha256 ~ '^[0-9a-f]{64}$')
);

create index post_match_reviews_fixture_idx
  on ou_model.post_match_reviews(fixture_key, reviewed_at_utc desc);
create index post_match_reviews_model_idx
  on ou_model.post_match_reviews(model_slug, model_version, reviewed_at_utc desc);

alter table ou_model.model_versions enable row level security;
alter table ou_model.post_match_reviews enable row level security;

revoke all on ou_model.model_versions, ou_model.post_match_reviews from public, anon, authenticated;
grant select, insert, update on ou_model.model_versions to service_role;
grant select, insert on ou_model.post_match_reviews to service_role;

insert into ou_model.model_versions (
  model_slug, version, display_name, status, config, notes
) values (
  'football-expert-x',
  '1.0.0',
  '足球专家 X 模型',
  'challenger',
  '{"market_prior_weight":0.70,"statistical_prior_weight":0.30,"max_log_lambda_correction":0.16,"minimum_data_quality_for_bet":0.68,"minimum_full_ev":0.04,"minimum_robust_ev":0.015,"promotion_minimum_predictions":300}'::jsonb,
  'Fresh model line. No accuracy claim until frozen out-of-time validation passes.'
);
;
