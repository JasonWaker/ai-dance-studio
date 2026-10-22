-- Recommendation-bearing duplicate fixtures need a recoverable merge path.
-- The original 2026-09-24 helper predates MFDR, H2H evidence and name-sync
-- tables, so deleting a duplicate could cascade away recommendation history.

create table if not exists public.football_duplicate_cleanup_queue (
  id bigint generated always as identity primary key,
  canonical_match_key text not null,
  duplicate_match_key text not null,
  priority text not null check (priority in ('P0','P1','P2')),
  confidence text not null check (confidence in ('confirmed','high','manual_review')),
  reason text not null,
  evidence jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending','merged','quarantined','failed','skipped')),
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  error_message text,
  unique (canonical_match_key, duplicate_match_key)
);

create table if not exists public.football_duplicate_merge_audit (
  id uuid primary key default gen_random_uuid(),
  canonical_match_key text not null,
  duplicate_match_key text not null,
  queue_id bigint references public.football_duplicate_cleanup_queue(id) on delete set null,
  snapshot jsonb not null,
  merge_result jsonb,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists football_duplicate_cleanup_queue_status_idx
  on public.football_duplicate_cleanup_queue(priority,status,created_at);
create index if not exists football_duplicate_merge_audit_keys_idx
  on public.football_duplicate_merge_audit(canonical_match_key,duplicate_match_key,created_at desc);

alter table public.football_duplicate_cleanup_queue enable row level security;
alter table public.football_duplicate_merge_audit enable row level security;
revoke all on table public.football_duplicate_cleanup_queue from public,anon,authenticated;
revoke all on table public.football_duplicate_merge_audit from public,anon,authenticated;
grant all on table public.football_duplicate_cleanup_queue to service_role;
grant all on table public.football_duplicate_merge_audit to service_role;

create or replace function public.merge_duplicate_match(p_canonical text, p_duplicate text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $func$
declare
  v_audit_id uuid;
  v_queue_id bigint;
  v_snapshot jsonb;
  v_result jsonb;
  v_merged_signals integer := 0;
  v_merged_decisions integer := 0;
  v_archived_decisions integer := 0;
begin
  if p_canonical = p_duplicate then
    raise exception 'canonical and duplicate are the same: %', p_canonical;
  end if;

  perform 1 from public.football_feature_matches
   where match_key in (p_canonical,p_duplicate)
   for update;
  if (select count(*) from public.football_feature_matches where match_key in (p_canonical,p_duplicate)) <> 2 then
    raise exception 'both fixture rows must exist: canonical %, duplicate %', p_canonical,p_duplicate;
  end if;

  if exists (
    select 1
    from public.football_feature_matches c
    join public.football_feature_matches d on d.match_key=p_duplicate
    where c.match_key=p_canonical
      and c.result ? 'home_score' and d.result ? 'home_score'
      and ((c.result->>'home_score') is distinct from (d.result->>'home_score')
        or (c.result->>'away_score') is distinct from (d.result->>'away_score'))
  ) then
    raise exception 'score conflict between % and %', p_canonical,p_duplicate;
  end if;

  select id into v_queue_id
  from public.football_duplicate_cleanup_queue
  where canonical_match_key=p_canonical and duplicate_match_key=p_duplicate;

  select jsonb_build_object(
    'matches',(select jsonb_agg(to_jsonb(x)) from public.football_feature_matches x where x.match_key in (p_canonical,p_duplicate)),
    'signals',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.football_feature_signals x where x.match_key in (p_canonical,p_duplicate)),
    'observations',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.football_feature_observations x where x.match_key in (p_canonical,p_duplicate)),
    'quotes',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.football_feature_quotes x where x.match_key in (p_canonical,p_duplicate)),
    'opening_baselines',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.football_feature_opening_baselines x where x.match_key in (p_canonical,p_duplicate)),
    'total_opening_baselines',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.football_feature_total_opening_baselines x where x.match_key in (p_canonical,p_duplicate)),
    'source_identities',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.football_feature_source_identities x where x.match_key in (p_canonical,p_duplicate)),
    'h2h_evidence',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.football_feature_h2h_evidence x where x.match_key in (p_canonical,p_duplicate)),
    'multi_feature_signals',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.multi_feature_signals x where x.match_key in (p_canonical,p_duplicate)),
    'multi_feature_decisions',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.multi_feature_decisions x where x.match_key in (p_canonical,p_duplicate)),
    'multi_feature_history',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.multi_feature_decision_history x where x.match_key in (p_canonical,p_duplicate)),
    'favorites',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.match_favorites x where x.match_key in (p_canonical,p_duplicate)),
    'bets',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.bet_records x where x.match_key in (p_canonical,p_duplicate)),
    'name_comparisons',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.football_name_comparisons x where x.match_key in (p_canonical,p_duplicate)),
    'name_unresolved',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from public.football_name_unresolved x where x.match_key in (p_canonical,p_duplicate))
  ) into v_snapshot;

  insert into public.football_duplicate_merge_audit(canonical_match_key,duplicate_match_key,queue_id,snapshot)
  values(p_canonical,p_duplicate,v_queue_id,v_snapshot) returning id into v_audit_id;

  -- Preserve the best parent-level immutable snapshots before moving children.
  update public.football_feature_matches c set
    first_seen_at=least(c.first_seen_at,d.first_seen_at),
    last_seen_at=greatest(c.last_seen_at,d.last_seen_at),
    result=coalesce(c.result,d.result),
    last_pre_match_market_at=greatest(c.last_pre_match_market_at,d.last_pre_match_market_at),
    last_pre_match_market=case when d.last_pre_match_market_at>c.last_pre_match_market_at then d.last_pre_match_market else coalesce(c.last_pre_match_market,d.last_pre_match_market) end,
    investment_recommendation_snapshot=case
      when c.investment_recommendation_snapshot is null then d.investment_recommendation_snapshot
      when d.investment_recommendation_snapshot is null then c.investment_recommendation_snapshot
      when d.investment_recommendation_locked_at<c.investment_recommendation_locked_at then d.investment_recommendation_snapshot
      else c.investment_recommendation_snapshot end,
    investment_recommendation_locked_at=least(c.investment_recommendation_locked_at,d.investment_recommendation_locked_at),
    home_team_cn=coalesce(c.home_team_cn,d.home_team_cn),
    away_team_cn=coalesce(c.away_team_cn,d.away_team_cn),
    competition_name_cn=coalesce(c.competition_name_cn,d.competition_name_cn)
  from public.football_feature_matches d
  where c.match_key=p_canonical and d.match_key=p_duplicate;

  -- Keep MFDR signal links alive when equivalent source signals collide.
  delete from public.multi_feature_signals ms
  using public.football_feature_signals ds, public.football_feature_signals cs
  where ds.match_key=p_duplicate and cs.match_key=p_canonical
    and ds.kind=cs.kind and ds.side=cs.side
    and coalesce(ds.handicap,0)=coalesce(cs.handicap,0)
    and coalesce(ds.total_line,0)=coalesce(cs.total_line,0)
    and ms.source_signal_id=ds.id
    and exists (select 1 from public.multi_feature_signals keep
      where keep.source_signal_id=cs.id and keep.market_type=ms.market_type and keep.direction=ms.direction);

  update public.multi_feature_signals ms set source_signal_id=cs.id,match_key=p_canonical
  from public.football_feature_signals ds, public.football_feature_signals cs
  where ds.match_key=p_duplicate and cs.match_key=p_canonical
    and ds.kind=cs.kind and ds.side=cs.side
    and coalesce(ds.handicap,0)=coalesce(cs.handicap,0)
    and coalesce(ds.total_line,0)=coalesce(cs.total_line,0)
    and ms.source_signal_id=ds.id;

  delete from public.football_feature_signals ds
  using public.football_feature_signals cs
  where ds.match_key=p_duplicate and cs.match_key=p_canonical
    and ds.kind=cs.kind and ds.side=cs.side
    and coalesce(ds.handicap,0)=coalesce(cs.handicap,0)
    and coalesce(ds.total_line,0)=coalesce(cs.total_line,0);
  update public.football_feature_signals set match_key=p_canonical where match_key=p_duplicate;
  get diagnostics v_merged_signals=row_count;
  update public.multi_feature_signals set match_key=p_canonical where match_key=p_duplicate;

  -- A duplicate MFDR rank is archived as immutable history instead of being cascaded away.
  insert into public.multi_feature_decision_history(match_key,decision_id,decision_rank,input_fingerprint,recalc_reason,snapshot,calculated_at)
  select p_canonical,null,d.decision_rank,d.input_fingerprint,'duplicate_merge_archive',to_jsonb(d),d.calculated_at
  from public.multi_feature_decisions d
  where d.match_key=p_duplicate
    and exists(select 1 from public.multi_feature_decisions c where c.match_key=p_canonical and c.decision_rank=d.decision_rank);
  get diagnostics v_archived_decisions=row_count;
  delete from public.multi_feature_decisions d
  where d.match_key=p_duplicate
    and exists(select 1 from public.multi_feature_decisions c where c.match_key=p_canonical and c.decision_rank=d.decision_rank);
  update public.multi_feature_decisions set match_key=p_canonical where match_key=p_duplicate;
  get diagnostics v_merged_decisions=row_count;
  update public.multi_feature_decision_history set match_key=p_canonical where match_key=p_duplicate;

  delete from public.football_feature_observations d
  where d.match_key=p_duplicate and exists(select 1 from public.football_feature_observations c
    where c.match_key=p_canonical and c.bookmaker=d.bookmaker and c.source_platform=d.source_platform and c.observed_at=d.observed_at);
  update public.football_feature_observations set match_key=p_canonical where match_key=p_duplicate;
  update public.football_feature_quotes set match_key=p_canonical where match_key=p_duplicate;

  delete from public.football_feature_opening_baselines d where d.match_key=p_duplicate
    and exists(select 1 from public.football_feature_opening_baselines c where c.match_key=p_canonical and c.bookmaker=d.bookmaker);
  update public.football_feature_opening_baselines set match_key=p_canonical where match_key=p_duplicate;
  delete from public.football_feature_total_opening_baselines d where d.match_key=p_duplicate
    and exists(select 1 from public.football_feature_total_opening_baselines c where c.match_key=p_canonical and c.bookmaker=d.bookmaker);
  update public.football_feature_total_opening_baselines set match_key=p_canonical where match_key=p_duplicate;
  update public.football_feature_source_identities set match_key=p_canonical where match_key=p_duplicate;

  delete from public.football_feature_h2h_evidence where match_key=p_duplicate
    and exists(select 1 from public.football_feature_h2h_evidence where match_key=p_canonical);
  update public.football_feature_h2h_evidence set match_key=p_canonical where match_key=p_duplicate;
  update public.football_name_comparisons set match_key=p_canonical where match_key=p_duplicate;
  delete from public.football_name_unresolved where match_key=p_duplicate
    and exists(select 1 from public.football_name_unresolved where match_key=p_canonical);
  update public.football_name_unresolved set match_key=p_canonical where match_key=p_duplicate;

  -- Merge per-user favorites and active bets without violating their unique indexes.
  update public.match_favorites c set
    is_favorite=(c.is_favorite or d.is_favorite),is_pinned=(c.is_pinned or d.is_pinned),
    feature_kinds=(select array(select distinct unnest(c.feature_kinds||d.feature_kinds))),
    note=left(concat_ws(E'\n',nullif(c.note,''),nullif(d.note,'')),2000)
  from public.match_favorites d
  where c.match_key=p_canonical and d.match_key=p_duplicate and c.user_id=d.user_id;
  delete from public.match_favorites d where d.match_key=p_duplicate
    and exists(select 1 from public.match_favorites c where c.match_key=p_canonical and c.user_id=d.user_id);
  update public.match_favorites set match_key=p_canonical where match_key=p_duplicate;

  update public.bet_records d set cancelled_at=coalesce(d.cancelled_at,now()),
    note=left(concat_ws(E'\n',nullif(d.note,''),'重复赛事合并：有效投注已保留在规范赛事记录'),2000)
  where d.match_key=p_duplicate and d.cancelled_at is null
    and exists(select 1 from public.bet_records c where c.match_key=p_canonical and c.user_id=d.user_id and c.cancelled_at is null);
  update public.bet_records set match_key=p_canonical where match_key=p_duplicate;

  delete from public.football_feature_matches where match_key=p_duplicate;

  v_result=jsonb_build_object('success',true,'audit_id',v_audit_id,'canonical',p_canonical,'duplicate',p_duplicate,
    'merged_signals',v_merged_signals,'merged_decisions',v_merged_decisions,'archived_decisions',v_archived_decisions);
  update public.football_duplicate_merge_audit set merge_result=v_result,completed_at=now() where id=v_audit_id;
  update public.football_duplicate_cleanup_queue set status='merged',processed_at=now(),error_message=null where id=v_queue_id;
  return v_result;
exception when others then
  update public.football_duplicate_cleanup_queue set status='failed',processed_at=now(),error_message=sqlerrm where id=v_queue_id;
  raise;
end;
$func$;

revoke all on function public.merge_duplicate_match(text,text) from public,anon,authenticated;
grant execute on function public.merge_duplicate_match(text,text) to service_role;

comment on table public.football_duplicate_merge_audit is
  'Private, recoverable pre-merge snapshots for recommendation-bearing duplicate fixture cleanup.';
;
