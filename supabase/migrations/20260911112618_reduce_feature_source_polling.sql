select cron.alter_job((select jobid from cron.job where jobname = 'football-feature-market-track'), schedule := '17 * * * *');
select cron.alter_job((select jobid from cron.job where jobname = 'football-feature-scan-every-2-hours'), schedule := '32 */2 * * *');;
