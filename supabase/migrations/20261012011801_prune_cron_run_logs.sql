delete from cron.job_run_details where end_time < now() - interval '7 days';
select cron.schedule('plus8-cron-run-log-retention', '15 3 * * *', $$delete from cron.job_run_details where end_time < now() - interval '7 days'$$);;
