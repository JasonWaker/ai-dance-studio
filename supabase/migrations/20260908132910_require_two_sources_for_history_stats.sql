create or replace function public.set_football_feature_signal_verification()
returns trigger language plpgsql set search_path = public, pg_temp as $$
declare
  evidence_count integer := greatest(1, coalesce((new.evidence->>'source_count')::integer, 1));
  stats_eligible boolean := coalesce((new.evidence->>'eligible_for_official_stats')::boolean, true);
begin
  new.source_count := evidence_count;
  if not stats_eligible then
    new.verification_status := case when evidence_count >= 2 then 'cross_verified' else 'single_source' end;
    new.included_in_stats := false;
  elsif new.quote_type = 'market_median' or (new.quote_type = 'bookmaker' and evidence_count >= 3) then
    new.verification_status := 'cross_verified';
    new.included_in_stats := true;
  elsif new.quote_type = 'aggregate_reference' and new.kind in ('losing_streak', 'over_streak') and evidence_count >= 2 then
    new.verification_status := 'history_verified';
    new.included_in_stats := true;
  else
    new.verification_status := 'single_source';
    new.included_in_stats := false;
  end if;
  return new;
exception when invalid_text_representation or numeric_value_out_of_range then
  new.source_count := 1; new.verification_status := 'single_source'; new.included_in_stats := false; return new;
end
$$;
update public.football_feature_signals set evidence = evidence where quote_type = 'aggregate_reference' and kind in ('losing_streak','over_streak');
comment on function public.set_football_feature_signal_verification() is 'Single-source history remains visible but is excluded from official statistics; history needs two sources.';;
