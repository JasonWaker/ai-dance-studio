create index if not exists football_duplicate_merge_audit_queue_idx on public.football_duplicate_merge_audit(queue_id) where queue_id is not null;;
