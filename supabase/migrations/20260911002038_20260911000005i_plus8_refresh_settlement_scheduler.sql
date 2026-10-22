create or replace function plus8_internal.refresh_settlement_scheduler()
returns void
language plpgsql
as $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    return;
  end if;

  begin
    perform cron.unschedule('plus8-settle-confirmed-results');
  exception when undefined_function then
    return;
  end;

  perform cron.schedule(
    'plus8-settle-confirmed-results',
    '*/15 * * * *',
    'select plus8_internal.settle_confirmed_results();'
  );
end;$$;;
