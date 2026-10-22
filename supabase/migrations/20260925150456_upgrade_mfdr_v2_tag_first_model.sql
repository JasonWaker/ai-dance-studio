-- User-authorized MFDR major iteration. Existing V1 decisions, history, and
-- bet snapshots remain unchanged; only new rows inherit the V2 generation.
alter table public.multi_feature_runs
  alter column model_version set default 'MFDR V2',
  alter column engine_revision set default 'mfdr-v2.0.0';

alter table public.multi_feature_decisions
  alter column model_version set default 'MFDR V2',
  alter column engine_revision set default 'mfdr-v2.0.0',
  alter column base_project_version set default 'football-platform-2026.09.25';

alter table public.multi_feature_decision_history
  alter column model_version set default 'MFDR V2',
  alter column engine_revision set default 'mfdr-v2.0.0';

comment on column public.multi_feature_decisions.model_version is
  'Immutable public recommendation generation. MFDR V2 is tag-first and preserves all historical V1 rows.';
comment on column public.multi_feature_decisions.engine_revision is
  'Immutable implementation revision; MFDR V2 starts at mfdr-v2.0.0.';
comment on column public.multi_feature_decisions.base_project_version is
  'Football platform release that generated this recommendation.';;
