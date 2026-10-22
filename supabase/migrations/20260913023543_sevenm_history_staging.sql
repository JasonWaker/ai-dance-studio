-- Historical streak evidence is fetched in twelve-page waves every two
-- hours, after the public listing cache has refreshed. A failed page never
-- overwrites a previously verified copy.
CREATE TABLE IF NOT EXISTS public.football_sevenm_history_requests (
  request_id bigint PRIMARY KEY,
  match_id bigint NOT NULL,
  requested_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.football_sevenm_history_cache (
  match_id bigint PRIMARY KEY,
  content text NOT NULL,
  fetched_at timestamptz NOT NULL,
  response_status integer NOT NULL CHECK (response_status=200)
);
ALTER TABLE public.football_sevenm_history_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.football_sevenm_history_cache ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.football_sevenm_history_requests FROM anon,authenticated;
REVOKE ALL ON public.football_sevenm_history_cache FROM anon,authenticated;
GRANT SELECT ON public.football_sevenm_history_cache TO service_role;

CREATE OR REPLACE FUNCTION public.football_enqueue_sevenm_histories(p_offset integer,p_limit integer)
RETURNS integer LANGUAGE sql SECURITY DEFINER SET search_path=public,pg_temp AS $$
WITH live AS (
  SELECT regexp_matches(content,'sDt2\[([0-9]+)\]=\[([^\]]+)\]','g') AS m
  FROM public.football_source_cache WHERE source_key='7m_live'
), fixtures AS (
  SELECT (regexp_matches(content,'sDt\[([0-9]+)\]=\[','g'))[1] AS id
  FROM public.football_source_cache WHERE source_key='7m_fixtures'
), parsed AS (
  SELECT m[1] AS id,
    string_to_array(substring(m[2] FROM '''([0-9]{4},[0-9]{2},[0-9]{2},[0-9]{2},[0-9]{2},[0-9]{1,2})'''),',') AS k
  FROM live WHERE split_part(m[2],',',1)='17'
), timed AS (
  SELECT p.id::bigint AS match_id,
    make_timestamptz(k[1]::int,k[2]::int,k[3]::int,k[4]::int,k[5]::int,k[6]::int,'Asia/Shanghai') AS kickoff
  FROM parsed p JOIN fixtures f USING(id) WHERE k IS NOT NULL
), selected AS (
  SELECT match_id FROM timed
  WHERE kickoff BETWEEN now() AND now()+interval '24 hours'
  ORDER BY kickoff,match_id OFFSET p_offset LIMIT p_limit
), queued AS (
  INSERT INTO public.football_sevenm_history_requests(request_id,match_id)
  SELECT net.http_get(
    url := 'https://analyse.7m.com.cn/'||match_id||'/data/gameteamhistory_gb.js',
    timeout_milliseconds := 12000
  ),match_id FROM selected
  RETURNING 1
)
SELECT count(*)::integer FROM queued;
$$;
REVOKE ALL ON FUNCTION public.football_enqueue_sevenm_histories(integer,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.football_enqueue_sevenm_histories(integer,integer) TO postgres,service_role;

SELECT cron.schedule('football-sevenm-histories-1','28 */2 * * *',
  'SELECT public.football_enqueue_sevenm_histories(0,12);');
SELECT cron.schedule('football-sevenm-histories-2','30 */2 * * *',
  'SELECT public.football_enqueue_sevenm_histories(12,12);');
SELECT cron.schedule('football-sevenm-histories-3','32 */2 * * *',
  'SELECT public.football_enqueue_sevenm_histories(24,12);');
SELECT cron.schedule('football-sevenm-histories-ingest','35 */2 * * *',
$job$
INSERT INTO public.football_sevenm_history_cache(match_id,content,fetched_at,response_status)
SELECT DISTINCT ON (r.match_id) r.match_id,h.content,r.requested_at,h.status_code
FROM public.football_sevenm_history_requests r
JOIN net._http_response h ON h.id=r.request_id
WHERE r.requested_at>now()-interval '15 minutes'
  AND h.status_code=200 AND length(h.content)>200
ORDER BY r.match_id,r.requested_at DESC
ON CONFLICT(match_id) DO UPDATE SET
  content=excluded.content,fetched_at=excluded.fetched_at,
  response_status=excluded.response_status;
$job$);
;
