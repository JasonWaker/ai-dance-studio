-- MFDR V2 internal minor iteration: one judgment per match, confidence instead
-- of A/B/C/D publication gates. Historical grades remain valid and unchanged.
alter table public.multi_feature_decisions
  drop constraint multi_feature_decisions_grade_check;

alter table public.multi_feature_decisions
  add constraint multi_feature_decisions_grade_check
  check (grade in ('MF','MF-A','MF-B','MF-C','MF-D'));

alter table public.multi_feature_runs
  alter column engine_revision set default 'mfdr-v2.2.0';

alter table public.multi_feature_decisions
  alter column engine_revision set default 'mfdr-v2.2.0';

alter table public.multi_feature_decision_history
  alter column engine_revision set default 'mfdr-v2.2.0';

comment on column public.multi_feature_decisions.grade is
  'MF for the current single-confidence model; legacy MF-A/B/C/D values are retained for historical audit.';

comment on column public.multi_feature_decisions.confidence_score is
  'Evidence confidence (not win probability), combining modules, feature strength, completeness, source coverage, conflict, price value and market age.';
;
