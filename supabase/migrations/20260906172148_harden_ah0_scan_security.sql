alter view public.ah0_away_water_dashboard set (security_invoker = true);
alter view public.ah0_away_water_stats set (security_invoker = true);
alter view public.ah0_away_water_stats_by_odds set (security_invoker = true);
alter function public.ah0_away_water_upsert(jsonb) set search_path = public, extensions;
;
