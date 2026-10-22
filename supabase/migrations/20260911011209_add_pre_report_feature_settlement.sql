-- Supabase Cron uses UTC. 04:45 UTC is 12:45 Asia/Shanghai.
-- Run a deep settlement pass before the 13:00 daily analysis so the report
-- cannot race the regular 13:00 quick recovery job.
do $block$
declare
  v_job_id bigint;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron')
     or not exists (select 1 from pg_extension where extname = 'pg_net') then
    return;
  end if;

  select jobid into v_job_id
  from cron.job
  where jobname = 'football-feature-result-recovery-pre-report'
  limit 1;

  if v_job_id is not null then
    perform cron.unschedule(v_job_id);
  end if;

  perform cron.schedule(
    'football-feature-result-recovery-pre-report',
    '45 4 * * *',
    $job$
      select net.http_post(
        url := 'https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/football-feature-scan/settle',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-scan-key', (select scan_key from public.ah0_scanner_config where id = true)
        ),
        body := jsonb_build_object('lookback_days', 14, 'tier', 'pre_report'),
        timeout_milliseconds := 120000
      );
    $job$
  );
end;
$block$;;
