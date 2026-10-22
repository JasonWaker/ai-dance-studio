-- Spread the five detail batches across the two-hour cycle. This keeps one
-- Nowscore batch at a time with twenty minutes between batches.
select cron.unschedule(jobid)
from cron.job
where jobname like 'football-feature-nowscore-detail-%';

select cron.schedule(
  'football-feature-nowscore-detail-1', '35 */2 * * *',
  $$select net.http_post(url := 'https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/football-feature-scan/nowscore-detail?batch=0', headers := jsonb_build_object('Content-Type','application/json','x-scan-key',(select scan_key from public.ah0_scanner_config where id=true)), body := '{}'::jsonb, timeout_milliseconds := 45000);$$
);
select cron.schedule(
  'football-feature-nowscore-detail-2', '55 */2 * * *',
  $$select net.http_post(url := 'https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/football-feature-scan/nowscore-detail?batch=1', headers := jsonb_build_object('Content-Type','application/json','x-scan-key',(select scan_key from public.ah0_scanner_config where id=true)), body := '{}'::jsonb, timeout_milliseconds := 45000);$$
);
select cron.schedule(
  'football-feature-nowscore-detail-3', '15 1-23/2 * * *',
  $$select net.http_post(url := 'https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/football-feature-scan/nowscore-detail?batch=2', headers := jsonb_build_object('Content-Type','application/json','x-scan-key',(select scan_key from public.ah0_scanner_config where id=true)), body := '{}'::jsonb, timeout_milliseconds := 45000);$$
);
select cron.schedule(
  'football-feature-nowscore-detail-4', '35 1-23/2 * * *',
  $$select net.http_post(url := 'https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/football-feature-scan/nowscore-detail?batch=3', headers := jsonb_build_object('Content-Type','application/json','x-scan-key',(select scan_key from public.ah0_scanner_config where id=true)), body := '{}'::jsonb, timeout_milliseconds := 45000);$$
);
select cron.schedule(
  'football-feature-nowscore-detail-5', '55 1-23/2 * * *',
  $$select net.http_post(url := 'https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/football-feature-scan/nowscore-detail?batch=4', headers := jsonb_build_object('Content-Type','application/json','x-scan-key',(select scan_key from public.ah0_scanner_config where id=true)), body := '{}'::jsonb, timeout_milliseconds := 45000);$$
);
;
