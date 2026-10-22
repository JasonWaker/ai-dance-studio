create index if not exists goal_lite_daily_picks_sync_run_idx
  on public.goal_lite_daily_picks(sync_run_id)
  where sync_run_id is not null;;
