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
          'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVsanZuZGprZGZidmF6aHJyeG1kIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc1NzQ1NDMsImV4cCI6MjEwMzE1MDU0M30.kwicEwj9rpmwKz1RM1UkGw9tOqmlStDai50kCc4S38I',
          'x-scan-key', (select scan_key from public.ah0_scanner_config where id = true)
        ),
        body := '{}'::jsonb,
        timeout_milliseconds := 120000
      );
    $command$
  );
end
$migration$;;
