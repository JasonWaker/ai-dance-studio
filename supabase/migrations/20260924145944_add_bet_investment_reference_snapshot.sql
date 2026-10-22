alter table public.bet_records
  add column if not exists investment_reference_snapshot jsonb;

alter table public.bet_records
  drop constraint if exists bet_records_investment_reference_snapshot_object;

alter table public.bet_records
  add constraint bet_records_investment_reference_snapshot_object
  check (
    investment_reference_snapshot is null
    or jsonb_typeof(investment_reference_snapshot) = 'object'
  );

comment on column public.bet_records.investment_reference_snapshot is
  'Exact actionable investment reference visible when the user placed the bet; kept as an immutable audit snapshot.';;
