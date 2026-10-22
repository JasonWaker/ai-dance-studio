-- The English Nowgoal feed exposes a UTC wall clock without a timezone suffix.
-- Earlier scanner versions interpreted it as Asia/Shanghai and therefore stored
-- every Nowgoal fixture eight hours early. Correct the existing source-owned
-- rows and their immutable observation/favorite snapshots once.
update public.football_feature_matches
set kickoff_at = kickoff_at + interval '8 hours'
where match_key like 'nowgoal:%';

update public.football_feature_observations
set payload = jsonb_set(
  payload,
  '{kickoff_at}',
  to_jsonb((payload->>'kickoff_at')::timestamptz + interval '8 hours'),
  true
)
where match_key like 'nowgoal:%'
  and payload ? 'kickoff_at';

update public.match_favorites
set kickoff_at = kickoff_at + interval '8 hours',
    updated_at = now()
where match_key like 'nowgoal:%';;
