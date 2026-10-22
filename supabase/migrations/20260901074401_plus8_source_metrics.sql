-- Keep database scale, analysis history, and settled betting performance as separate metrics.
create or replace view public.plus8_match_analysis_source
with (security_invoker = true)
as
select
  m.id as match_id,
  coalesce(final_pre_match.analysis_source, latest_valid.analysis_source) as analysis_source,
  final_pre_match.id as final_pre_match_analysis_id,
  coalesce(final_pre_match.id, latest_valid.id) as source_analysis_id,
  case when final_pre_match.id is not null then 'final_pre_match' else 'latest_valid_analysis' end as source_resolution
from public.plus8_matches m
left join public.plus8_final_pre_match_analysis final_pre_match on final_pre_match.match_id = m.id
left join lateral (
  select a.id, a.analysis_source
  from public.plus8_analyses a
  where a.match_id = m.id and a.is_valid
  order by a.analysis_time desc, a.created_at desc, a.id desc
  limit 1
) latest_valid on final_pre_match.id is null
where coalesce(final_pre_match.analysis_source, latest_valid.analysis_source) is not null;

create or replace view public.plus8_source_scale_stats
with (security_invoker = true)
as
with sources(analysis_source) as (
  values ('manual_analysis'::text), ('system_scan'::text)
), match_counts as (
  select analysis_source, count(distinct match_id)::integer as match_count
  from public.plus8_match_analysis_source
  group by analysis_source
), analysis_counts as (
  select analysis_source, count(id)::integer as analysis_count
  from public.plus8_analyses
  group by analysis_source
)
select sources.analysis_source,
       coalesce(match_counts.match_count, 0) as match_count,
       coalesce(analysis_counts.analysis_count, 0) as analysis_count
from sources
left join match_counts using (analysis_source)
left join analysis_counts using (analysis_source);

create or replace view public.plus8_source_betting_stats
with (security_invoker = true)
as
select
  analysis_source,
  model_version,
  market_type,
  count(*)::integer as betting_sample_count,
  count(*) filter (where result = 'full_win')::integer as full_win_count,
  count(*) filter (where result = 'half_win')::integer as half_win_count,
  count(*) filter (where result = 'push')::integer as push_count,
  count(*) filter (where result = 'half_loss')::integer as half_loss_count,
  count(*) filter (where result = 'full_loss')::integer as full_loss_count,
  (count(*) filter (where result = 'full_win') + 0.5 * count(*) filter (where result = 'half_win'))::numeric
    / nullif(count(*) filter (where result in ('full_win','half_win','half_loss','full_loss')), 0) as weighted_hit_rate,
  coalesce(sum(units), 0::numeric) as total_risk_u,
  coalesce(sum(pnl_u), 0::numeric) as total_pnl_u,
  coalesce(sum(pnl_u), 0::numeric) / nullif(sum(units), 0::numeric) as roi
from public.plus8_settled_recommendations
where included_in_stats = true
group by analysis_source, model_version, market_type;

revoke all on public.plus8_match_analysis_source from public, anon, authenticated;
revoke all on public.plus8_source_scale_stats from public, anon, authenticated;
revoke all on public.plus8_source_betting_stats from public, anon, authenticated;
grant select on public.plus8_match_analysis_source to service_role;
grant select on public.plus8_source_scale_stats to service_role;
grant select on public.plus8_source_betting_stats to service_role;

comment on view public.plus8_match_analysis_source is
  'One row per match. Source comes from final pre-match analysis, or latest valid analysis for live-only matches.';
comment on view public.plus8_source_scale_stats is
  'Database scale by source: distinct match count and raw analysis row count.';
comment on view public.plus8_source_betting_stats is
  'Official settled betting samples only, grouped by source, model version, and market type.';;
