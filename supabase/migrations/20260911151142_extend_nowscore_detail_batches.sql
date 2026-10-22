-- Cover every persisted Nowscore fixture starting in the next three hours.
-- Five overlapping batches scan up to 156 ordered fixtures without bursts.
select cron.schedule(
  'football-feature-nowscore-detail-4',
  '50 */2 * * *',
  $$select net.http_post(
      url := 'https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/football-feature-scan/nowscore-detail?batch=3',
      headers := jsonb_build_object('Content-Type','application/json','x-scan-key',(select scan_key from public.ah0_scanner_config where id=true)),
      body := '{}'::jsonb,
      timeout_milliseconds := 45000
    );$$
);

select cron.schedule(
  'football-feature-nowscore-detail-5',
  '55 */2 * * *',
  $$select net.http_post(
      url := 'https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/football-feature-scan/nowscore-detail?batch=4',
      headers := jsonb_build_object('Content-Type','application/json','x-scan-key',(select scan_key from public.ah0_scanner_config where id=true)),
      body := '{}'::jsonb,
      timeout_milliseconds := 45000
    );$$
);
;
