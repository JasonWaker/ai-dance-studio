-- MFDR V2 internal minor iteration: combine source-derived recent form,
-- attack/defence, venue, ranking and head-to-head analysis with feature tags.
-- Existing locked decisions retain their original engine revision.
alter table public.multi_feature_runs
  alter column engine_revision set default 'mfdr-v2.1.0';

alter table public.multi_feature_decisions
  alter column engine_revision set default 'mfdr-v2.1.0',
  alter column base_project_version set default 'football-platform-2026.09.25-mfdr-source-analysis';

alter table public.multi_feature_decision_history
  alter column engine_revision set default 'mfdr-v2.1.0';

comment on column public.multi_feature_decisions.engine_revision is
  'Immutable implementation revision; MFDR V2.1 adds independent source-data analysis before market validation.';;
