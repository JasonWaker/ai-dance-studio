create or replace function plus8_internal.settle_confirmed_results()
returns jsonb
language sql
as $$
  select plus8_internal.settle_confirmed_results(
    now(),
    interval '3 hours',
    interval '14 days',
    500
  );
$$;;
