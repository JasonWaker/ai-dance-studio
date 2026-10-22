update public.football_feature_signals
set latest_price = null,
    latest_total_line = null,
    last_observed_at = trigger_at,
    currently_qualified = true,
    left_range_at = null,
    range_transitions = greatest(coalesce(range_transitions, 0) - 1, 0),
    latest_evidence = coalesce(latest_evidence, '{}'::jsonb) || jsonb_build_object(
      'tracking_note', '本场大小盘未采集；历史错误零值已清理'
    )
where kind = 'over_streak'
  and total_line is null
  and latest_total_line = 0
  and coalesce(latest_evidence->>'over_odds', '') = ''
  and coalesce(latest_evidence->>'under_odds', '') = '';;
