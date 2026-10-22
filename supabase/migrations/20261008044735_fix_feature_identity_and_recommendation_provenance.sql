begin;

-- Quarantine unresolved source-identity conflicts from statistics and new
-- recommendations. Existing locked pre-match snapshots remain immutable.
alter table public.football_feature_matches
  add column if not exists identity_conflict_active boolean not null default false;

create index if not exists football_feature_matches_identity_conflict_idx
  on public.football_feature_matches (identity_conflict_active, kickoff_at desc)
  where identity_conflict_active;

alter table public.football_feature_identity_conflicts
  add column if not exists resolved_at timestamptz,
  add column if not exists resolution text;

comment on column public.football_feature_matches.identity_conflict_active is
  'True while a source identity, fixture mapping, or kickoff-time conflict is unresolved. Such fixtures are excluded from statistics and new recommendations.';

-- Apply the quarantine to the private statistical views without duplicating
-- their feature enumeration and settlement semantics.
do $$
declare
  view_name text;
  definition text;
begin
  foreach view_name in array array['football_feature_stats','football_feature_stats_by_bookmaker'] loop
    definition := pg_get_viewdef(format('public.%I',view_name)::regclass, true);
    if position('identity_match.identity_conflict_active' in definition) = 0 then
      if position('FROM football_feature_signals ' in definition) = 0 then
        raise exception '% definition changed; inspect before adding identity quarantine', view_name;
      end if;
      definition := regexp_replace(
        definition,
        'FROM football_feature_signals (s(_[0-9]+)?)',
        'FROM football_feature_signals \1 JOIN football_feature_matches identity_match ON identity_match.match_key = \1.match_key AND NOT identity_match.identity_conflict_active',
        'g'
      );
      execute format('create or replace view public.%I with (security_invoker = true) as %s',view_name,definition);
    end if;
  end loop;
end $$;

revoke all on table public.football_feature_stats from anon, authenticated;
revoke all on table public.football_feature_stats_by_bookmaker from anon, authenticated;
grant select on table public.football_feature_stats to service_role;
grant select on table public.football_feature_stats_by_bookmaker to service_role;

-- Keep publication time separate from the later freeze time. locked_at has
-- historically represented the post-kickoff immutability boundary for many
-- decisions, so it must not be presented as the original publication time.
alter table public.multi_feature_decisions
  add column if not exists first_published_at timestamptz,
  add column if not exists frozen_at timestamptz;

alter table public.multi_feature_decisions disable trigger multi_feature_decisions_immutable_lock;

with first_publication as (
  select h.match_key,h.decision_rank,min(h.calculated_at) as published_at
  from public.multi_feature_decision_history h
  join public.football_feature_matches m on m.match_key=h.match_key
  where coalesce(h.snapshot->>'analysis_phase','pre_match')='pre_match'
    and h.snapshot->>'decision_status'='RECOMMEND'
    and h.calculated_at<m.kickoff_at
  group by h.match_key,h.decision_rank
), provenance as (
  select d.id,d.locked_at,d.analysis_phase,d.decision_status,d.calculated_at,m.kickoff_at,p.published_at
  from public.multi_feature_decisions d
  join public.football_feature_matches m on m.match_key=d.match_key
  left join first_publication p on p.match_key=d.match_key and p.decision_rank=d.decision_rank
)
update public.multi_feature_decisions d
set first_published_at=coalesce(
      p.published_at,
      case when p.analysis_phase='pre_match' and p.decision_status='RECOMMEND'
        and p.calculated_at<p.kickoff_at then p.calculated_at end
    ),
    frozen_at=p.locked_at
from provenance p
where p.id=d.id;

alter table public.multi_feature_decisions enable trigger multi_feature_decisions_immutable_lock;

create or replace function public.multi_feature_set_decision_provenance()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
begin
  if new.first_published_at is null
     and new.analysis_phase='pre_match'
     and new.decision_status='RECOMMEND' then
    new.first_published_at=coalesce(new.calculated_at,now());
  end if;
  if new.frozen_at is null and new.locked_at is not null then
    new.frozen_at=new.locked_at;
  end if;
  return new;
end $$;

drop trigger if exists multi_feature_decision_provenance on public.multi_feature_decisions;
create trigger multi_feature_decision_provenance
before insert or update on public.multi_feature_decisions
for each row execute function public.multi_feature_set_decision_provenance();

revoke execute on function public.multi_feature_set_decision_provenance() from public,anon,authenticated;
grant execute on function public.multi_feature_set_decision_provenance() to service_role;

comment on column public.multi_feature_decisions.first_published_at is
  'First time this ranked RECOMMEND decision was published before kickoff; null means no verified pre-match publication.';
comment on column public.multi_feature_decisions.frozen_at is
  'Time the row became immutable. This may be after kickoff and is not the recommendation publication time.';

-- Repair the verified duplicate Botafogo RJ v Vasco fixture. Keep every raw
-- observation, quote and signal, but attach them to the correct Nowscore
-- canonical fixture. Existing recommendation snapshots and bet snapshots are
-- deliberately not regenerated.
update public.football_feature_source_identities
set match_key='nowscore:2910908',last_seen_at=greatest(last_seen_at,now())
where match_key='oddstorm:13573464';

update public.football_feature_observations set match_key='nowscore:2910908'
where match_key='oddstorm:13573464';
update public.football_feature_quotes set match_key='nowscore:2910908'
where match_key='oddstorm:13573464';

update public.football_feature_signals target
set evidence=target.evidence||jsonb_build_object(
  'canonical_merge_source',jsonb_build_object(
    'former_match_key',duplicate.match_key,
    'signal_id',duplicate.id,
    'bookmaker',duplicate.bookmaker,
    'trigger_at',duplicate.trigger_at,
    'source_platform',duplicate.source_platform,
    'source_url',duplicate.source_url,
    'evidence',duplicate.evidence
  )
)
from public.football_feature_signals duplicate
where target.match_key='nowscore:2910908'
  and duplicate.match_key='oddstorm:13573464'
  and target.kind=duplicate.kind
  and target.side=duplicate.side
  and coalesce(target.handicap,0)=coalesce(duplicate.handicap,0)
  and coalesce(target.total_line,0)=coalesce(duplicate.total_line,0);

delete from public.football_feature_signals duplicate
where duplicate.match_key='oddstorm:13573464'
  and exists (
    select 1 from public.football_feature_signals target
    where target.match_key='nowscore:2910908'
      and target.kind=duplicate.kind
      and target.side=duplicate.side
      and coalesce(target.handicap,0)=coalesce(duplicate.handicap,0)
      and coalesce(target.total_line,0)=coalesce(duplicate.total_line,0)
  );

update public.football_feature_signals set match_key='nowscore:2910908'
where match_key='oddstorm:13573464';
update public.multi_feature_signals set match_key='nowscore:2910908'
where match_key='oddstorm:13573464';

insert into public.football_feature_opening_baselines(
  match_key,bookmaker,source_platform,source_url,first_observed_at,
  first_home_handicap,first_home_odds,first_away_odds
)
select 'nowscore:2910908',bookmaker,source_platform,source_url,first_observed_at,
  first_home_handicap,first_home_odds,first_away_odds
from public.football_feature_opening_baselines
where match_key='oddstorm:13573464'
on conflict(match_key,bookmaker) do update set
  source_platform=excluded.source_platform,
  source_url=excluded.source_url,
  first_observed_at=excluded.first_observed_at,
  first_home_handicap=excluded.first_home_handicap,
  first_home_odds=excluded.first_home_odds,
  first_away_odds=excluded.first_away_odds
where excluded.first_observed_at<football_feature_opening_baselines.first_observed_at;
delete from public.football_feature_opening_baselines where match_key='oddstorm:13573464';

insert into public.football_feature_total_opening_baselines(
  match_key,bookmaker,source_platform,source_url,first_observed_at,
  first_total_line,first_over_odds,first_under_odds
)
select 'nowscore:2910908',bookmaker,source_platform,source_url,first_observed_at,
  first_total_line,first_over_odds,first_under_odds
from public.football_feature_total_opening_baselines
where match_key='oddstorm:13573464'
on conflict(match_key,bookmaker) do update set
  source_platform=excluded.source_platform,
  source_url=excluded.source_url,
  first_observed_at=excluded.first_observed_at,
  first_total_line=excluded.first_total_line,
  first_over_odds=excluded.first_over_odds,
  first_under_odds=excluded.first_under_odds
where excluded.first_observed_at<football_feature_total_opening_baselines.first_observed_at;
delete from public.football_feature_total_opening_baselines where match_key='oddstorm:13573464';

delete from public.football_name_unresolved where match_key='oddstorm:13573464';
update public.football_name_comparisons set match_key='nowscore:2910908'
where match_key='oddstorm:13573464';

update public.football_feature_identity_conflicts
set resolved_at=now(),resolution='merged oddstorm:13573464 into canonical nowscore:2910908 after score, teams and source kickoff verification'
where resolved_at is null
  and (match_key in ('oddstorm:13573464','nowscore:2910908')
    or source_key in ('oddstorm:13573464','nowscore:2910908'));

update public.football_feature_matches
set identity_conflict_active=false
where match_key='nowscore:2910908';

delete from public.football_feature_matches where match_key='oddstorm:13573464';

commit;
;
