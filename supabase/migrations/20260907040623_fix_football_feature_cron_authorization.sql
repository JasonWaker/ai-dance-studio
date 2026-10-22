do $migration$
declare
  v_job_id bigint;
begin
  select jobid into v_job_id from cron.job where jobname = 'football-feature-scan-every-2-hours';
  if v_job_id is null then
    raise exception 'football feature cron job not found';
  end if;
  perform cron.alter_job(
    v_job_id,
    command := $command$
      select net.http_post(
        url := 'https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/football-feature-scan/scan',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYXNlIiwicmVmIjoidWxqdm5kamtkZmJ2YXpick'
        ),
        body := '{}'::jsonb,
        timeout_milliseconds := 120000
      );
    $command$
  );
end
$migration$;;
