-- Two historical fixtures had source schedule disagreements in addition to
-- the UKT parser error. Nowgoal and an independent archive agree on 15:00 UTC
-- for 13617529 and 14:00 UTC for 13618081. Preserve the original time in the
-- prior correction audit; replace its target with the corroborated schedule.

update public.football_feature_matches m
set kickoff_at = v.verified_at,
    result = case when m.result is null then null else
      jsonb_set(
        jsonb_set(m.result, '{kickoff_at}', to_jsonb(v.verified_at::text)),
        '{finished_at}', to_jsonb((v.verified_at + interval '2 hours')::text)
      ) end
from (values
  ('oddstorm:13617529', '2026-09-30 17:00+00'::timestamptz, '2026-09-30 15:00+00'::timestamptz),
  ('oddstorm:13618081', '2026-10-01 14:30+00'::timestamptz, '2026-10-01 14:00+00'::timestamptz)
) as v(match_key, shifted_at, verified_at)
where m.match_key = v.match_key and m.kickoff_at = v.shifted_at;

update public.bet_records b set kickoff_at = v.verified_at
from (values
  ('oddstorm:13617529', '2026-09-30 17:00+00'::timestamptz, '2026-09-30 15:00+00'::timestamptz),
  ('oddstorm:13618081', '2026-10-01 14:30+00'::timestamptz, '2026-10-01 14:00+00'::timestamptz)
) as v(match_key, shifted_at, verified_at)
where b.match_key = v.match_key and b.kickoff_at = v.shifted_at;

update public.football_feature_source_identities s set kickoff_at = v.verified_at
from (values
  ('oddstorm:13617529', '2026-09-30 17:00+00'::timestamptz, '2026-09-30 15:00+00'::timestamptz),
  ('oddstorm:13618081', '2026-10-01 14:30+00'::timestamptz, '2026-10-01 14:00+00'::timestamptz)
) as v(match_key, shifted_at, verified_at)
where s.match_key = v.match_key and s.kickoff_at = v.shifted_at;

update public.football_feature_observations o
set payload = jsonb_set(o.payload, '{kickoff_at}', to_jsonb(v.verified_at::text))
from (values
  ('oddstorm:13617529', '2026-09-30 17:00+00'::timestamptz, '2026-09-30 15:00+00'::timestamptz),
  ('oddstorm:13618081', '2026-10-01 14:30+00'::timestamptz, '2026-10-01 14:00+00'::timestamptz)
) as v(match_key, shifted_at, verified_at)
where o.match_key = v.match_key
  and (o.payload->>'kickoff_at')::timestamptz = v.shifted_at;

update public.football_name_unresolved n set kickoff_at = v.verified_at
from (values
  ('oddstorm:13617529', '2026-09-30 17:00+00'::timestamptz, '2026-09-30 15:00+00'::timestamptz),
  ('oddstorm:13618081', '2026-10-01 14:30+00'::timestamptz, '2026-10-01 14:00+00'::timestamptz)
) as v(match_key, shifted_at, verified_at)
where n.match_key = v.match_key and n.kickoff_at = v.shifted_at;

update public.football_kickoff_time_corrections c
set new_kickoff_at = v.verified_at,
    reason = c.reason || '; independent Nowgoal and fixture archive override'
from (values
  ('oddstorm:13617529', '2026-09-30 15:00+00'::timestamptz),
  ('oddstorm:13618081', '2026-10-01 14:00+00'::timestamptz)
) as v(match_key, verified_at)
where c.dataset = 'football_feature_matches' and c.match_key = v.match_key
  and c.new_kickoff_at <> v.verified_at;
;
