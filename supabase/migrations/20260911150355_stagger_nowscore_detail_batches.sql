-- Nowscore publishes hundreds of fixtures in one list. Detail pages are split
-- into three small, overlapping batches so every invocation stays below the
-- Edge wall-clock limit while requests remain paced and recoverable.
do $$
declare existing_job record;
begin
  for existing_job in
    select jobid from cron.job where jobname like 'football-feature-nowscore-detail-%'
  loop
    perform cron.unschedule(existing_job.jobid);
  end loop;
end
$$;

select cron.schedule(
  'football-feature-nowscore-detail-1',
  '35 */2 * * *',
  $$select net.http_post(
      url := 'https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/football-feature-scan/nowscore-detail?batch=0',
      headers := jsonb_build_object('Content-Type','application/json','x-scan-key',(select scan_key from public.ah0_scanner_config where id=true)),
      body := '{}'::jsonb,
      timeout_milliseconds := 45000
    );$$
);

select cron.schedule(
  'football-feature-nowscore-detail-2',
  '40 */2 * * *',
  $$select net.http_post(
      url := 'https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/football-feature-scan/nowscore-detail?batch=1',
      headers := jsonb_build_object('Content-Type','application/json','x-scan-key',(select scan_key from public.ah0_scanner_config where id=true)),
      body := '{}'::jsonb,
      timeout_milliseconds := 45000
    );$$
);

select cron.schedule(
  'football-feature-nowscore-detail-3',
  '45 */2 * * *',
  $$select net.http_post(
      url := 'https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/football-feature-scan/nowscore-detail?batch=2',
      headers := jsonb_build_object('Content-Type','application/json','x-scan-key',(select scan_key from public.ah0_scanner_config where id=true)),
      body := '{}'::jsonb,
      timeout_milliseconds := 45000
    );$$
);
;
