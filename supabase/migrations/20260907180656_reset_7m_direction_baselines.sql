delete from public.football_feature_signals
where quote_type = 'aggregate_reference'
  and bookmaker = '7M公开盘路'
  and kind in ('reversal','rise_075');

delete from public.football_feature_opening_baselines
where bookmaker = '7M公开盘路';;
