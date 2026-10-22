
create table public.plus8_admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  granted_at timestamptz not null default now(),
  granted_by text not null default 'model_owner_seed'
);

comment on table public.plus8_admin_users is
  'Allowlist for authenticated accounts permitted to use the Plus8 dashboard write API.';

alter table public.plus8_admin_users enable row level security;
revoke all on table public.plus8_admin_users from public, anon, authenticated;
grant all on table public.plus8_admin_users to service_role;

insert into public.plus8_admin_users (user_id)
select distinct user_id
from public.model_versions
where user_id is not null
on conflict (user_id) do nothing;

create table public.plus8_admin_audit_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  action text not null check (action in ('sync_analysis', 'settle_match', 'update_match')),
  match_key text,
  request_payload jsonb not null default '{}'::jsonb,
  result_payload jsonb,
  created_at timestamptz not null default now()
);

comment on table public.plus8_admin_audit_log is
  'Append-only audit trail for writes performed from the Plus8 dashboard.';

create index plus8_admin_audit_log_user_created_idx
  on public.plus8_admin_audit_log (user_id, created_at desc);
create index plus8_admin_audit_log_match_created_idx
  on public.plus8_admin_audit_log (match_key, created_at desc)
  where match_key is not null;

alter table public.plus8_admin_audit_log enable row level security;
revoke all on table public.plus8_admin_audit_log from public, anon, authenticated;
grant all on table public.plus8_admin_audit_log to service_role;

create trigger plus8_admin_audit_append_only
before update or delete on public.plus8_admin_audit_log
for each row execute function public.plus8_prevent_history_mutation();
;
