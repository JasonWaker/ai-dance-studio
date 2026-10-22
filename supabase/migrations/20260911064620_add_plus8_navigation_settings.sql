create table public.plus8_site_settings (
  setting_key text primary key,
  setting_value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  constraint plus8_site_settings_key_length check (char_length(setting_key) between 1 and 80),
  constraint plus8_site_settings_value_object check (jsonb_typeof(setting_value) = 'object')
);
comment on table public.plus8_site_settings is 'Global administrator-managed presentation settings for the Plus8 site.';
alter table public.plus8_site_settings enable row level security;
revoke all on table public.plus8_site_settings from public, anon, authenticated;
grant all on table public.plus8_site_settings to service_role;
insert into public.plus8_site_settings (setting_key, setting_value)
values ('navigation', '{"items": []}'::jsonb)
on conflict (setting_key) do nothing;;
