-- The historical 7M streak pages must not share one Edge worker with the
-- multi-provider discovery scan. Both jobs run once per two hours, staggered
-- after the two public listing files have been cached.
SELECT cron.schedule('football-sevenm-streak-scan','42 */2 * * *',
$job$
SELECT net.http_post(
  url := 'https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/football-feature-scan/scan?source=7M',
  headers := jsonb_build_object(
    'Content-Type','application/json',
    'x-scan-key',(SELECT scan_key FROM public.ah0_scanner_config WHERE id=true)
  ),
  body := '{}'::jsonb,
  timeout_milliseconds := 120000
);
$job$);
;
