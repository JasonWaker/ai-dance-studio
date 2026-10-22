-- Only explicitly verified feature samples count. Observations are retained.
alter table public.football_feature_signals
 add column sample_verified_at timestamptz,
 add column sample_verification_evidence jsonb;
alter table public.under3_low_odds_matches
 add column sample_verified_at timestamptz,
 add column sample_verification_evidence jsonb;
alter table public.football_feature_signals drop constraint football_feature_signals_sample_status_check;
alter table public.under3_low_odds_matches drop constraint under3_low_odds_matches_sample_status_check;
alter table public.football_feature_signals add constraint football_feature_signals_sample_status_check
 check(sample_status in ('active','pending_preflight','preflight_failed','abandoned_preflight_deviation'));
alter table public.under3_low_odds_matches add constraint under3_low_odds_matches_sample_status_check
 check(sample_status in ('active','pending_preflight','preflight_failed','abandoned_preflight_deviation'));
alter table public.football_feature_signals alter column sample_status set default 'pending_preflight';
alter table public.under3_low_odds_matches alter column sample_status set default 'pending_preflight';

-- No inferred passes from a final score, old inclusion flag, or last_seen_at.
-- A service-side replay may subsequently verify real stored pre-match evidence.
update public.football_feature_signals set sample_status='pending_preflight',
 sample_exclusion_reason='旧样本尚无30分钟核验证据，待证据复核；原赛果和推荐保留'
 where sample_status='active';
update public.under3_low_odds_matches set sample_status='pending_preflight',
 sample_exclusion_reason='旧样本尚无30分钟核验证据，待证据复核；原赛果和推荐保留'
 where sample_status='active';

create function public.apply_feature_sample_checks(p_checks jsonb)
returns integer language plpgsql security invoker set search_path=pg_catalog,public as $$
declare item jsonb; changed integer:=0; affected integer; market_at timestamptz;
begin
 if jsonb_array_length(p_checks)>100 then raise exception 'sample batch exceeds 100'; end if;
 for item in select value from jsonb_array_elements(p_checks) loop
  market_at:=nullif(item->>'market_at','')::timestamptz;
  update public.football_feature_signals s set
   sample_status=item->>'status',
   sample_verified_at=case when item->>'status'='active' then market_at else s.sample_verified_at end,
   sample_verification_evidence=item->'evidence',
   sample_exclusion_reason=case when item->>'status'='active' then null else item->>'reason' end,
   sample_excluded_at=case when item->>'status'='abandoned_preflight_deviation' then clock_timestamp() else s.sample_excluded_at end,
   included_in_stats=case when item->>'status'='abandoned_preflight_deviation' then false else s.included_in_stats end
  from public.football_feature_matches m
  where s.id=(item->>'id')::uuid and m.match_key=s.match_key
   and s.sample_status<>'abandoned_preflight_deviation'
   and (item->>'status'<>'active' or (market_at>=m.kickoff_at-interval '30 minutes'
     and market_at<=m.kickoff_at-interval '25 minutes' and market_at>=s.trigger_at
     and market_at<clock_timestamp()+interval '5 seconds' and not m.identity_conflict_active));
  get diagnostics affected=row_count;changed:=changed+affected;
 end loop;
 return changed;
end $$;
revoke all on function public.apply_feature_sample_checks(jsonb) from public,anon,authenticated;
grant execute on function public.apply_feature_sample_checks(jsonb) to service_role;

-- Repeated upserts cannot reactivate abandoned samples or insert unverified
-- rows directly into the valid statistics pool.
create function public.guard_verified_feature_sample() returns trigger
language plpgsql security invoker set search_path=pg_catalog,public as $$
begin
 if TG_TABLE_NAME='football_feature_signals' then
 if TG_OP='UPDATE' then
  -- Repeated scans are follow-up observations, never a new first quote.
  NEW.trigger_at:=OLD.trigger_at;NEW.trigger_price:=OLD.trigger_price;
  NEW.market_reference_price:=OLD.market_reference_price;
  NEW.evidence:=NEW.evidence||(select coalesce(jsonb_object_agg(key,value),'{}'::jsonb)
    from jsonb_each(OLD.evidence) where key in ('initial','current','opening_total_line','current_total_line'));
 end if;
 if TG_OP='UPDATE' and OLD.evidence ? 'sample_original_market' then
  NEW.evidence:=NEW.evidence||jsonb_build_object('sample_original_market',OLD.evidence->'sample_original_market');
 end if;
 if TG_OP='UPDATE' and not (OLD.evidence ? 'sample_original_market') then
  NEW.evidence:=NEW.evidence-'sample_original_market';
 end if;
 if TG_OP='INSERT' and exists (
  select 1 from public.football_feature_signals s where s.match_key=NEW.match_key and s.kind=NEW.kind
   and s.side=NEW.side and s.sample_status='abandoned_preflight_deviation'
 ) then
  NEW.sample_status:='abandoned_preflight_deviation';NEW.sample_exclusion_reason:='同场同特征已废弃，重复扫描不恢复';
  NEW.sample_excluded_at:=clock_timestamp();NEW.included_in_stats:=false;
 end if;
 end if;
 if TG_OP='UPDATE' and OLD.sample_status='abandoned_preflight_deviation' then
  NEW.sample_status:=OLD.sample_status;NEW.sample_exclusion_reason:=OLD.sample_exclusion_reason;
  NEW.sample_verified_at:=OLD.sample_verified_at;NEW.sample_verification_evidence:=OLD.sample_verification_evidence;
 end if;
 if NEW.sample_status='active' and (NEW.sample_verified_at is null or NEW.sample_verification_evidence is null
  or NEW.sample_verification_evidence->>'rule' is distinct from 'feature-sample-30m-v1'
  or NEW.sample_verified_at>clock_timestamp()+interval '5 seconds') then
  NEW.sample_status:='pending_preflight';
 end if;
 if TG_TABLE_NAME='under3_low_odds_matches' then
 if NEW.sample_status='active' and
   (NEW.sample_verified_at<NEW.kickoff_at-interval '30 minutes' or NEW.sample_verified_at>NEW.kickoff_at-interval '25 minutes'
     or NEW.sample_verified_at<NEW.first_seen_at) then
  NEW.sample_status:='preflight_failed';NEW.sample_exclusion_reason:='核验时间不在30分钟窗口或早于首次发现';
 end if;
 end if;
 return NEW;
end $$;
create trigger zzzz_guard_verified_sample before insert or update on public.football_feature_signals
for each row execute function public.guard_verified_feature_sample();
create trigger zzzz_guard_verified_sample before insert or update on public.under3_low_odds_matches
for each row execute function public.guard_verified_feature_sample();
revoke all on function public.guard_verified_feature_sample() from public,anon,authenticated;
grant execute on function public.guard_verified_feature_sample() to service_role;
-- Under3 has an append-only quote archive. Replay only actual window quotes,
-- never the final score or latest post-kickoff odds.
with historical as (
 select distinct on (m.id) m.id,s.captured_at,s.under3_odds,s.odds_source,s.source_url,m.trigger_under3_odds
 from public.under3_low_odds_matches m join public.under3_low_odds_snapshots s on s.match_id=m.id
 where m.sample_status='pending_preflight' and s.captured_at>=m.first_seen_at
 and s.captured_at between m.kickoff_at-interval '30 minutes' and m.kickoff_at-interval '25 minutes'
 and s.captured_at<clock_timestamp() and s.source_url is not null
 and s.under3_odds is not null and m.trigger_under3_odds is not null
 order by m.id,s.captured_at desc,s.id desc
)
update public.under3_low_odds_matches m set
 sample_status=case when h.under3_odds between 1.60 and 1.75 and abs(h.under3_odds-h.trigger_under3_odds)<=0.08 then 'active' else 'abandoned_preflight_deviation' end,
 sample_verified_at=h.captured_at,
 sample_verification_evidence=jsonb_build_object('rule','feature-sample-30m-v1','method','stored_pre_match_evidence','market_observed_at',h.captured_at,'source_url',h.source_url,'odds_source',h.odds_source,'original_under3_odds',h.trigger_under3_odds,'under3_odds',h.under3_odds),
 sample_exclusion_reason=case when h.under3_odds between 1.60 and 1.75 and abs(h.under3_odds-h.trigger_under3_odds)<=0.08 then null else '真实30分钟历史盘口偏离原特征或水位' end,
 sample_excluded_at=case when h.under3_odds not between 1.60 and 1.75 or abs(h.under3_odds-h.trigger_under3_odds)>0.08 then clock_timestamp() else m.sample_excluded_at end
from historical h where m.id=h.id;
comment on column public.football_feature_signals.sample_status is 'active=30分钟核验通过；pending_preflight=未核验；preflight_failed=核验失败；abandoned_preflight_deviation=失效废弃。仅active进入有效统计。';

-- Bounded, keyset-paginated historical replay. Only fixtures with signals.
create function public.feature_sample_recheck_matches(p_cursor text default '',p_limit integer default 100)
returns table(match_key text,kickoff_at timestamptz,last_pre_match_market_at timestamptz,last_pre_match_market jsonb,identity_conflict_active boolean)
language sql stable security invoker set search_path=pg_catalog,public as $$
 select m.match_key,m.kickoff_at,m.last_pre_match_market_at,m.last_pre_match_market,m.identity_conflict_active
 from public.football_feature_matches m where m.match_key>p_cursor
 and exists(select 1 from public.football_feature_signals s where s.match_key=m.match_key)
 order by m.match_key limit least(greatest(p_limit,1),100);
$$;
revoke all on function public.feature_sample_recheck_matches(text,integer) from public,anon,authenticated;
grant execute on function public.feature_sample_recheck_matches(text,integer) to service_role;
;
