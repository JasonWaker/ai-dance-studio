-- Some of the earliest 7M fixtures are women's matches and are excluded by
-- the football scanner. One extra twelve-page wave keeps all 36 eligible
-- men's fixtures covered without increasing the two-hour scan frequency.
SELECT cron.schedule('football-sevenm-histories-4','34 */2 * * *',
  'SELECT public.football_enqueue_sevenm_histories(36,12);');
SELECT cron.alter_job(
  (SELECT jobid FROM cron.job WHERE jobname='football-sevenm-histories-ingest'),
  schedule := '38 */2 * * *'
);
;
