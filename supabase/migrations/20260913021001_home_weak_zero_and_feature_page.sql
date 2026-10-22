-- The new draw-no-bet study shares the no-loss settlement definition with
-- away_zero, but is a separate signal and never changes old recommendations.
ALTER TABLE public.football_feature_signals
  DROP CONSTRAINT football_feature_signals_kind_check;
ALTER TABLE public.football_feature_signals
  ADD CONSTRAINT football_feature_signals_kind_check CHECK
  (kind = ANY (ARRAY['away_zero','home_weak_zero','reversal','rise_075',
                     'handicap_rise_05','losing_streak','over_streak',
                     'weak_favorite','total_line_jump']));

DO $migration$
DECLARE definition text;
BEGIN
  definition := pg_get_viewdef('public.football_feature_stats'::regclass, true);
  IF position($needle$('away_zero'::text),$needle$ in definition) = 0 THEN
    RAISE EXCEPTION 'football_feature_stats definition changed; inspect before extending';
  END IF;
  definition := replace(definition, $needle$('away_zero'::text),$needle$, $replacement$('away_zero'::text), ('home_weak_zero'::text),$replacement$);
  definition := replace(definition, $needle$k.kind = 'away_zero'::text$needle$, $replacement$k.kind = ANY (ARRAY['away_zero'::text, 'home_weak_zero'::text])$replacement$);
  EXECUTE 'CREATE OR REPLACE VIEW public.football_feature_stats AS ' || definition;

  definition := pg_get_viewdef('public.football_feature_stats_by_bookmaker'::regclass, true);
  definition := replace(definition, $needle$kind = 'away_zero'::text$needle$, $replacement$kind = ANY (ARRAY['away_zero'::text, 'home_weak_zero'::text])$replacement$);
  EXECUTE 'CREATE OR REPLACE VIEW public.football_feature_stats_by_bookmaker AS ' || definition;
END
$migration$;

-- Page keys are filtered and sorted in Postgres before bulky match JSON and
-- recommendation evidence are fetched. This avoids an ever-growing IN list
-- and downloading every match for a 30-row page. No duplicated mutable table.
CREATE OR REPLACE FUNCTION public.football_feature_page_keys(
  p_kind text, p_status text DEFAULT NULL, p_outcome text DEFAULT NULL,
  p_match_key text DEFAULT NULL, p_search text DEFAULT NULL,
  p_start timestamptz DEFAULT NULL, p_end timestamptz DEFAULT NULL,
  p_sort text DEFAULT 'smart', p_odds_band text DEFAULT NULL,
  p_page integer DEFAULT 1
) RETURNS jsonb LANGUAGE sql STABLE SET search_path = public AS $function$
WITH filtered AS (
  SELECT m.match_key, m.kickoff_at, m.status,
         CASE WHEN m.result IS NOT NULL THEN (m.result->>'finished_at')::timestamptz END AS settled_at,
         CASE WHEN m.status = 'scheduled' AND m.kickoff_at > now() THEN 0
              WHEN m.status = 'finished' OR m.result IS NOT NULL THEN 2
              WHEN m.status IN ('cancelled','postponed') THEN 3 ELSE 1 END AS sort_group
  FROM public.football_feature_matches m
  WHERE EXISTS (
    SELECT 1 FROM public.football_feature_signals s
    WHERE s.match_key = m.match_key AND s.kind = p_kind
      AND (p_outcome IS NULL OR (p_outcome = 'pending' AND s.outcome IS NULL)
           OR (p_outcome <> 'pending' AND s.outcome = p_outcome))
  )
    AND (p_status IS NULL OR m.status = p_status)
    AND (p_match_key IS NULL OR m.match_key = p_match_key)
    AND (p_start IS NULL OR m.kickoff_at >= p_start)
    AND (p_end IS NULL OR m.kickoff_at < p_end)
    AND (p_search IS NULL OR m.match_key ILIKE '%'||p_search||'%' OR
         m.competition_name ILIKE '%'||p_search||'%' OR
         m.home_team ILIKE '%'||p_search||'%' OR m.away_team ILIKE '%'||p_search||'%')
    AND (p_kind <> 'away_zero' OR p_odds_band IS NULL OR
      CASE p_odds_band
        WHEN 'low' THEN (m.last_pre_match_market->>'away_odds')::numeric BETWEEN 1.80 AND 1.82
        WHEN 'mid' THEN (m.last_pre_match_market->>'away_odds')::numeric BETWEEN 1.83 AND 1.85
        WHEN 'high' THEN (m.last_pre_match_market->>'away_odds')::numeric BETWEEN 1.86 AND 1.88
        WHEN 'below' THEN (m.last_pre_match_market->>'away_odds')::numeric < 1.80
        WHEN 'above' THEN (m.last_pre_match_market->>'away_odds')::numeric > 1.88
        ELSE true END)
), numbered AS (
  SELECT match_key, row_number() OVER (ORDER BY
    CASE WHEN p_sort = 'smart' THEN sort_group END ASC,
    CASE WHEN p_sort = 'smart' AND sort_group = 0 THEN kickoff_at END ASC,
    CASE WHEN p_sort = 'smart' AND sort_group = 2 THEN coalesce(settled_at,kickoff_at) END DESC,
    CASE WHEN p_sort = 'smart' AND sort_group <> 0 THEN kickoff_at END DESC,
    CASE WHEN p_sort = 'kickoff_asc' THEN kickoff_at END ASC,
    CASE WHEN p_sort = 'kickoff_desc' THEN kickoff_at END DESC,
    match_key ASC) AS row_num
  FROM filtered
)
SELECT jsonb_build_object(
  'total', (SELECT count(*) FROM filtered),
  'keys', coalesce((SELECT jsonb_agg(match_key ORDER BY row_num)
                    FROM numbered WHERE row_num > (greatest(p_page,1)-1)*30
                      AND row_num <= greatest(p_page,1)*30),'[]'::jsonb)
)
$function$;
REVOKE ALL ON FUNCTION public.football_feature_page_keys(text,text,text,text,text,timestamptz,timestamptz,text,text,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.football_feature_page_keys(text,text,text,text,text,timestamptz,timestamptz,text,text,integer) TO service_role;
;
