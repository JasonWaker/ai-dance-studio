CREATE OR REPLACE VIEW public.plus8_source_scale_stats AS
WITH sources(analysis_source) AS (VALUES ('manual_analysis'::text), ('system_scan'::text))
SELECT s.analysis_source,
count(DISTINCT a.match_id) FILTER (WHERE a.is_valid)::integer AS match_count,
count(a.id)::integer AS analysis_count
FROM sources s LEFT JOIN public.plus8_analyses a USING (analysis_source)
GROUP BY s.analysis_source;;
