create table if not exists public.goal_lite_daily_picks (
 id uuid primary key default gen_random_uuid(),
 report_date date not null,
 league_code text not null,
 league_name_zh text not null,
 match_key text not null,
 home_team_zh text not null,
 away_team_zh text not null,
 kickoff_at timestamptz not null,
 model_name text not null default 'GOAL-Lite',
 model_version text not null default 'v1.0',
 selection_rank integer,
 daily_top_rank integer,
 pick_side text check (pick_side in ('over','under') or pick_side is null),
 goal_line numeric(4,2),
 decimal_odds numeric(8,3),
 odds_asof timestamptz,
 odds_source text,
 expected_goals numeric(5,2),
 win_probability numeric(7,5),
 push_probability numeric(7,5),
 half_win_probability numeric(7,5),
 half_loss_probability numeric(7,5),
 loss_probability numeric(7,5),
 simulated_ev numeric(9,5),
 rating text,
 units numeric(5,2) not null default 0,
 recommendation_status text not null default 'observe' check (recommendation_status in ('observe','recommended','no_bet','insufficient_data','settled')),
 evidence text,
 risk_notes text,
 predicted_scores text[],
 data_quality text,
 calculation_status text default 'unverified',
 score_home integer,
 score_away integer,
 settled_at timestamptz,
 settlement_result text,
 report_generated_at timestamptz not null default now(),
 source_type text not null default 'chatgpt_daily_task',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint goal_lite_daily_picks_uniq unique(report_date, league_code, match_key)
);
create index if not exists goal_lite_daily_picks_kickoff_idx on public.goal_lite_daily_picks(kickoff_at desc);
create index if not exists goal_lite_daily_picks_report_idx on public.goal_lite_daily_picks(report_date desc, daily_top_rank);
alter table public.goal_lite_daily_picks enable row level security;
create policy "Daily picks public read" on public.goal_lite_daily_picks for select to anon, authenticated using (true);
revoke insert, update, delete on public.goal_lite_daily_picks from anon, authenticated;
comment on table public.goal_lite_daily_picks is 'GOAL-Lite daily fourteen league picks; separate from Plus8 and other models. Server-only writes.';;
