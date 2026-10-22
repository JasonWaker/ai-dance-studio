-- Service-role-only projection for the authenticated custom-model dashboard.
-- Analysis data stays in the private ou_model schema; no public table or view is created.
create or replace function public.custom_model_predictions_dashboard()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select pg_catalog.jsonb_build_object(
    'generated_at', pg_catalog.now(),
    'models', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'model_slug', mv.model_slug,
        'version', mv.version,
        'display_name', mv.display_name,
        'status', mv.status,
        'parent_version', mv.parent_version,
        'validation_metrics', mv.validation_metrics,
        'created_at_utc', mv.created_at_utc,
        'promoted_at_utc', mv.promoted_at_utc,
        'notes', mv.notes
      ) order by mv.display_name, mv.created_at_utc desc)
      from ou_model.model_versions mv
    ), '[]'::jsonb),
    'analyses', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'analysis_key', a.analysis_key,
        'fixture_key', a.fixture_key,
        'analysis_type', a.analysis_type,
        'published_at_utc', a.published_at_utc,
        'model_name', a.model_name,
        'model_version', a.model_version,
        'summary', a.summary,
        'data_quality', a.data_quality,
        'limitations', a.limitations,
        'competition', f.competition,
        'season', f.season,
        'kickoff_utc', f.kickoff_utc,
        'home_team', f.home_team,
        'away_team', f.away_team,
        'match_url', f.match_url,
        'result', case when r.fixture_key is null then null else pg_catalog.jsonb_build_object(
          'home_goals', r.home_goals,
          'away_goals', r.away_goals,
          'result_source', r.result_source,
          'recorded_at_utc', r.recorded_at_utc
        ) end,
        'predictions', coalesce((
          select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
            'prediction_key', p.prediction_key,
            'market', p.market,
            'line', p.line,
            'selection', p.selection,
            'probability', p.probability,
            'probability_meaning', p.probability_meaning,
            'decimal_odds', p.decimal_odds,
            'decision', p.decision,
            'rationale', p.rationale
          ) order by p.prediction_key)
          from ou_model.predictions p
          where p.analysis_key = a.analysis_key
        ), '[]'::jsonb)
      ) order by f.kickoff_utc desc, a.published_at_utc desc)
      from ou_model.analyses a
      join ou_model.fixtures f on f.fixture_key = a.fixture_key
      left join ou_model.results r on r.fixture_key = f.fixture_key
    ), '[]'::jsonb)
  );
$$;

revoke all on function public.custom_model_predictions_dashboard() from public, anon, authenticated;
grant execute on function public.custom_model_predictions_dashboard() to service_role;

comment on function public.custom_model_predictions_dashboard() is
  'Service-role-only read projection for the authenticated 自有模型预测 page.';
;
