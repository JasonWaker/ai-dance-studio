alter table public.football_feature_signals
  drop constraint if exists football_feature_signals_kind_check;

alter table public.football_feature_signals
  add constraint football_feature_signals_kind_check
  check (kind = any (array[
    'away_zero'::text,
    'home_weak_zero'::text,
    'reversal'::text,
    'rise_075'::text,
    'handicap_rise_05'::text,
    'underdog_075'::text,
    'losing_streak'::text,
    'winning_streak'::text,
    'over_streak'::text,
    'weak_favorite'::text,
    'total_line_jump'::text,
    'home_receive_225_25'::text,
    'h2h_over_70'::text,
    'home_dragon'::text,
    'away_worm'::text,
    'five_plus_total'::text
  ]));

comment on constraint football_feature_signals_kind_check on public.football_feature_signals is
  '允许独立足球特征信号；underdog_075 为主盘受让 0.75 且受让方十进制水位在 1.65 至 2.00。';;
