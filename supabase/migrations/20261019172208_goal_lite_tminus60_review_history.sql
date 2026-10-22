create table if not exists public.goal_lite_pick_reviews (
 id uuid primary key default gen_random_uuid(),
 pick_id uuid not null references public.goal_lite_daily_picks(id) on delete restrict,
 review_type text not null default 't_minus_60',
 scheduled_review_at timestamptz not null,
 reviewed_at timestamptz not null default now(),
 kickoff_at timestamptz not null,
 initial_snapshot jsonb not null,
 reviewed_snapshot jsonb not null,
 changes jsonb not null default '{}'::jsonb,
 decision text not null,
 review_reason text,
 odds_source text,
 odds_sampled_at timestamptz,
 model_version text not null default 'v1.0',
 data_quality text,
 created_at timestamptz not null default now(),
 constraint unique_goal_lite_review_window unique(pick_id,review_type,scheduled_review_at)
);
create index if not exists goal_lite_pick_reviews_pick_idx on public.goal_lite_pick_reviews (pick_id, reviewed_at desc);
alter table public.goal_lite_pick_reviews enable row level security;
create policy "Public read review history" on public.goal_lite_pick_reviews for select to anon, authenticated using (true);
revoke insert, update, delete on public.goal_lite_pick_reviews from anon,authenticated;
comment on table public.goal_lite_pick_reviews is 'Append-only GOAL-Lite pre-kickoff review snapshots, maintained separately from Plus8';;
