-- Retire the historical high-over module without destroying its archived data.
-- Browser and authenticated clients can no longer query or mutate the module.
revoke all on table public.h2h_high_over_matches from anon, authenticated;
revoke all on table public.h2h_high_over_dashboard from anon, authenticated;
revoke all on table public.h2h_high_over_stats from anon, authenticated;
revoke all on table public.h2h_high_over_stats_by_line from anon, authenticated;
revoke all on table public.h2h_high_over_stats_by_h2h_rate from anon, authenticated;

revoke execute on function public.h2h_high_over_upsert(jsonb) from anon, authenticated;
revoke execute on function public.h2h_high_over_settle(text, integer, integer, text) from anon, authenticated;

comment on table public.h2h_high_over_matches is
  'Archived historical high-over module. Retired 2026-09-07; excluded from navigation, tasks, and statistics.';
;
