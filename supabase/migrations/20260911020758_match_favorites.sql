create table public.match_favorite_groups (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 40),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, name),
  unique (id, user_id)
);

create table public.match_favorites (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  match_key text not null check (char_length(match_key) between 1 and 160),
  group_id uuid,
  kickoff_at timestamptz not null,
  competition_name text not null default '',
  home_team text not null,
  away_team text not null,
  source_path text not null default '',
  feature_kinds text[] not null default '{}',
  note text not null default '' check (char_length(note) <= 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, match_key),
  foreign key (group_id, user_id)
    references public.match_favorite_groups(id, user_id)
    on delete set null (group_id)
);

create index match_favorite_groups_user_sort_idx
  on public.match_favorite_groups (user_id, sort_order, created_at);

create index match_favorites_user_kickoff_idx
  on public.match_favorites (user_id, kickoff_at desc);

create index match_favorites_user_group_idx
  on public.match_favorites (user_id, group_id, updated_at desc);

alter table public.match_favorite_groups enable row level security;
alter table public.match_favorites enable row level security;

revoke all on table public.match_favorite_groups from anon, authenticated;
revoke all on table public.match_favorites from anon, authenticated;

comment on table public.match_favorite_groups is 'Per-admin groups for saved football matches; accessed only through an authenticated Edge Function.';
comment on table public.match_favorites is 'Per-admin saved football matches with immutable match identity and editable notes.';
;
