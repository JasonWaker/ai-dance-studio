create or replace function public.football_feature_refresh_history_evidence(p_items jsonb)
returns integer
language plpgsql
set search_path = public, pg_temp
as $$
declare
  i jsonb;
  s jsonb;
  changed integer := 0;
  total_changed integer := 0;
begin
  for i in select value from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    for s in select value from jsonb_array_elements(coalesce(i->'signals', '[]'::jsonb)) loop
      if s->>'kind' in ('losing_streak', 'over_streak')
         and coalesce((s->'evidence'->>'source_count')::integer, 1) >= 2 then
        update public.football_feature_signals
        set evidence = s->'evidence'
        where match_key = i->>'match_key'
          and bookmaker = i->>'bookmaker'
          and kind = s->>'kind'
          and side = s->>'side'
          and source_count < coalesce((s->'evidence'->>'source_count')::integer, 1);
        get diagnostics changed = row_count;
        total_changed := total_changed + changed;
      end if;
    end loop;
  end loop;
  return total_changed;
end
$$;

revoke all on function public.football_feature_refresh_history_evidence(jsonb) from public;
grant execute on function public.football_feature_refresh_history_evidence(jsonb) to service_role;

comment on function public.football_feature_refresh_history_evidence(jsonb) is
  'Upgrades existing streak signals only when a new scan has more independently matched history sources.';
;
