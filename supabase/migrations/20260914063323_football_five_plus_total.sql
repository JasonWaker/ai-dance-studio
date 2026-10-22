-- Observational ≥5.0 pre-match total line; no investment recommendation.
alter table public.football_feature_signals
  drop constraint football_feature_signals_kind_check;

alter table public.football_feature_signals
  add constraint football_feature_signals_kind_check
  check (kind = any (array[
    'away_zero','home_weak_zero','reversal','rise_075','handicap_rise_05',
    'losing_streak','winning_streak','over_streak','weak_favorite',
    'total_line_jump','home_receive_225_25','five_plus_total'
  ]));
;
