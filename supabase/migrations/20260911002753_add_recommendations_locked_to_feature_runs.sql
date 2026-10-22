
alter table public.football_feature_runs
  add column if not exists recommendations_locked integer not null default 0;

comment on column public.football_feature_runs.recommendations_locked is
  'Number of pre-match investment recommendation snapshots locked during this scan or settlement recovery run.';
;
