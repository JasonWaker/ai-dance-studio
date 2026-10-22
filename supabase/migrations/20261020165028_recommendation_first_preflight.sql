-- Observation eligibility and recommendation preflight are independent.
-- No market, result or recommendation snapshot is rewritten by this repair.
alter table public.football_feature_signals alter column sample_status set default 'active';
alter table public.under3_low_odds_matches alter column sample_status set default 'active';

create or replace function public.guard_verified_feature_sample() returns trigger
language plpgsql security invoker set search_path=pg_catalog,public as $$
begin
 if TG_TABLE_NAME='football_feature_signals' then
  if TG_OP='UPDATE' then
   NEW.trigger_at:=OLD.trigger_at; NEW.trigger_price:=OLD.trigger_price;
   NEW.market_reference_price:=OLD.market_reference_price;
   NEW.evidence:=NEW.evidence||(select coalesce(jsonb_object_agg(key,value),'{}'::jsonb)
    from jsonb_each(OLD.evidence) where key in ('initial','current','opening_total_line','current_total_line'));
   if OLD.evidence ? 'sample_original_market' then
    NEW.evidence:=NEW.evidence||jsonb_build_object('sample_original_market',OLD.evidence->'sample_original_market');
   else NEW.evidence:=NEW.evidence-'sample_original_market'; end if;
  end if;
  if TG_OP='INSERT' and exists(select 1 from public.football_feature_signals s
   where s.match_key=NEW.match_key and s.kind=NEW.kind and s.side=NEW.side
    and s.sample_status='abandoned_preflight_deviation') then
   NEW.sample_status:='abandoned_preflight_deviation'; NEW.included_in_stats:=false;
   NEW.sample_exclusion_reason:='同场同特征已废弃，重复扫描不恢复';
   NEW.sample_excluded_at:=clock_timestamp();
  end if;
 end if;
 if TG_OP='UPDATE' and OLD.sample_status='abandoned_preflight_deviation' then
  NEW.sample_status:=OLD.sample_status; NEW.sample_exclusion_reason:=OLD.sample_exclusion_reason;
  NEW.sample_verified_at:=OLD.sample_verified_at; NEW.sample_verification_evidence:=OLD.sample_verification_evidence;
 end if;
 return NEW;
end $$;

-- Restore only observations excluded by the mistaken blanket window gate.
-- Existing abandoned records, formal inclusion flags and actual evidence stay intact.
update public.football_feature_signals set
 sample_verification_evidence=coalesce(sample_verification_evidence,'{}')||jsonb_build_object('statistics_gate_repair',jsonb_build_object('previous_status',sample_status,'previous_reason',sample_exclusion_reason)),
 sample_status='active',sample_exclusion_reason=null
 where sample_status in ('pending_preflight','preflight_failed');
update public.under3_low_odds_matches set
 sample_verification_evidence=coalesce(sample_verification_evidence,'{}')||jsonb_build_object('statistics_gate_repair',jsonb_build_object('previous_status',sample_status,'previous_reason',sample_exclusion_reason)),
 sample_status='active',sample_exclusion_reason=null
 where sample_status in ('pending_preflight','preflight_failed');

comment on column public.football_feature_signals.sample_status is '观察样本资格，与推荐临场复核分离；active不代表推荐已核验。推荐复核读取锁定快照preflight_*；废弃样本不统计。';
comment on column public.under3_low_odds_matches.sample_status is '观察样本资格，与推荐临场复核分离；active不代表推荐已核验。';

create or replace function public.apply_feature_preflight_verification(
 p_match_key text,p_expected_snapshot jsonb,p_snapshot jsonb,p_abandoned_kinds text[],p_verified_at timestamptz
) returns boolean language plpgsql security invoker set search_path=pg_catalog,public as $$
declare current_snapshot jsonb; kickoff timestamptz;
begin
 select investment_recommendation_snapshot,kickoff_at into current_snapshot,kickoff
 from public.football_feature_matches where match_key=p_match_key for update;
 if current_snapshot is distinct from p_expected_snapshot then return false; end if;
 if current_snapshot->>'snapshot_origin' is distinct from 'pre_match'
  or current_snapshot->>'status' not in ('recommended','abandoned')
  or p_verified_at < kickoff-interval '30 minutes' or p_verified_at > kickoff-interval '25 minutes'
  or p_verified_at>clock_timestamp()+interval '5 seconds' then return false; end if;
 update public.football_feature_matches set investment_recommendation_snapshot=p_snapshot
 where match_key=p_match_key and status='scheduled' and kickoff_at>clock_timestamp();
 if not found then return false; end if;
 update public.football_feature_signals set sample_status='abandoned_preflight_deviation',
  sample_excluded_at=p_verified_at,sample_exclusion_reason='已复核·废弃：原推荐特征或盘口水位偏离',included_in_stats=false
 where match_key=p_match_key and kind=any(p_abandoned_kinds);
 update public.football_feature_signals s set sample_verified_at=p_verified_at
 where s.match_key=p_match_key and s.sample_status='active' and exists(
  select 1 from jsonb_array_elements(coalesce(p_snapshot->'candidates','[]'::jsonb)||jsonb_build_array(p_snapshot)) p
  where p->>'kind'=s.kind and p->>'preflight_status'='verified');
 return true;
end $$;
revoke all on function public.apply_feature_preflight_verification(text,jsonb,jsonb,text[],timestamptz) from public,anon,authenticated;
grant execute on function public.apply_feature_preflight_verification(text,jsonb,jsonb,text[],timestamptz) to service_role;
;
