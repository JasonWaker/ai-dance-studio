
alter table public.bets
  add column if not exists external_ticket_id text,
  add column if not exists source_platform text,
  add column if not exists potential_profit numeric,
  add column if not exists score_home_at_bet integer,
  add column if not exists score_away_at_bet integer;

alter table public.bets
  drop constraint if exists bets_potential_profit_check,
  add constraint bets_potential_profit_check check (potential_profit is null or potential_profit >= 0),
  drop constraint if exists bets_score_home_at_bet_check,
  add constraint bets_score_home_at_bet_check check (score_home_at_bet is null or score_home_at_bet >= 0),
  drop constraint if exists bets_score_away_at_bet_check,
  add constraint bets_score_away_at_bet_check check (score_away_at_bet is null or score_away_at_bet >= 0);

create unique index if not exists bets_user_platform_ticket_uidx
  on public.bets (user_id, source_platform, external_ticket_id)
  where external_ticket_id is not null;

comment on column public.bets.external_ticket_id is 'Bet slip/order identifier from the user-provided source.';
comment on column public.bets.potential_profit is 'Potential net profit shown on the bet slip, excluding returned stake.';
comment on column public.bets.score_home_at_bet is 'Home score visible when an in-play bet was placed.';
comment on column public.bets.score_away_at_bet is 'Away score visible when an in-play bet was placed.';
;
