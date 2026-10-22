-- Preserve verification evidence supplied by the scanner before the generic
-- source-normalization trigger writes the canonical JSON fields.
create or replace function public.football_feature_normalize_source_metadata()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  history_label text;
  evidence_count integer;
  evidence_status text;
  evidence_eligible boolean;
begin
  evidence_count := coalesce(nullif(new.evidence->>'source_count', '')::integer, new.source_count, 1);
  evidence_status := nullif(new.evidence->>'verification_status', '');
  evidence_eligible := nullif(new.evidence->>'eligible_for_official_stats', '')::boolean;

  new.source_count := greatest(1, evidence_count);
  new.verification_status := coalesce(evidence_status, nullif(new.verification_status, ''), 'single_source');
  new.included_in_stats := coalesce(evidence_eligible, new.included_in_stats, false);

  if new.kind in ('losing_streak', 'over_streak')
     and new.verification_status = 'history_verified'
     and jsonb_typeof(new.evidence->'history_sources') = 'array'
     and jsonb_array_length(new.evidence->'history_sources') >= 2 then
    select string_agg(
      case value
        when '7M historical results and closing lines' then '7M 历史赛果与收盘'
        when 'LiveScore result archive' then 'LiveScore 赛果档案'
        when 'ESPN result archive' then 'ESPN 赛果档案'
        else value
      end,
      ' + ' order by ordinality
    )
    into history_label
    from jsonb_array_elements_text(new.evidence->'history_sources')
         with ordinality as src(value, ordinality);

    new.source_platform := coalesce(nullif(history_label, ''), new.source_platform);
    new.included_in_stats := true;
  end if;

  new.evidence :=
    jsonb_set(
      jsonb_set(
        jsonb_set(
          coalesce(new.evidence, '{}'::jsonb),
          '{source_count}', to_jsonb(new.source_count), true
        ),
        '{verification_status}', to_jsonb(new.verification_status), true
      ),
      '{eligible_for_official_stats}', to_jsonb(coalesce(new.included_in_stats, false)), true
    );

  return new;
exception when invalid_text_representation or numeric_value_out_of_range then
  new.source_count := greatest(1, coalesce(new.source_count, 1));
  new.verification_status := coalesce(nullif(new.verification_status, ''), 'single_source');
  new.included_in_stats := coalesce(new.included_in_stats, false);
  return new;
end
$$;

-- Recompute the verification tier for the newly backfilled feature from the
-- exact stored quote cohort that produced each signal.
with quote_counts as (
  select match_key, observed_at, count(distinct bookmaker)::integer as source_count
  from public.football_feature_quotes
  where quote_type = 'bookmaker'
  group by match_key, observed_at
), candidates as (
  select
    q.match_key,
    q.bookmaker,
    q.quote_type,
    case
      when q.quote_type = 'market_median' then greatest(3, coalesce(qc.source_count, 3))
      else greatest(1, coalesce(qc.source_count, 1))
    end as source_count,
    row_number() over (
      partition by q.match_key, q.bookmaker
      order by q.observed_at, q.id
    ) as candidate_order
  from public.football_feature_quotes q
  join public.football_feature_matches m using (match_key)
  left join quote_counts qc using (match_key, observed_at)
  where q.home_handicap is not null
    and q.opening_home_handicap is not null
    and q.home_handicap <> 0
    and abs(q.home_handicap) - abs(q.opening_home_handicap) >= 0.5
    and (q.opening_home_handicap = 0 or sign(q.opening_home_handicap) = sign(q.home_handicap))
    and q.opening_at is not null
    and q.opening_at <= q.observed_at
    and q.observed_at < m.kickoff_at
), corrected as (
  select
    match_key,
    bookmaker,
    quote_type,
    source_count,
    (quote_type = 'market_median' or (quote_type = 'bookmaker' and source_count >= 3)) as eligible
  from candidates
  where candidate_order = 1
)
update public.football_feature_signals s
set source_count = c.source_count,
    verification_status = case when c.eligible then 'cross_verified' else 'single_source' end,
    included_in_stats = c.eligible,
    evidence = s.evidence || jsonb_build_object(
      'source_count', c.source_count,
      'verification_status', case when c.eligible then 'cross_verified' else 'single_source' end,
      'eligible_for_official_stats', c.eligible
    )
from corrected c
where s.kind = 'handicap_rise_05'
  and s.match_key = c.match_key
  and s.bookmaker = c.bookmaker;

comment on function public.football_feature_normalize_source_metadata() is
  'Canonicalizes source metadata while preserving scanner-supplied source count, verification tier, and official-stat eligibility.';
;
