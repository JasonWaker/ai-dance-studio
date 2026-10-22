-- Match the feature dashboard's category, outcome and time access paths.
create index if not exists football_feature_signals_kind_trigger_idx
  on public.football_feature_signals (kind, trigger_at desc);

create index if not exists football_feature_signals_kind_outcome_match_idx
  on public.football_feature_signals (kind, outcome, match_key);

create index if not exists football_feature_matches_status_kickoff_idx
  on public.football_feature_matches (status, kickoff_at desc);
;
