begin;
do $migration$
declare definition text; view_name text;
begin
 foreach view_name in array array['football_feature_stats','football_feature_stats_by_bookmaker'] loop
  definition := pg_get_viewdef(('public.'||view_name)::regclass,true);
  -- Neutral denominator exclusion must not classify over-3 as an inverse feature.
  definition := replace(definition, 'ARRAY[''total_30''::text, ''losing_streak''::text, ''away_worm''::text]', 'ARRAY[''losing_streak''::text, ''away_worm''::text]');
  execute format('create or replace view public.%I with (security_invoker=true) as %s',view_name,definition);
 end loop;
end $migration$;
commit;
;
