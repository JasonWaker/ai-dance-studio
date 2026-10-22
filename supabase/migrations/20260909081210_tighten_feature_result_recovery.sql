select cron.alter_job(
  job_id := 3,
  schedule := '5,20,35,50 * * * *',
  command := $job$
    select net.http_post(
      url := 'https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/football-feature-scan/settle',
      headers := jsonb_build_object(
        'Content-Type','application/json',
        'x-scan-key',(select scan_key from public.ah0_scanner_config where id = true)
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 90000
    );
  $job$,
  active := true
);;
