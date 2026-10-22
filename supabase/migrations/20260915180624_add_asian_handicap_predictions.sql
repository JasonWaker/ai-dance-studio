-- Store Asian handicap forecasts alongside totals and match-result forecasts.
alter table ou_model.predictions
  drop constraint if exists predictions_market_check,
  drop constraint if exists total_goals_line;

alter table ou_model.predictions
  add constraint predictions_market_check
    check (market in ('total_goals', 'asian_handicap', 'match_result', 'correct_score')),
  add constraint prediction_market_line
    check (
      (market = 'total_goals'
        and line is not null and line * 4 = trunc(line * 4)
        and line >= 0 and selection in ('over', 'under'))
      or
      (market = 'asian_handicap'
        and line is not null and line * 4 = trunc(line * 4)
        and selection in ('home', 'away'))
      or
      (market in ('match_result', 'correct_score') and line is null)
    );;
