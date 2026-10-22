-- The fetch queue keeps up to 48 fixtures. The parser still applies the
-- existing 36-fixture priority budget, but the prioritized IDs can fall in
-- any of the four deterministic cache pages.
select cron.schedule('football-sevenm-h2h-parse-4','56 */2 * * *',
$job$
select net.http_post(
  url := 'https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/football-feature-scan/h2h-evidence?batch=3',
  headers := jsonb_build_object(
    'Content-Type','application/json',
    'x-scan-key',(select scan_key from public.ah0_scanner_config where id=true)
  ),
  body := '{}'::jsonb,
  timeout_milliseconds := 60000
);
$job$);

;
