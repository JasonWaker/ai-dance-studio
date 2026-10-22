-- Run a lightweight targeted verifier every minute. The Edge Function only
-- fetches matches whose kickoff is 2-12 minutes away, so failed attempts can
-- retry while each successful match records one auditable final snapshot.
do $$
declare existing_job bigint;
begin
  select jobid into existing_job from cron.job where jobname = 'football-feature-prekickoff-verify';
  if existing_job is not null then perform cron.unschedule(existing_job); end if;
end $$;

select cron.schedule(
  'football-feature-prekickoff-verify',
  '* * * * *',
  $$
    select net.http_post(
      url := 'https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/football-feature-scan/preflight',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-scan-key', (select scan_key from public.ah0_scanner_config where id = true)
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 90000
    );
  $$
);
;
