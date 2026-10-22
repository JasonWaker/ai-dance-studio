-- Match the 7M scanner's men's-fixture filter before paging history URLs.
-- This avoids fetching twelve irrelevant women's pages and leaves the
-- original three twelve-page waves sufficient for complete near-term cover.
CREATE OR REPLACE FUNCTION public.football_enqueue_sevenm_histories(p_offset integer,p_limit integer)
RETURNS integer LANGUAGE sql SECURITY DEFINER SET search_path=public,pg_temp AS $$
WITH live AS (
  SELECT regexp_matches(content,'sDt2\[([0-9]+)\]=\[([^\]]+)\]','g') AS m
  FROM public.football_source_cache WHERE source_key='7m_live'
), fixtures AS (
  SELECT m[1] AS id FROM (
    SELECT regexp_matches(content,
      'sDt\[([0-9]+)\]=\[''([^'']*)'',''([^'']*)'',''([^'']*)'',''([^'']*)''','g') AS m
    FROM public.football_source_cache WHERE source_key='7m_fixtures'
  ) f
  WHERE (m[2]||m[4]||m[5]) !~* '(女|women|ladies|femeni|feminino|femenil|frauen|dames)'
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
SELECT cron.unschedule((SELECT jobid FROM cron.job WHERE jobname='football-sevenm-histories-4'));
SELECT cron.alter_job(
  (SELECT jobid FROM cron.job WHERE jobname='football-sevenm-histories-ingest'),
  schedule := '35 */2 * * *'
);
;
