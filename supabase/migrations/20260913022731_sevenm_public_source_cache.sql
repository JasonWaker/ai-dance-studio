-- 7M's public live CDN is reachable from Postgres' network but not from the
-- Edge runtime. Cache only two unauthenticated listing files for the two-hour
-- feature scan; no credentials or personal data enter this table.
CREATE TABLE IF NOT EXISTS public.football_source_cache (
  source_key text PRIMARY KEY CHECK (source_key IN ('7m_fixtures','7m_live')),
  content text NOT NULL,
  fetched_at timestamptz NOT NULL DEFAULT now(),
  response_status integer NOT NULL CHECK (response_status = 200)
);
ALTER TABLE public.football_source_cache ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.football_source_cache FROM anon, authenticated;
GRANT SELECT ON public.football_source_cache TO service_role;

CREATE TABLE IF NOT EXISTS public.football_source_fetch_requests (
  request_id bigint PRIMARY KEY,
  source_key text NOT NULL CHECK (source_key IN ('7m_fixtures','7m_live')),
  requested_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.football_source_fetch_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.football_source_fetch_requests FROM anon, authenticated;

-- pg_net runs asynchronously. The second job imports only successful,
-- nonempty responses. A failed fetch leaves the previous cache intact and
-- the Edge scanner marks it stale after four hours.
SELECT cron.schedule('football-sevenm-public-fetch','25 */2 * * *',
$job$
INSERT INTO public.football_source_fetch_requests(request_id,source_key)
SELECT net.http_get(url := 'http://ctc-live.7m.com.cn/datafile/fgb2.js',timeout_milliseconds := 12000),'7m_fixtures'
UNION ALL
SELECT net.http_get(url := 'http://js-live.7m.com.cn/livedts/csxl.js',timeout_milliseconds := 12000),'7m_live';
$job$);

SELECT cron.schedule('football-sevenm-public-ingest','27 */2 * * *',
$job$
INSERT INTO public.football_source_cache(source_key,content,fetched_at,response_status)
SELECT DISTINCT ON (r.source_key) r.source_key,h.content,r.requested_at,h.status_code
FROM public.football_source_fetch_requests r
JOIN net._http_response h ON h.id=r.request_id
WHERE r.requested_at>now()-interval '15 minutes'
  AND h.status_code=200 AND length(h.content)>10000
ORDER BY r.source_key,r.requested_at DESC
ON CONFLICT(source_key) DO UPDATE SET
 content=excluded.content,fetched_at=excluded.fetched_at,
 response_status=excluded.response_status;
$job$);
;
