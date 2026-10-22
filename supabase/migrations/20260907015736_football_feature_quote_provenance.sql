alter table public.football_feature_observations
  add column source_platform text not null default 'legacy_normalized_feed',
  add column source_url text,
  add column market_summary jsonb not null default '{}';

alter table public.football_feature_observations
  drop constraint football_feature_observations_match_key_bookmaker_observed__key,
  add constraint football_feature_observations_source_observed_key
    unique (match_key, bookmaker, source_platform, observed_at);

alter table public.football_feature_signals
  add column quote_type text not null default 'bookmaker'
    check (quote_type in ('bookmaker', 'market_median')),
  add column source_platform text not null default 'legacy_normalized_feed',
  add column source_url text,
  add column trigger_price numeric,
  add column market_reference_price numeric;

create table public.football_feature_quotes (
  id uuid primary key default gen_random_uuid(),
  observation_id uuid not null references public.football_feature_observations(id) on delete cascade,
  match_key text not null references public.football_feature_matches(match_key),
  quote_type text not null check (quote_type in ('bookmaker', 'market_median')),
  bookmaker text not null,
  source_platform text not null,
  source_url text not null,
  observed_at timestamptz not null,
  opening_at timestamptz,
  home_handicap numeric,
  home_odds numeric,
  away_odds numeric,
  opening_home_handicap numeric,
  opening_home_odds numeric,
  opening_away_odds numeric,
  total_line numeric,
  over_odds numeric,
  under_odds numeric,
  raw_evidence jsonb not null default '{}',
  unique (observation_id, quote_type, bookmaker)
);

create index football_feature_quotes_match_idx
  on public.football_feature_quotes(match_key, observed_at desc);
create index football_feature_quotes_bookmaker_idx
  on public.football_feature_quotes(bookmaker, quote_type);

alter table public.football_feature_quotes enable row level security;
revoke all on table public.football_feature_quotes from anon, authenticated;
grant all on table public.football_feature_quotes to service_role;

create view public.football_feature_stats_by_bookmaker
with (security_invoker = true) as
select
  s.quote_type,
  s.bookmaker,
  s.kind,
  count(*) as samples,
  count(distinct s.match_key) as matches,
  count(*) filter (where s.value is not null) as settled,
  count(*) filter (where s.outcome is null) as pending,
  count(*) filter (where s.value = 1) as wins,
  count(*) filter (where s.value = 0.5) as half_wins,
  count(*) filter (where s.value = 0) as pushes,
  count(*) filter (where s.value = -0.5) as half_losses,
  count(*) filter (where s.value = -1) as losses,
  round(
    100.0 * count(*) filter (
      where case when s.kind = 'losing_streak' then s.value < 0 else s.value > 0 end
    ) / nullif(count(*) filter (where s.value is not null), 0),
    2
  ) as hit_rate
from public.football_feature_signals s
group by s.quote_type, s.bookmaker, s.kind;

revoke all on table public.football_feature_stats_by_bookmaker from anon, authenticated;
grant select on table public.football_feature_stats_by_bookmaker to service_role;

create or replace function public.football_feature_commit(
  p_run uuid,
  p_items jsonb,
  p_results jsonb
) returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  i jsonb;
  s jsonb;
  q jsonb;
  r jsonb;
  observation_id uuid;
  n integer := 0;
  changed integer := 0;
begin
  for i in select value from jsonb_array_elements(p_items) loop
    insert into football_feature_matches(
      match_key, kickoff_at, competition_name, home_team, away_team
    ) values (
      i->>'match_key', (i->>'kickoff_at')::timestamptz,
      i->>'competition_name', i->>'home_team', i->>'away_team'
    )
    on conflict(match_key) do update
      set kickoff_at = excluded.kickoff_at, last_seen_at = now();

    insert into football_feature_observations(
      run_id, match_key, bookmaker, observed_at, payload, all_five,
      source_platform, source_url, market_summary
    ) values (
      p_run, i->>'match_key', i->>'bookmaker', (i->>'observed_at')::timestamptz,
      i->'observation', coalesce((i->>'all_five')::boolean, false),
      i->>'source_platform', i->>'source_url', coalesce(i->'market_summary', '{}'::jsonb)
    )
    on conflict(match_key, bookmaker, source_platform, observed_at) do update
      set market_summary = excluded.market_summary
    returning id into observation_id;

    for q in select value from jsonb_array_elements(coalesce(i->'quotes', '[]'::jsonb)) loop
      insert into football_feature_quotes(
        observation_id, match_key, quote_type, bookmaker, source_platform,
        source_url, observed_at, opening_at, home_handicap, home_odds,
        away_odds, opening_home_handicap, opening_home_odds,
        opening_away_odds, total_line, over_odds, under_odds, raw_evidence
      ) values (
        observation_id, i->>'match_key', q->>'quote_type', q->>'bookmaker',
        i->>'source_platform', i->>'source_url', (i->>'observed_at')::timestamptz,
        nullif(q->>'opening_at', '')::timestamptz,
        nullif(q->>'home_handicap', '')::numeric,
        nullif(q->>'home_odds', '')::numeric,
        nullif(q->>'away_odds', '')::numeric,
        nullif(q->>'opening_home_handicap', '')::numeric,
        nullif(q->>'opening_home_odds', '')::numeric,
        nullif(q->>'opening_away_odds', '')::numeric,
        nullif(q->>'total_line', '')::numeric,
        nullif(q->>'over_odds', '')::numeric,
        nullif(q->>'under_odds', '')::numeric,
        q
      ) on conflict do nothing;
    end loop;

    for s in select value from jsonb_array_elements(i->'signals') loop
      insert into football_feature_signals(
        match_key, bookmaker, kind, side, trigger_at, handicap, total_line,
        evidence, quote_type, source_platform, source_url, trigger_price,
        market_reference_price
      ) values (
        i->>'match_key', i->>'bookmaker', s->>'kind', s->>'side',
        (i->>'observed_at')::timestamptz, nullif(s->>'handicap', '')::numeric,
        nullif(s->>'total_line', '')::numeric, s->'evidence',
        i->>'quote_type', i->>'source_platform', i->>'source_url',
        nullif(s->>'trigger_price', '')::numeric,
        nullif(s->>'market_reference_price', '')::numeric
      ) on conflict do nothing;
      get diagnostics changed = row_count;
      n := n + changed;
    end loop;
  end loop;

  for r in select value from jsonb_array_elements(p_results) loop
    update football_feature_signals
      set outcome = r->>'outcome', value = (r->>'value')::numeric, settled_at = now()
      where id = (r->>'id')::uuid;
    update football_feature_matches
      set status = r->'result'->>'status', result = r->'result'
      where match_key = r->>'match_key';
  end loop;

  return jsonb_build_object(
    'new_signals', n,
    'settled', jsonb_array_length(p_results)
  );
end
$$;

revoke execute on function public.football_feature_commit(uuid, jsonb, jsonb)
  from public, anon, authenticated;
grant execute on function public.football_feature_commit(uuid, jsonb, jsonb)
  to service_role;
;
