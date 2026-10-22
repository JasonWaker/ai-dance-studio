create or replace function plus8_internal.refresh_settlement_scheduler()
returns void
language plpgsql
as $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    return;
  end if;

  perform 1;
end;
$$;
;
