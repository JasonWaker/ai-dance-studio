-- Mirror losing-streak persistence and statistics for Asian-handicap winning streaks.
alter table public.football_feature_signals
  drop constraint football_feature_signals_kind_check;
alter table public.football_feature_signals
  add constraint football_feature_signals_kind_check
  check (kind in (
    'away_zero', 'home_weak_zero', 'reversal', 'rise_075',
    'handicap_rise_05', 'losing_streak', 'winning_streak', 'over_streak',
    'weak_favorite', 'total_line_jump', 'home_receive_225_25'
  ));

do $$
declare
  definition text;
  old_kinds text := 'ARRAY[''losing_streak''::text, ''over_streak''::text]';
  new_kinds text := 'ARRAY[''losing_streak''::text, ''winning_streak''::text, ''over_streak''::text]';
begin
  definition := pg_get_viewdef('public.football_feature_stats'::regclass, true);
  if position('(''over_streak''::text)' in definition) = 0
     or position(old_kinds in definition) = 0 then
    raise exception 'football_feature_stats definition changed; inspect winning-streak migration';
  end if;
  definition := replace(definition, '(''over_streak''::text)',
    '(''over_streak''::text), (''winning_streak''::text)');
  definition := replace(definition, old_kinds, new_kinds);
  execute 'create or replace view public.football_feature_stats with (security_invoker = true) as ' || definition;

  definition := pg_get_viewdef('public.football_feature_stats_by_bookmaker'::regclass, true);
  if position(old_kinds in definition) = 0 then
    raise exception 'football_feature_stats_by_bookmaker definition changed; inspect winning-streak migration';
  end if;
  definition := replace(definition, old_kinds, new_kinds);
  execute 'create or replace view public.football_feature_stats_by_bookmaker with (security_invoker = true) as ' || definition;

  definition := pg_get_functiondef('public.football_feature_normalize_source_metadata()'::regprocedure);
  if position('new.kind in (''losing_streak'', ''over_streak'')' in definition) = 0 then
    raise exception 'football_feature_normalize_source_metadata definition changed';
  end if;
  definition := replace(definition,
    'new.kind in (''losing_streak'', ''over_streak'')',
    'new.kind in (''losing_streak'', ''winning_streak'', ''over_streak'')');
  execute definition;

  definition := pg_get_functiondef('public.football_feature_refresh_history_evidence(jsonb)'::regprocedure);
  if position('s->>''kind'' in (''losing_streak'', ''over_streak'')' in definition) = 0 then
    raise exception 'football_feature_refresh_history_evidence definition changed';
  end if;
  definition := replace(definition,
    's->>''kind'' in (''losing_streak'', ''over_streak'')',
    's->>''kind'' in (''losing_streak'', ''winning_streak'', ''over_streak'')');
  execute definition;

  definition := pg_get_functiondef('public.football_feature_commit(uuid,jsonb,jsonb)'::regprocedure);
  if position('s->>''kind'' in (''losing_streak'',''over_streak'')' in definition) = 0 then
    raise exception 'football_feature_commit definition changed';
  end if;
  definition := replace(definition,
    's->>''kind'' in (''losing_streak'',''over_streak'')',
    's->>''kind'' in (''losing_streak'',''winning_streak'',''over_streak'')');
  execute definition;
end $$;

revoke all on table public.football_feature_stats from anon, authenticated;
revoke all on table public.football_feature_stats_by_bookmaker from anon, authenticated;
grant select on table public.football_feature_stats to service_role;
grant select on table public.football_feature_stats_by_bookmaker to service_role;
;
