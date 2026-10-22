alter table public.football_feature_identity_conflicts
  add column if not exists resolved_at timestamptz,
  add column if not exists resolution text;
create index if not exists football_feature_identity_conflicts_open_idx
  on public.football_feature_identity_conflicts(detected_at desc)
  where resolved_at is null;
;
