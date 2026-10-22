-- Independent historical head-to-head high-over module.
-- Existing Plus8 tables and statistics are intentionally not referenced.

alter table public.h2h_high_over_matches
  add column if not exists odds_updated_at timestamptz;

alter table public.h2h_high_over_matches
  add constraint h2h_high_over_matches_fixed_sample_size
    check (h2h_sample_size = 6),
  add constraint h2h_high_over_matches_qualified_over_count
    check (h2h_over_count between 5 and 6 and h2h_over_count <= h2h_sample_size),
  add constraint h2h_high_over_matches_results_array
    check (jsonb_typeof(h2h_results) = 'array'),
  add constraint h2h_high_over_matches_scores_nonnegative
    check (
      (home_score is null or home_score >= 0)
      and (away_score is null or away_score >= 0)
      and (total_goals is null or total_goals >= 0)
    ),
  add constraint h2h_high_over_matches_quarter_line
    check (ou_line is null or (ou_line > 0 and mod(ou_line * 4, 1) = 0)),
  add constraint h2h_high_over_matches_settlement_consistency
    check (
      status <> 'settled'
      or (
        home_score is not null
        and away_score is not null
        and total_goals = home_score + away_score
        and settlement_line is not null
        and settlement_result is not null
        and settled_at is not null
      )
    );

create index if not exists h2h_high_over_matches_competition_idx
  on public.h2h_high_over_matches (competition_name);
create index if not exists h2h_high_over_matches_rate_idx
  on public.h2h_high_over_matches (h2h_over_rate desc);

create or replace function public.h2h_high_over_touch_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists h2h_high_over_matches_touch_updated_at on public.h2h_high_over_matches;
create trigger h2h_high_over_matches_touch_updated_at
before update on public.h2h_high_over_matches
for each row execute function public.h2h_high_over_touch_updated_at();

create or replace function public.h2h_high_over_upsert(p_payload jsonb)
returns public.h2h_high_over_matches
language plpgsql
security invoker
set search_path = ''
as $$
declare
  saved public.h2h_high_over_matches;
begin
  insert into public.h2h_high_over_matches (
    match_key, scan_batch_id, scanned_at, kickoff_at,
    competition_name, competition_country, competition_level,
    home_team, away_team, source_match_id,
    ou_line, over_odds, under_odds, odds_source, odds_updated_at,
    h2h_sample_size, h2h_over_count, h2h_over_rate,
    over_rate_basis, h2h_results, h2h_source
  ) values (
    btrim(p_payload->>'match_key'), nullif(btrim(p_payload->>'scan_batch_id'), ''),
    coalesce((p_payload->>'scanned_at')::timestamptz, now()),
    (p_payload->>'kickoff_at')::timestamptz,
    btrim(p_payload->>'competition_name'), nullif(btrim(p_payload->>'competition_country'), ''),
    nullif(btrim(p_payload->>'competition_level'), ''),
    btrim(p_payload->>'home_team'), btrim(p_payload->>'away_team'),
    nullif(btrim(p_payload->>'source_match_id'), ''),
    nullif(p_payload->>'ou_line', '')::numeric,
    nullif(p_payload->>'over_odds', '')::numeric,
    nullif(p_payload->>'under_odds', '')::numeric,
    nullif(btrim(p_payload->>'odds_source'), ''),
    case when p_payload ? 'ou_line' or p_payload ? 'over_odds' or p_payload ? 'under_odds' then now() else null end,
    (p_payload->>'h2h_sample_size')::smallint,
    (p_payload->>'h2h_over_count')::smallint,
    (p_payload->>'h2h_over_rate')::numeric,
    p_payload->>'over_rate_basis', coalesce(p_payload->'h2h_results', '[]'::jsonb),
    nullif(btrim(p_payload->>'h2h_source'), '')
  )
  on conflict (match_key) do update set
    scan_batch_id = excluded.scan_batch_id,
    scanned_at = excluded.scanned_at,
    kickoff_at = excluded.kickoff_at,
    competition_name = excluded.competition_name,
    competition_country = excluded.competition_country,
    competition_level = excluded.competition_level,
    home_team = excluded.home_team,
    away_team = excluded.away_team,
    source_match_id = excluded.source_match_id,
    ou_line = case
      when h2h_high_over_matches.status = 'settled' then h2h_high_over_matches.ou_line
      else coalesce(excluded.ou_line, h2h_high_over_matches.ou_line)
    end,
    over_odds = case when h2h_high_over_matches.status = 'settled' then h2h_high_over_matches.over_odds else excluded.over_odds end,
    under_odds = case when h2h_high_over_matches.status = 'settled' then h2h_high_over_matches.under_odds else excluded.under_odds end,
    odds_source = case when h2h_high_over_matches.status = 'settled' then h2h_high_over_matches.odds_source else excluded.odds_source end,
    odds_updated_at = case when h2h_high_over_matches.status = 'settled' then h2h_high_over_matches.odds_updated_at else excluded.odds_updated_at end,
    h2h_sample_size = excluded.h2h_sample_size,
    h2h_over_count = excluded.h2h_over_count,
    h2h_over_rate = excluded.h2h_over_rate,
    over_rate_basis = excluded.over_rate_basis,
    h2h_results = excluded.h2h_results,
    h2h_source = excluded.h2h_source
  returning * into saved;

  return saved;
end;
$$;

create or replace function public.h2h_high_over_settle(
  p_match_key text,
  p_home_score integer,
  p_away_score integer,
  p_result_source text
)
returns public.h2h_high_over_matches
language plpgsql
security invoker
set search_path = ''
as $$
declare
  target public.h2h_high_over_matches;
  goals integer;
  line_fraction numeric;
  result_value text;
begin
  select * into target
  from public.h2h_high_over_matches
  where match_key = p_match_key
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'High-over match not found';
  end if;
  if target.status = 'settled' then
    return target;
  end if;
  if target.status = 'cancelled' then
    raise exception using errcode = 'P0001', message = 'Cancelled match cannot be settled';
  end if;
  if p_home_score < 0 or p_away_score < 0 then
    raise exception using errcode = '22023', message = 'Scores must be non-negative';
  end if;
  if target.ou_line is null then
    raise exception using errcode = 'P0001', message = '待补结算盘口';
  end if;

  goals := p_home_score + p_away_score;
  line_fraction := target.ou_line - floor(target.ou_line);

  result_value := case
    when line_fraction = 0 and goals > target.ou_line then 'OVER'
    when line_fraction = 0 and goals = target.ou_line then 'PUSH'
    when line_fraction = 0 then 'UNDER'
    when line_fraction = 0.5 and goals > target.ou_line then 'OVER'
    when line_fraction = 0.5 then 'UNDER'
    when line_fraction = 0.25 and goals > floor(target.ou_line) then 'OVER'
    when line_fraction = 0.25 and goals = floor(target.ou_line) then 'HALF_UNDER'
    when line_fraction = 0.25 then 'UNDER'
    when line_fraction = 0.75 and goals > ceil(target.ou_line) then 'OVER'
    when line_fraction = 0.75 and goals = ceil(target.ou_line) then 'HALF_OVER'
    when line_fraction = 0.75 then 'UNDER'
    else null
  end;

  if result_value is null then
    raise exception using errcode = '22023', message = 'Unsupported Asian total line';
  end if;

  update public.h2h_high_over_matches set
    status = 'settled',
    home_score = p_home_score,
    away_score = p_away_score,
    total_goals = goals,
    settlement_line = target.ou_line,
    settlement_result = result_value,
    over_hit = case when result_value in ('OVER', 'HALF_OVER') then true when result_value = 'PUSH' then null else false end,
    settled_at = now(),
    result_source = btrim(p_result_source)
  where id = target.id
  returning * into target;

  return target;
end;
$$;

create or replace view public.h2h_high_over_dashboard
with (security_invoker = true)
as
select
  id, match_key, scan_batch_id, scanned_at, kickoff_at,
  kickoff_at at time zone 'Asia/Shanghai' as kickoff_beijing,
  competition_name, competition_country, competition_level,
  home_team, away_team, ou_line, over_odds, under_odds,
  h2h_sample_size, h2h_over_count, h2h_over_rate, h2h_results,
  over_rate_basis, odds_source, h2h_source, source_match_id,
  status, home_score, away_score, total_goals, settlement_line,
  settlement_result, over_hit, settled_at, result_source,
  updated_at, created_at, odds_updated_at
from public.h2h_high_over_matches
order by kickoff_at desc;

create or replace view public.h2h_high_over_stats
with (security_invoker = true)
as
select
  count(*) filter (where status = 'settled') as settled_matches,
  count(*) filter (where status = 'settled' and settlement_result = 'OVER') as full_over,
  count(*) filter (where status = 'settled' and settlement_result = 'HALF_OVER') as half_over,
  count(*) filter (where status = 'settled' and settlement_result = 'PUSH') as push,
  count(*) filter (where status = 'settled' and settlement_result = 'HALF_UNDER') as half_under,
  count(*) filter (where status = 'settled' and settlement_result = 'UNDER') as full_under,
  round(100.0 * (
    count(*) filter (where status = 'settled' and settlement_result = 'OVER')
    + 0.5 * count(*) filter (where status = 'settled' and settlement_result = 'HALF_OVER')
  ) / nullif(count(*) filter (where status = 'settled' and settlement_result in ('OVER','HALF_OVER','HALF_UNDER','UNDER')), 0), 2) as weighted_over_hit_rate,
  round(100.0 * count(*) filter (where status = 'settled' and settlement_result in ('OVER','HALF_OVER'))
    / nullif(count(*) filter (where status = 'settled' and settlement_result in ('OVER','HALF_OVER','HALF_UNDER','UNDER')), 0), 2) as simple_over_hit_rate,
  count(*) as total_matches,
  count(*) filter (where status = 'scheduled') as scheduled_matches,
  count(*) filter (where scanned_at at time zone 'Asia/Shanghai' >= date_trunc('day', now() at time zone 'Asia/Shanghai')) as today_scanned,
  count(*) filter (where h2h_over_count = 5) as h2h_83_count,
  count(*) filter (where h2h_over_count = 6) as h2h_100_count,
  round(100.0 * (
    count(*) filter (where status = 'settled' and h2h_over_count = 6 and settlement_result = 'OVER')
    + 0.5 * count(*) filter (where status = 'settled' and h2h_over_count = 6 and settlement_result = 'HALF_OVER')
  ) / nullif(count(*) filter (where status = 'settled' and h2h_over_count = 6 and settlement_result in ('OVER','HALF_OVER','HALF_UNDER','UNDER')), 0), 2) as h2h_100_weighted_over_hit_rate
from public.h2h_high_over_matches;

create or replace view public.h2h_high_over_stats_by_line
with (security_invoker = true)
as
select
  settlement_line as ou_line,
  count(*)::bigint as sample_count,
  count(*) filter (where settlement_result = 'OVER') as full_over,
  count(*) filter (where settlement_result = 'HALF_OVER') as half_over,
  count(*) filter (where settlement_result = 'PUSH') as push,
  count(*) filter (where settlement_result = 'HALF_UNDER') as half_under,
  count(*) filter (where settlement_result = 'UNDER') as full_under,
  round(100.0 * (
    count(*) filter (where settlement_result = 'OVER')
    + 0.5 * count(*) filter (where settlement_result = 'HALF_OVER')
  ) / nullif(count(*) filter (where settlement_result in ('OVER','HALF_OVER','HALF_UNDER','UNDER')), 0), 2) as weighted_over_hit_rate
from public.h2h_high_over_matches
where status = 'settled' and settlement_line is not null
group by settlement_line;

create or replace view public.h2h_high_over_stats_by_h2h_rate
with (security_invoker = true)
as
select
  case when h2h_over_count = 6 then '6/6' else '5/6' end as h2h_condition,
  case when h2h_over_count = 6 then 100.0::numeric else round(500.0 / 6, 2) end as h2h_over_rate,
  count(*) filter (where status = 'settled') as sample_count,
  count(*) filter (where status = 'settled' and settlement_result = 'OVER') as full_over,
  count(*) filter (where status = 'settled' and settlement_result = 'HALF_OVER') as half_over,
  count(*) filter (where status = 'settled' and settlement_result = 'PUSH') as push,
  count(*) filter (where status = 'settled' and settlement_result = 'HALF_UNDER') as half_under,
  count(*) filter (where status = 'settled' and settlement_result = 'UNDER') as full_under,
  round(100.0 * (
    count(*) filter (where status = 'settled' and settlement_result = 'OVER')
    + 0.5 * count(*) filter (where status = 'settled' and settlement_result = 'HALF_OVER')
  ) / nullif(count(*) filter (where status = 'settled' and settlement_result in ('OVER','HALF_OVER','HALF_UNDER','UNDER')), 0), 2) as weighted_over_hit_rate
from public.h2h_high_over_matches
where h2h_over_count in (5, 6)
group by h2h_over_count;

revoke all on table public.h2h_high_over_matches from public, anon, authenticated;
grant select on table public.h2h_high_over_matches to anon, authenticated;
grant all on table public.h2h_high_over_matches to service_role;

revoke all on public.h2h_high_over_dashboard from public, anon, authenticated;
revoke all on public.h2h_high_over_stats from public, anon, authenticated;
revoke all on public.h2h_high_over_stats_by_line from public, anon, authenticated;
revoke all on public.h2h_high_over_stats_by_h2h_rate from public, anon, authenticated;
grant select on public.h2h_high_over_dashboard, public.h2h_high_over_stats,
  public.h2h_high_over_stats_by_line, public.h2h_high_over_stats_by_h2h_rate
to anon, authenticated, service_role;

revoke execute on function public.h2h_high_over_touch_updated_at() from public, anon, authenticated;
revoke execute on function public.h2h_high_over_upsert(jsonb) from public, anon, authenticated;
revoke execute on function public.h2h_high_over_settle(text, integer, integer, text) from public, anon, authenticated;
grant execute on function public.h2h_high_over_touch_updated_at() to service_role;
grant execute on function public.h2h_high_over_upsert(jsonb) to service_role;
grant execute on function public.h2h_high_over_settle(text, integer, integer, text) to service_role;

comment on table public.h2h_high_over_matches is
  'Independent H2H high-over scanner records. Never contributes to Plus8 model performance.';
comment on column public.h2h_high_over_matches.ou_line is
  'Original pre-match Asian total line recorded by the scan and frozen after settlement.';
comment on view public.h2h_high_over_stats is
  'Independent high-over performance; percentages are 0-100 and PUSH is excluded from hit-rate denominators.';
;
