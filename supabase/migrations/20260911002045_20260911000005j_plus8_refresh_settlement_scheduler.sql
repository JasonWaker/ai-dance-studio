create schema if not exists plus8_internal;

grant execute on function plus8_internal.settle_confirmed_results(timestamptz, interval, interval, integer) to service_role;
grant execute on function plus8_internal.refresh_settlement_scheduler() to service_role;
grant execute on function plus8_internal.settle_confirmed_results(timestamptz, interval, interval, integer) to postgres;
grant execute on function plus8_internal.refresh_settlement_scheduler() to postgres;

select plus8_internal.refresh_settlement_scheduler();;
