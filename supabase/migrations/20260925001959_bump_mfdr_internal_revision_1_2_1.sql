alter table public.multi_feature_runs alter column engine_revision set default 'mfdr-v1.2.1';
alter table public.multi_feature_decisions alter column engine_revision set default 'mfdr-v1.2.1';
alter table public.multi_feature_decision_history alter column engine_revision set default 'mfdr-v1.2.1';
comment on column public.multi_feature_decisions.model_version is 'Public MFDR generation. It changes from V1 to V2 only after an explicit user-requested major iteration.';
comment on column public.multi_feature_decisions.engine_revision is 'Internal patch/minor revision for routine fixes and rule adjustments; current code revision mfdr-v1.2.1.';;
