update ou_model.model_versions
set config = '{
  "model_name":"足球专家 X 模型",
  "model_slug":"football-expert-x",
  "version":"1.0.0",
  "status":"challenger",
  "market_prior_weight":0.70,
  "statistical_prior_weight":0.30,
  "max_log_lambda_correction":0.16,
  "minimum_data_quality_for_bet":0.68,
  "minimum_full_ev":0.04,
  "minimum_robust_ev":0.015,
  "minimum_bookmakers":2,
  "factor_caps":{"availability_xg":0.45,"schedule_xg":0.20,"context_xg":0.20,"transfer_xg":0.15,"harmony_xg":0.08},
  "promotion_gate":{"minimum_predictions":300,"require_brier_improvement":true,"require_log_loss_improvement":true,"maximum_calibration_error":0.05,"require_nonnegative_roi_after_costs":true,"maximum_drawdown":0.20}
}'::jsonb
where model_slug = 'football-expert-x' and version = '1.0.0';
;
