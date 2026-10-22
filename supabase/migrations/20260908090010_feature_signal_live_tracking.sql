alter table public.football_feature_signals
  add column if not exists last_observed_at timestamptz,
  add column if not exists latest_price numeric,
  add column if not exists latest_handicap numeric,
  add column if not exists latest_total_line numeric,
  add column if not exists latest_evidence jsonb not null default '{}'::jsonb,
  add column if not exists currently_qualified boolean not null default true,
  add column if not exists left_range_at timestamptz,
  add column if not exists reentered_at timestamptz,
  add column if not exists range_transitions integer not null default 0;

update public.football_feature_signals
set last_observed_at = coalesce(last_observed_at, trigger_at),
    latest_price = coalesce(latest_price, trigger_price),
    latest_handicap = coalesce(latest_handicap, handicap),
    latest_total_line = coalesce(latest_total_line, total_line);

create index if not exists football_feature_signals_live_tracking_idx
  on public.football_feature_signals (kind, currently_qualified, last_observed_at desc);

comment on column public.football_feature_signals.currently_qualified is
  'Whether the same bookmaker quote still satisfies the feature rule at its latest reliable pre-match observation.';
comment on column public.football_feature_signals.left_range_at is
  'Most recent observation time when this bookmaker signal stopped satisfying its feature rule.';
;
