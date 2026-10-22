alter table public.football_feature_signals
  add column if not exists sample_status text not null default 'active',
  add column if not exists sample_excluded_at timestamptz,
  add column if not exists sample_exclusion_reason text;
alter table public.football_feature_signals drop constraint if exists football_feature_signals_sample_status_check;
alter table public.football_feature_signals add constraint football_feature_signals_sample_status_check check (sample_status in ('active', 'abandoned_preflight_deviation'));
create index if not exists football_feature_signals_active_sample_idx on public.football_feature_signals (kind, settled_at desc) where sample_status = 'active';

alter table public.under3_low_odds_matches
  add column if not exists sample_status text not null default 'active',
  add column if not exists sample_excluded_at timestamptz,
  add column if not exists sample_exclusion_reason text;
alter table public.under3_low_odds_matches drop constraint if exists under3_low_odds_matches_sample_status_check;
alter table public.under3_low_odds_matches add constraint under3_low_odds_matches_sample_status_check check (sample_status in ('active', 'abandoned_preflight_deviation'));

comment on column public.football_feature_signals.sample_status is '样本状态；赛前30分钟核验盘口或水位偏离时废弃，不再进入特征统计。';
comment on column public.under3_low_odds_matches.sample_status is '小3低水样本状态；赛前30分钟核验偏离时废弃。';

-- Compare-and-swap the audit snapshot and exclude its feature samples in one transaction.
create or replace function public.apply_feature_preflight_verification(
  p_match_key text, p_expected_snapshot jsonb, p_snapshot jsonb,
  p_abandoned_kinds text[], p_verified_at timestamptz
) returns boolean language plpgsql security invoker set search_path=pg_catalog,public as $$
declare current_snapshot jsonb;
begin
  select investment_recommendation_snapshot into current_snapshot
  from public.football_feature_matches where match_key=p_match_key for update;
  if current_snapshot is distinct from p_expected_snapshot then return false; end if;
  update public.football_feature_matches set investment_recommendation_snapshot=p_snapshot
    where match_key=p_match_key and status='scheduled' and kickoff_at>clock_timestamp();
  if not found then return false; end if;
  update public.football_feature_signals set sample_status='abandoned_preflight_deviation',
    sample_excluded_at=p_verified_at, sample_exclusion_reason='赛前30分钟核验：盘口变化或水位偏差超过0.08', included_in_stats=false
    where match_key=p_match_key and kind=any(p_abandoned_kinds);
  return true;
end $$;

do $$
declare view_name text; definition text;
begin
  definition:=pg_get_viewdef('public.under3_low_odds_dashboard'::regclass,true);
  definition:=replace(definition,'FROM under3_low_odds_matches m',', m.sample_status, m.sample_excluded_at, m.sample_exclusion_reason FROM under3_low_odds_matches m');
  execute 'create or replace view public.under3_low_odds_dashboard with (security_invoker=true) as '||definition;
  for view_name in select viewname from pg_views where schemaname='public' and viewname like 'under3_low_odds_stats%' loop
    definition:=pg_get_viewdef(format('public.%I',view_name)::regclass,true);
    definition:=replace(definition,'WHERE ', 'WHERE sample_status = ''active'' AND ');
    execute format('create or replace view public.%I with (security_invoker=true) as %s',view_name,definition);
  end loop;
end $$;
revoke all on function public.apply_feature_preflight_verification(text,jsonb,jsonb,text[],timestamptz) from public,anon,authenticated;
grant execute on function public.apply_feature_preflight_verification(text,jsonb,jsonb,text[],timestamptz) to service_role;

-- Future scans must not reintroduce a discarded match through a new company signal.
create or replace function public.keep_abandoned_feature_sample()
returns trigger language plpgsql security invoker set search_path=pg_catalog,public as $$
declare snapshot jsonb;
begin
  select investment_recommendation_snapshot into snapshot from public.football_feature_matches where match_key=NEW.match_key;
  if NEW.sample_status='abandoned_preflight_deviation' or exists (
    select 1 from jsonb_array_elements(coalesce(snapshot->'candidates','[]'::jsonb) || jsonb_build_array(snapshot)) plan
    where plan->>'kind'=NEW.kind and plan->>'preflight_status'='deviated'
  ) then
    NEW.sample_status:='abandoned_preflight_deviation'; NEW.included_in_stats:=false;
    NEW.sample_excluded_at:=coalesce(NEW.sample_excluded_at,(snapshot->>'preflight_verified_at')::timestamptz,clock_timestamp());
    NEW.sample_exclusion_reason:=coalesce(NEW.sample_exclusion_reason,'赛前核验偏离，样本已废弃');
  end if;
  return NEW;
end $$;
create trigger zz_keep_abandoned_feature_sample before insert or update on public.football_feature_signals
for each row execute function public.keep_abandoned_feature_sample();
revoke all on function public.keep_abandoned_feature_sample() from public,anon,authenticated;
grant execute on function public.keep_abandoned_feature_sample() to service_role;

do $$
declare view_name text; definition text;
begin
  foreach view_name in array array['football_feature_stats','football_feature_stats_by_bookmaker'] loop
    definition:=pg_get_viewdef(format('public.%I',view_name)::regclass,true);
    definition:=regexp_replace(definition,'football_feature_signals (s(_[0-9]+)?)\M',
      '(select * from public.football_feature_signals where sample_status = ''active'') \1','g');
    execute format('create or replace view public.%I with (security_invoker=true) as %s',view_name,definition);
  end loop;
end $$;
;
