-- Extend the existing water family without backfilling historical observations.
begin;
do $migration$
declare definition text; view_name text;
begin
  select pg_get_constraintdef(oid) into definition from pg_constraint
    where conrelid='public.football_feature_signals'::regclass and conname='football_feature_signals_kind_check';
  if definition is null or position('total_35' in definition)=0 then raise exception 'Missing expected kind constraint'; end if;
  definition := replace(definition, '''total_35''::text', '''total_30''::text, ''total_35''::text');
  alter table public.football_feature_signals drop constraint football_feature_signals_kind_check;
  execute 'alter table public.football_feature_signals add constraint football_feature_signals_kind_check ' || definition;
  foreach view_name in array array['football_feature_stats','football_feature_stats_by_bookmaker'] loop
    definition := pg_get_viewdef(('public.'||view_name)::regclass,true);
    -- VALUES tuple and water-family arrays are different syntactic contexts.
    definition := replace(definition, '(''total_35''::text)', '(''total_30''::text), (''total_35''::text)');
    definition := replace(definition, '''total_325''::text, ''total_35''::text', '''total_325''::text, ''total_30''::text, ''total_35''::text');
    -- For the integer 3.0 market a push is not a decisive settlement.
    definition := replace(definition, 'ARRAY[''losing_streak''::text', 'ARRAY[''total_30''::text, ''losing_streak''::text');
    execute format('create or replace view public.%I with (security_invoker=true) as %s',view_name,definition);
  end loop;
end $migration$;
comment on constraint football_feature_signals_kind_check on public.football_feature_signals is
 'Includes total_30: exact 3.0 median main line, over odds 1.65-2.00; 3 goals PUSH excluded from decisive rate.';
commit;
;
