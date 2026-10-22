-- MFDR V2 internal patch: compare both teams against common opponents.
-- Existing locked decisions retain the engine revision used at calculation time.
alter table public.multi_feature_runs
  alter column engine_revision set default 'mfdr-v2.1.1';

alter table public.multi_feature_decisions
  alter column engine_revision set default 'mfdr-v2.1.1';

alter table public.multi_feature_decision_history
  alter column engine_revision set default 'mfdr-v2.1.1';

comment on column public.multi_feature_decisions.engine_revision is
  'Immutable implementation revision; MFDR V2.1.1 adds common-opponent comparison to independent source analysis.';;
