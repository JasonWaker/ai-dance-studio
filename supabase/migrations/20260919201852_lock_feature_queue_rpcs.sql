revoke all on function public.football_enqueue_sevenm_h2h(integer, integer) from public, anon, authenticated;
revoke all on function public.football_enqueue_sevenm_histories(integer, integer) from public, anon, authenticated;
grant execute on function public.football_enqueue_sevenm_h2h(integer, integer) to postgres, service_role;
grant execute on function public.football_enqueue_sevenm_histories(integer, integer) to postgres, service_role;;
