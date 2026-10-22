-- MFDR exposes a stable product model version and tracks implementation
-- revisions separately. This prevents code-level v1.x revisions from being
-- mistaken for different recommendation models.

alter table public.multi_feature_runs
  add column model_version text,
  add column engine_revision text;

update public.multi_feature_runs
set model_version = 'MFDR V1',
    engine_revision = 'legacy-untracked';

alter table public.multi_feature_runs
  alter column model_version set not null,
  alter column model_version set default 'MFDR V1',
  alter column engine_revision set not null,
  alter column engine_revision set default 'mfdr-v1.2.0',
  add constraint multi_feature_runs_model_version_format
    check (model_version ~ '^MFDR V[1-9][0-9]*$');

alter table public.multi_feature_decisions
  add column engine_revision text;

alter table public.multi_feature_decisions
  disable trigger multi_feature_decisions_immutable_lock;

update public.multi_feature_decisions
set engine_revision = case lower(model_version)
      when 'mfdr v1.2' then 'mfdr-v1.2.0'
      when 'mfdr v1.1' then 'mfdr-v1.1.0'
      when 'mfdr v1' then 'mfdr-v1.0.0'
      else 'legacy-untracked'
    end,
    model_version = 'MFDR V1';

alter table public.multi_feature_decisions
  enable trigger multi_feature_decisions_immutable_lock;

alter table public.multi_feature_decisions
  alter column model_version set default 'MFDR V1',
  alter column engine_revision set not null,
  alter column engine_revision set default 'mfdr-v1.2.0',
  add constraint multi_feature_decisions_model_version_format
    check (model_version ~ '^MFDR V[1-9][0-9]*$');

alter table public.multi_feature_decision_history
  add column model_version text,
  add column engine_revision text;

update public.multi_feature_decision_history
set model_version = 'MFDR V1',
    engine_revision = case lower(snapshot->>'model_version')
      when 'mfdr v1.2' then 'mfdr-v1.2.0'
      when 'mfdr v1.1' then 'mfdr-v1.1.0'
      when 'mfdr v1' then 'mfdr-v1.0.0'
      else 'legacy-untracked'
    end,
    snapshot = snapshot || jsonb_build_object(
      'legacy_model_version', coalesce(snapshot->>'model_version', 'missing'),
      'model_version', 'MFDR V1',
      'engine_revision', case lower(snapshot->>'model_version')
        when 'mfdr v1.2' then 'mfdr-v1.2.0'
        when 'mfdr v1.1' then 'mfdr-v1.1.0'
        when 'mfdr v1' then 'mfdr-v1.0.0'
        else 'legacy-untracked'
      end
    );

alter table public.multi_feature_decision_history
  alter column model_version set not null,
  alter column model_version set default 'MFDR V1',
  alter column engine_revision set not null,
  alter column engine_revision set default 'mfdr-v1.2.0',
  add constraint multi_feature_history_model_version_format
    check (model_version ~ '^MFDR V[1-9][0-9]*$');

update public.bet_records record
set mfdr_decision_snapshots = coalesce((
  select jsonb_agg(
    item || jsonb_build_object(
      'legacy_model_version', coalesce(item->>'model_version', 'missing'),
      'model_version', 'MFDR V1',
      'engine_revision', case lower(item->>'model_version')
        when 'mfdr v1.2' then 'mfdr-v1.2.0'
        when 'mfdr v1.1' then 'mfdr-v1.1.0'
        when 'mfdr v1' then 'mfdr-v1.0.0'
        else coalesce(nullif(item->>'engine_revision',''), 'legacy-untracked')
      end
    ) order by ordinal
  )
  from jsonb_array_elements(record.mfdr_decision_snapshots) with ordinality as entry(item, ordinal)
), '[]'::jsonb)
where jsonb_array_length(record.mfdr_decision_snapshots) > 0;

comment on column public.multi_feature_runs.model_version is
  'Public MFDR model generation used for this run, for example MFDR V1.';
comment on column public.multi_feature_runs.engine_revision is
  'Internal implementation revision used for reproducibility; does not change the public model generation.';
comment on column public.multi_feature_decisions.model_version is
  'Immutable public recommendation model generation attached to the match decision.';
comment on column public.multi_feature_decisions.engine_revision is
  'Immutable internal implementation revision attached to the match decision.';
comment on column public.multi_feature_decision_history.model_version is
  'Public recommendation model generation captured with this historical snapshot.';
comment on column public.multi_feature_decision_history.engine_revision is
  'Internal implementation revision captured with this historical snapshot.';;
