create or replace function public.normalize_goal_lite_competition_code()
returns trigger
language plpgsql
set search_path = public
as $$
declare normalized text;
begin
  normalized := case upper(coalesce(new.competition_code,new.league_code))
    when 'EPL' then 'ENG_PL' when 'PREMIER_LEAGUE' then 'ENG_PL'
    when 'LALIGA' then 'ESP_LL' when 'LA_LIGA' then 'ESP_LL'
    when 'SERIE_A' then 'ITA_SA'
    when 'BUNDESLIGA' then 'GER_BL'
    when 'LIGUE_1' then 'FRA_L1'
    when 'ELITESERIEN' then 'NOR_EL'
    when 'EREDIVISIE' then 'NED_ED'
    when 'EERSTE_DIVISIE' then 'NED_EE'
    when 'BUNDESLIGA_2' then 'GER_2BL' when '2_BUNDESLIGA' then 'GER_2BL'
    when 'CSL' then 'CHN_CSL'
    when 'J1_LEAGUE' then 'JPN_J1'
    when 'K_LEAGUE_1' then 'KOR_K1'
    when 'ALLSVENSKAN' then 'SWE_ALL'
    when 'SUPER_LIG' then 'TUR_SL'
    when 'SWISS_SUPER_LEAGUE' then 'SUI_SL'
    when 'A_LEAGUE' then 'AUS_ALM'
    when 'UCL' then 'UEFA_UCL'
    when 'ACLE' then 'AFC_ACLE'
    when 'UEL' then 'UEFA_UEL'
    when 'UECL' then 'UEFA_UECL'
    when 'UNL' then 'UEFA_UNL'
    when 'WORLD_CUP' then 'FIFA_WC'
    when 'MLS' then 'USA_MLS'
    when 'LIGA_MX' then 'MEX_LMX'
    else upper(coalesce(new.competition_code,new.league_code))
  end;
  new.league_code := normalized;
  new.competition_code := normalized;
  return new;
end $$;

create trigger normalize_goal_lite_competition_code_trigger
before insert or update of league_code,competition_code on public.goal_lite_daily_picks
for each row execute function public.normalize_goal_lite_competition_code();

update public.goal_lite_daily_picks set competition_code=competition_code;

alter table public.goal_lite_daily_picks
  add constraint goal_lite_daily_picks_competition_code_check
  check (competition_code in (
    'ENG_PL','ESP_LL','ITA_SA','GER_BL','FRA_L1','NOR_EL','NED_ED','NED_EE','GER_2BL','CHN_CSL','JPN_J1','KOR_K1',
    'SWE_ALL','TUR_SL','SUI_SL','AUS_ALM','UEFA_UCL','AFC_ACLE','UEFA_UEL','UEFA_UECL','UEFA_UNL','FIFA_WC','USA_MLS','MEX_LMX'
  )) not valid;
;
