-- Keep the expensive discovery/history scan at 30 minutes. Recheck only existing
-- upcoming OddStorm signals every 10 minutes so market monitoring cannot overlap
-- the full scanner under normal conditions.
select cron.alter_job(
  (select jobid from cron.job where jobname = 'football-feature-scan-every-2-hours'),
  schedule := '*/30 * * * *'
);

do $$
declare existing_job bigint;
begin
  select jobid into existing_job from cron.job where jobname = 'football-feature-market-track';
  if existing_job is not null then perform cron.unschedule(existing_job); end if;
end $$;

select cron.schedule(
  'football-feature-market-track',
  '*/10 * * * *',
  $$
    select net.http_post(
      url := 'https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/football-feature-scan/track',
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
