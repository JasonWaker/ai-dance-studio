-- MFDR V2 internal patch: use the latest complete pre-match market snapshot
-- inside the T-2h decision window and keep the implementation traceable.
alter table public.multi_feature_runs
  alter column engine_revision set default 'mfdr-v2.1.2';

alter table public.multi_feature_decisions
  alter column engine_revision set default 'mfdr-v2.1.2';

alter table public.multi_feature_decision_history
  alter column engine_revision set default 'mfdr-v2.1.2';

comment on column public.multi_feature_decisions.engine_revision is
  'Immutable implementation revision; MFDR V2.1.2 adds T-2h market fallback and batched source queries.';;
