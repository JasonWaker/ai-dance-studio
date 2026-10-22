create trigger pool_mfdr_inserted after insert on public.multi_feature_decisions
for each row when (new.decision_status='RECOMMEND' and new.analysis_phase='pre_match' and new.confidence_strategy_direction='reverse')
execute function feature_pool_internal.mark_dirty();
create trigger pool_mfdr_changed after update of decision_status,confidence_strategy_direction,settlement_outcome on public.multi_feature_decisions
for each row when ((old.confidence_strategy_direction='reverse' or new.confidence_strategy_direction='reverse') and
(old.decision_status is distinct from new.decision_status or old.confidence_strategy_direction is distinct from new.confidence_strategy_direction or old.settlement_outcome is distinct from new.settlement_outcome))
execute function feature_pool_internal.mark_dirty();
;
