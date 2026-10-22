-- V2 patch: do not publish a formal MF-C recommendation when the modeled
-- edge is below 1.5%. The public model generation remains MFDR V2.
alter table public.multi_feature_runs
  alter column engine_revision set default 'mfdr-v2.0.1';

alter table public.multi_feature_decisions
  alter column engine_revision set default 'mfdr-v2.0.1';

alter table public.multi_feature_decision_history
  alter column engine_revision set default 'mfdr-v2.0.1';

comment on column public.multi_feature_decisions.engine_revision is
  'Immutable implementation revision; current MFDR V2 revision is mfdr-v2.0.1.';;
