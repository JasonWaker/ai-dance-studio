-- Also recover rows whose source marked them live or finished without a score.
drop index if exists public.football_feature_matches_result_due_idx;
create index football_feature_matches_result_due_idx
  on public.football_feature_matches (last_result_check_at nulls first, kickoff_at)
  where status in ('scheduled', 'live', 'finished') and result is null;
;
