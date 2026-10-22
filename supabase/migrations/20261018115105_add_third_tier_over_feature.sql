begin;
do $migration$
declare definition text; view_name text;
begin
  select pg_get_constraintdef(oid) into definition
  from pg_constraint
  where conrelid='public.football_feature_signals'::regclass
    and conname='football_feature_signals_kind_check';
  if definition is null or position('total_375' in definition)=0 then
    raise exception 'Missing expected feature kind constraint';
  end if;
  if position('third_tier_over' in definition)=0 then
    definition:=replace(definition,'''total_375''::text','''total_375''::text, ''third_tier_over''::text');
    alter table public.football_feature_signals drop constraint football_feature_signals_kind_check;
    execute 'alter table public.football_feature_signals add constraint football_feature_signals_kind_check '||definition;
  end if;

  foreach view_name in array array['football_feature_stats','football_feature_stats_by_bookmaker'] loop
    definition:=pg_get_viewdef(('public.'||view_name)::regclass,true);
    if position('third_tier_over' in definition)>0 then continue; end if;
    if view_name='football_feature_stats' then
      definition:=replace(definition,'(''total_375''::text), (''total_425''::text)','(''total_375''::text), (''third_tier_over''::text), (''total_425''::text)');
    end if;
    definition:=replace(definition,'''total_375''::text, ''total_35''::text','''total_375''::text, ''third_tier_over''::text, ''total_35''::text');
    definition:=replace(definition,'''total_375''::text, ''losing_streak''::text','''total_375''::text, ''third_tier_over''::text, ''losing_streak''::text');
    execute format('create or replace view public.%I with (security_invoker=true) as %s',view_name,definition);
  end loop;
end $migration$;
commit;;
