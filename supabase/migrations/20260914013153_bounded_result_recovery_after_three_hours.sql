-- A completed kickoff becomes eligible for result verification after three
-- hours. Remember attempts so a failed/unknown fixture cannot starve others.
alter table public.football_feature_matches
  add column if not exists last_result_check_at timestamptz;
alter table public.under3_low_odds_matches
  add column if not exists last_result_check_at timestamptz;

create index if not exists football_feature_matches_result_due_idx
  on public.football_feature_matches (last_result_check_at nulls first, kickoff_at)
  where status = 'scheduled' and result is null;
create index if not exists under3_low_odds_matches_result_due_idx
  on public.under3_low_odds_matches (last_result_check_at nulls first, kickoff_at)
  where status in ('scheduled', 'live') and settled_at is null;

do $$
declare quick_job bigint;
begin
  select jobid into quick_job from cron.job where jobname = 'football-feature-result-recovery';
  if quick_job is null then
    raise exception 'football-feature-result-recovery cron job is missing';
  end if;
  perform cron.alter_job(quick_job, schedule := '4-54/10 * * * *');
end $$;

select cron.schedule(
  'under3-result-recovery-after-three-hours',
  '9-59/10 * * * *',
  $job$
    select net.http_post(
      url := 'https://uljvndjkdfbvazhrrxmd.supabase.co/functions/v1/football-feature-scan/settle',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-scan-key', (select scan_key from public.ah0_scanner_config where id = true)
      ),
      body := jsonb_build_object('dataset', 'under3', 'tier', 'quick'),
      timeout_milliseconds := 120000
    );
  $job$
);
;
