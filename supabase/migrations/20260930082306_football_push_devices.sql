create table public.football_push_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_token text not null unique,
  environment text not null check (environment in ('development', 'production')),
  bundle_id text not null default 'com.shenshangyuntec.footballcontrol',
  feature_pool_enabled boolean not null default true,
  bet_kickoff_enabled boolean not null default true,
  feature_baseline_initialized boolean not null default false,
  seen_feature_keys jsonb not null default '[]'::jsonb,
  last_registered_at timestamptz not null default now(),
  last_push_at timestamptz,
  last_push_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index football_push_devices_user_id_idx
  on public.football_push_devices(user_id);
alter table public.football_push_devices enable row level security;
revoke all on public.football_push_devices from anon, authenticated;
comment on table public.football_push_devices is
  'Private APNs device registrations. Access is only through authenticated Edge Functions.';
do $$
begin
  perform cron.unschedule('football-feature-push-sync');
exception when others then
  null;
end $$;
select cron.schedule(
  'football-feature-push-sync',
  '*/5 * * * *',
  $job$
    select net.http_post(
      url := 'https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/football-feature-scan/push-sync',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-scan-key', (select scan_key from public.ah0_scanner_config where id = true)
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 120000
    );
  $job$
);
