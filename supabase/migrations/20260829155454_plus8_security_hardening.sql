alter function public.plus8_component_outcome(numeric)
  set search_path = public;
alter function public.plus8_combine_component_outcomes(integer, integer)
  set search_path = public;
alter function public.plus8_settle_total(text, numeric, integer)
  set search_path = public;
alter function public.plus8_settle_handicap(text, numeric, integer, integer)
  set search_path = public;
alter function public.plus8_calculate_pnl(text, numeric, numeric)
  set search_path = public;

create index plus8_settlements_final_analysis_idx
  on public.plus8_settlements (final_analysis_id);
create index plus8_settlements_final_total_recommendation_idx
  on public.plus8_settlements (final_total_recommendation_id);
create index plus8_settlements_final_handicap_recommendation_idx
  on public.plus8_settlements (final_handicap_recommendation_id);;
