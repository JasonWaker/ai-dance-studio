create index if not exists football_feature_runs_started_at_desc_idx on public.football_feature_runs (started_at desc) include (finished_at);
create index if not exists football_feature_signals_last_observed_desc_idx on public.football_feature_signals (last_observed_at desc);
create index if not exists football_feature_signals_settled_desc_idx on public.football_feature_signals (settled_at desc) where settled_at is not null;;
