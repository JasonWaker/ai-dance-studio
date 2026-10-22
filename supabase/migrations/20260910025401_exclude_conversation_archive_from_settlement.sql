CREATE OR REPLACE VIEW public.plus8_final_pre_match_analysis AS
SELECT DISTINCT ON (a.match_id) a.id,a.match_id,a.analysis_key,a.model_name,a.model_version,a.analysis_type,a.analysis_time,a.is_valid,a.is_final_pre_match,a.data_completeness,a.confidence,a.model_total_lambda,a.predicted_scores,a.notes,a.created_at,a.analysis_source
FROM public.plus8_analyses a JOIN public.plus8_matches m ON m.id=a.match_id
WHERE a.analysis_type IN ('pre_match','pre_match_review') AND a.analysis_time<m.kickoff_time AND a.is_valid
AND (a.analysis_json->>'archive_batch') IS DISTINCT FROM 'conversation-20260909-manual'
ORDER BY a.match_id,a.analysis_time DESC,a.created_at DESC,a.id DESC;;
