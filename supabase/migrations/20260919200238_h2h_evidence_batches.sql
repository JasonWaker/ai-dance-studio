-- Parse cached 7M direct-meeting pages in bounded Edge batches after the
-- database-side HTTP fetch and ingest stages complete.
select cron.schedule('football-sevenm-h2h-parse-1','50 */2 * * *',
$job$
select net.http_post(
  url := 'https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/football-feature-scan/h2h-evidence?batch=0',
  headers := jsonb_build_object(
    'Content-Type','application/json',
    'x-scan-key',(select scan_key from public.ah0_scanner_config where id=true)
  ),
  body := '{}'::jsonb,
  timeout_milliseconds := 60000
);
$job$);

select cron.schedule('football-sevenm-h2h-parse-2','52 */2 * * *',
$job$
select net.http_post(
  url := 'https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/football-feature-scan/h2h-evidence?batch=1',
  headers := jsonb_build_object(
    'Content-Type','application/json',
    'x-scan-key',(select scan_key from public.ah0_scanner_config where id=true)
  ),
  body := '{}'::jsonb,
  timeout_milliseconds := 60000
);
$job$);

select cron.schedule('football-sevenm-h2h-parse-3','54 */2 * * *',
$job$
select net.http_post(
  url := 'https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/football-feature-scan/h2h-evidence?batch=2',
  headers := jsonb_build_object(
    'Content-Type','application/json',
    'x-scan-key',(select scan_key from public.ah0_scanner_config where id=true)
  ),
  body := '{}'::jsonb,
  timeout_milliseconds := 60000
);
$job$);

;
