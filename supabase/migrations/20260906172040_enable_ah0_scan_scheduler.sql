create extension if not exists pg_cron;
create extension if not exists pg_net;

create table if not exists public.ah0_scanner_config (
  id boolean primary key default true check (id),
  scan_key text not null default encode(gen_random_bytes(24),'hex'),
  feed_url text,
  feed_token text,
  updated_at timestamptz not null default now()
);
alter table public.ah0_scanner_config enable row level security;
revoke all on public.ah0_scanner_config from anon, authenticated;
insert into public.ah0_scanner_config(id) values(true) on conflict (id) do nothing;

select cron.unschedule(jobid) from cron.job where jobname='ah0-away-water-every-3-hours';
select cron.schedule(
  'ah0-away-water-every-3-hours',
  '0 */3 * * *',
  $$
  select net.http_post(
    url := 'https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/ah0-away-water-scan/scan',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'X-Scan-Key',(select scan_key from public.ah0_scanner_config where id=true)
    ),
    body := jsonb_build_object('triggered_at',now()),
    timeout_milliseconds := 15000
  );
  $$
);
;
