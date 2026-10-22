-- The first verification for a recommendation is the audit fact. Even the
-- trusted runtime may append a row but cannot rewrite or delete that fact.
create function public.reject_feature_preflight_review_mutation() returns trigger
language plpgsql security invoker set search_path=pg_catalog,public as $$
begin
 raise exception 'feature_preflight_reviews is append-only' using errcode='55000';
end $$;

revoke all on function public.reject_feature_preflight_review_mutation() from public,anon,authenticated;
create trigger feature_preflight_reviews_append_only
before update or delete on public.feature_preflight_reviews
for each row execute function public.reject_feature_preflight_review_mutation();
;
