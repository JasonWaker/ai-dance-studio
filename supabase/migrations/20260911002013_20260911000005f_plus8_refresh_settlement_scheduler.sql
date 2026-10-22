create or replace function plus8_internal.refresh_settlement_scheduler()
returns void
language plpgsql
as $$
begin
  begin
    perform cron.unschedule('plus8-settle-confirmed-results');
  exception when undefined_function then
    return;
  end;
end;$$;;
