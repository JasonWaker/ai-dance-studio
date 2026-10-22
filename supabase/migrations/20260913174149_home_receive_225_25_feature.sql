-- Independent pre-match home +2.25/+2.5 Asian handicap feature. Existing
-- signals and recommendation snapshots are not rewritten.
alter table public.football_feature_signals
  drop constraint football_feature_signals_kind_check;

alter table public.football_feature_signals
  add constraint football_feature_signals_kind_check check
  (kind = any (array['away_zero','home_weak_zero','reversal','rise_075',
                     'handicap_rise_05','losing_streak','over_streak',
                     'weak_favorite','total_line_jump','home_receive_225_25']));

-- The statistics view enumerates feature names explicitly. Preserve every
-- existing rate calculation and add only the new row to the enumeration.
do $migration$
declare definition text;
begin
  definition := pg_get_viewdef('public.football_feature_stats'::regclass, true);
  if position($needle$('total_line_jump'::text)$needle$ in definition) = 0 then
    raise exception 'football_feature_stats definition changed; inspect before extending';
  end if;
  if position('home_receive_225_25' in definition) = 0 then
    definition := replace(definition,
      $needle$('total_line_jump'::text)$needle$,
      $replacement$('total_line_jump'::text), ('home_receive_225_25'::text)$replacement$);
    execute 'create or replace view public.football_feature_stats with (security_invoker = true) as ' || definition;
  end if;
end
$migration$;

revoke all on table public.football_feature_stats from anon, authenticated;
grant select on table public.football_feature_stats to service_role;
;
