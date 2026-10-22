do $$
declare definition text;
begin
  definition := pg_get_viewdef('public.football_feature_stats'::regclass, true);
  if (length(definition) - length(replace(definition, 's.value IS NOT NULL', ''))) / length('s.value IS NOT NULL') <> 5 then
    raise exception 'football_feature_stats definition changed; inspect before updating streak denominator';
  end if;
  definition := replace(definition, 's.value IS NOT NULL',
    's.value IS NOT NULL AND (k.kind NOT IN (''losing_streak'', ''over_streak'') OR s.value <> 0)');
  execute 'create or replace view public.football_feature_stats with (security_invoker = true) as ' || definition;

  definition := pg_get_viewdef('public.football_feature_stats_by_bookmaker'::regclass, true);
  if (length(definition) - length(replace(definition, 'value IS NOT NULL', ''))) / length('value IS NOT NULL') <> 4 then
    raise exception 'football_feature_stats_by_bookmaker definition changed; inspect before updating streak denominator';
  end if;
  definition := replace(definition, 'value IS NOT NULL',
    'value IS NOT NULL AND (kind NOT IN (''losing_streak'', ''over_streak'') OR value <> 0)');
  execute 'create or replace view public.football_feature_stats_by_bookmaker with (security_invoker = true) as ' || definition;
end $$;
revoke all on table public.football_feature_stats from anon, authenticated;
revoke all on table public.football_feature_stats_by_bookmaker from anon, authenticated;
grant select on table public.football_feature_stats to service_role;
grant select on table public.football_feature_stats_by_bookmaker to service_role;;
