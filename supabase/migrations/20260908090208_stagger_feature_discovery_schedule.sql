select cron.alter_job((select jobid from cron.job where jobname = 'football-feature-scan-every-2-hours'), schedule := '2,32 * * * *');;
