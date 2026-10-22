-- Keep feature settlement responsive for recent matches while retaining a
-- wider recovery pass for delayed or temporarily unavailable result sources.
create or replace function plus8_internal.refresh_feature_result_recovery_jobs()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $fn$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron')
     or not exists (select 1 from pg_extension where extname = 'pg_net') then
    return;
  end if;

  perform cron.unschedule(jobid)
  from cron.job
  where jobname in (
    'football-feature-result-recovery',
    'football-feature-result-recovery-deep'
  );

  perform cron.schedule(
    'football-feature-result-recovery',
    '*/10 * * * *',
    $job$
      select net.http_post(
        url := 'https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/football-feature-scan/settle',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-scan-key', (select scan_key from public.ah0_scanner_config where id = true)
        ),
        body := jsonb_build_object('lookback_days', 4, 'tier', 'quick'),
        timeout_milliseconds := 120000
      );
    $job$
  );

  perform cron.schedule(
    'football-feature-result-recovery-deep',
    '7 * * * *',
    $job$
      select net.http_post(
        url := 'https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/football-feature-scan/settle',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-scan-key', (select scan_key from public.ah0_scanner_config where id = true)
        ),
        body := jsonb_build_object('lookback_days', 14, 'tier', 'deep'),
        timeout_milliseconds := 120000
      );
    $job$
  );
end;
$fn$;

select plus8_internal.refresh_feature_result_recovery_jobs();

grant execute on function plus8_internal.refresh_feature_result_recovery_jobs() to postgres;
grant execute on function plus8_internal.refresh_feature_result_recovery_jobs() to service_role;

comment on function plus8_internal.refresh_feature_result_recovery_jobs() is
  'Recreates the 10-minute four-day quick settlement scan and hourly fourteen-day recovery scan.';;
