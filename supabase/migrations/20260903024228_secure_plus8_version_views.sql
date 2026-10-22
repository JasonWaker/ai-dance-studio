alter view public.plus8_pending_settlements set (security_invoker = true);
alter view public.plus8_settled_recommendations set (security_invoker = true);
alter view public.plus8_match_version_ledger set (security_invoker = true);
alter view public.plus8_version_comparison_stats set (security_invoker = true);;
