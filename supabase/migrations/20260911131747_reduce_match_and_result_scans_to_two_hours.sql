-- Keep the heavy fixture discovery scan at one run every two hours.
select cron.alter_job(
  (select jobid from cron.job where jobname = 'football-feature-scan-every-2-hours'),
  schedule := '32 */2 * * *'
);

-- The normal result recovery pass also runs every two hours. Offset it from
-- discovery so the public source requests are not emitted in one burst.
select cron.alter_job(
  (select jobid from cron.job where jobname = 'football-feature-result-recovery'),
  schedule := '7 */2 * * *'
);

-- Retain the wider fourteen-day recovery as a lower-frequency fallback instead
-- of running two result crawls in the same two-hour window.
select cron.alter_job(
  (select jobid from cron.job where jobname = 'football-feature-result-recovery-deep'),
  schedule := '37 */6 * * *'
);;
