-- New live-only 3.75 water family. Preserve deployed view identity filters and grants.
begin;
do $migration$
declare definition text; view_name text;
begin
 select pg_get_constraintdef(oid) into definition from pg_constraint
 where conrelid='public.football_feature_signals'::regclass and conname='football_feature_signals_kind_check';
 if definition is null or position('total_35' in definition)=0 then raise exception 'Missing expected kind constraint'; end if;
 if position('total_375' in definition)>0 then raise exception 'total_375 already exists'; end if;
 definition:=replace(definition,'''total_35''::text','''total_35''::text, ''total_375''::text');
 alter table public.football_feature_signals drop constraint football_feature_signals_kind_check;
 execute 'alter table public.football_feature_signals add constraint football_feature_signals_kind_check '||definition;
 foreach view_name in array array['football_feature_stats','football_feature_stats_by_bookmaker'] loop
  definition:=pg_get_viewdef(('public.'||view_name)::regclass,true);
  if position('''total_30''::text,' in definition)=0 then raise exception 'Missing water-family anchor in %',view_name; end if;
  definition:=replace(definition,'(''total_35''::text)','(''total_35''::text), (''total_375''::text)');
  -- total_30 appears only in water-family / neutral exclusion arrays, never inverse-event CASE.
  definition:=replace(definition,'''total_30''::text,','''total_30''::text, ''total_375''::text,');
  execute format('create or replace view public.%I with (security_invoker=true) as %s',view_name,definition);
 end loop;
end $migration$;
commit;
;
