-- Twenty Bailian lookups run in four waves of five. Keep the pg_net caller
-- alive longer than the search phase, but below the Edge Function's 150s
-- request idle timeout.
do $$
declare
  name_job_id bigint;
  name_job_command text;
begin
  select jobid, command into name_job_id, name_job_command
  from cron.job
  where jobname = 'football-leisu-name-sync';

  if name_job_id is null then
    raise exception 'football-leisu-name-sync cron job not found';
  end if;
  if name_job_command not like '%timeout_milliseconds := 60000%' then
    raise exception 'football-leisu-name-sync cron timeout has changed; review before altering';
  end if;

  perform cron.alter_job(
    name_job_id,
    command := replace(name_job_command, 'timeout_milliseconds := 60000', 'timeout_milliseconds := 120000')
  );
end $$;
;
