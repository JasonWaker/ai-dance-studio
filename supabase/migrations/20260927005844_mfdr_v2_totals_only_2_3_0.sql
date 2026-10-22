-- MFDR V2 internal iteration: every new recommendation is an Asian total-goals
-- decision. Historical handicap decisions remain immutable for audit.
alter table public.multi_feature_runs
  alter column engine_revision set default 'mfdr-v2.3.0';

alter table public.multi_feature_decisions
  alter column engine_revision set default 'mfdr-v2.3.0';

alter table public.multi_feature_decision_history
  alter column engine_revision set default 'mfdr-v2.3.0';

comment on column public.multi_feature_decisions.confidence_score is
  'Evidence confidence (not win probability). MFDR V2.3 adds total-goals projection, BTTS, clean-sheet, failed-to-score and goal-volatility evidence; values above 90% are highlighted in the UI.';;
