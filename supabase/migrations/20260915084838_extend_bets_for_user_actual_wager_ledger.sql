
alter table public.bets
  alter column stake_units drop not null,
  add column if not exists currency text not null default 'CNY',
  add column if not exists odds_format text not null default 'decimal',
  add column if not exists bet_source text not null default 'user_actual',
  add column if not exists bet_status text not null default 'pending',
  add column if not exists raw_input text,
  add column if not exists notes text,
  add column if not exists settled_at timestamptz,
  add column if not exists idempotency_key text;

alter table public.bets
  drop constraint if exists bets_currency_check,
  add constraint bets_currency_check check (currency ~ '^[A-Z]{3}$'),
  drop constraint if exists bets_odds_format_check,
  add constraint bets_odds_format_check check (odds_format in ('decimal','hong_kong','malay','indo','american')),
  drop constraint if exists bets_bet_source_check,
  add constraint bets_bet_source_check check (bet_source in ('user_actual','imported_actual')),
  drop constraint if exists bets_bet_status_check,
  add constraint bets_bet_status_check check (bet_status in ('pending','settled','void','cancelled','cashed_out')),
  drop constraint if exists bets_positive_stake_check,
  add constraint bets_positive_stake_check check (stake is null or stake > 0),
  drop constraint if exists bets_positive_odds_check,
  add constraint bets_positive_odds_check check (odds > 1);

create unique index if not exists bets_idempotency_key_uidx
  on public.bets (idempotency_key)
  where idempotency_key is not null;

create index if not exists bets_user_placed_at_idx
  on public.bets (user_id, placed_at desc);

comment on column public.bets.bet_source is 'Actual wager provenance; user_actual means explicitly reported by the user and is separate from model recommendations.';
comment on column public.bets.bet_status is 'Lifecycle status for the actual wager.';
comment on column public.bets.idempotency_key is 'Stable key used to prevent accidental duplicate writes from repeated assistant runs.';
comment on column public.bets.raw_input is 'Original user wording preserved for later audit.';
;
