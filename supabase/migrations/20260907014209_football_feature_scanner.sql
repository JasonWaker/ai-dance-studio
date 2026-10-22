create table public.football_feature_config (
 id boolean primary key default true check(id), feed_url text, feed_token text,
 description text not null default '全球男子足球；不限制联赛、杯赛与级别；数据源覆盖范围需实际核验'
);
insert into public.football_feature_config(id) values(true);
create table public.football_feature_runs (
 id uuid primary key default gen_random_uuid(), slot bigint unique not null,
 started_at timestamptz not null default now(), finished_at timestamptz,
 next_scan_at timestamptz not null, status text not null check(status in ('running','success','partial','blocked','failed')),
 discovered integer, qualified integer, signals integer, settled integer, excluded integer,
 message text, coverage jsonb not null default '{}'
);
create table public.football_feature_matches (
 match_key text primary key, kickoff_at timestamptz not null, competition_name text not null,
 home_team text not null, away_team text not null, status text not null default 'scheduled',
 first_seen_at timestamptz not null default now(), last_seen_at timestamptz not null default now(),
 result jsonb
);
create index on public.football_feature_matches(kickoff_at);
create table public.football_feature_observations (
 id uuid primary key default gen_random_uuid(), run_id uuid not null references public.football_feature_runs(id),
 match_key text not null references public.football_feature_matches(match_key), bookmaker text not null,
 observed_at timestamptz not null, payload jsonb not null, all_five boolean not null default false,
 unique(match_key,bookmaker,observed_at)
);
create table public.football_feature_signals (
 id uuid primary key default gen_random_uuid(), match_key text not null references public.football_feature_matches(match_key),
 bookmaker text not null, kind text not null check(kind in ('away_zero','reversal','rise_075','losing_streak','over_streak')),
 side text not null check(side in ('home','away')), trigger_at timestamptz not null, handicap numeric, total_line numeric,
 evidence jsonb not null, outcome text check(outcome in ('WIN','HALF_WIN','PUSH','HALF_LOSS','LOSS','VOID')),
 value numeric check(value in (-1,-0.5,0,0.5,1)), settled_at timestamptz,
 unique(match_key,bookmaker,kind,side)
);
create index on public.football_feature_signals(kind);
create index on public.football_feature_signals(match_key);
create index on public.football_feature_observations(run_id);
create view public.football_feature_stats with(security_invoker=true) as
with kinds(kind) as(values('away_zero'),('reversal'),('rise_075'),('losing_streak'),('over_streak'))
select k.kind, count(s.id) as samples, count(distinct s.match_key) as matches,
 count(s.id) filter(where s.outcome is null) as pending,
 count(s.id) filter(where s.outcome='VOID') as voids,
 count(s.id) filter(where s.value is not null) as settled,
 count(s.id) filter(where s.value=1) as wins,
 count(s.id) filter(where s.value=0.5) as half_wins,
 count(s.id) filter(where s.value=0) as pushes,
 count(s.id) filter(where s.value=-0.5) as half_losses,
 count(s.id) filter(where s.value=-1) as losses,
 round(100.0 * count(s.id) filter(where case when k.kind='losing_streak' then s.value<0 else s.value>0 end) / nullif(count(s.id) filter(where s.value is not null),0),2) as hit_rate,
 round(100.0 * count(s.id) filter(where s.value=1) / nullif(count(s.id) filter(where s.value in(-1,1)),0),2) as decisive_win_rate
from kinds k left join public.football_feature_signals s on s.kind=k.kind group by k.kind;
-- All records are operator-only. No public read/write grants and no SECURITY DEFINER RPC.
do $$ declare t text; begin
 foreach t in array array['football_feature_config','football_feature_runs','football_feature_matches','football_feature_observations','football_feature_signals'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from anon, authenticated',t);
 execute format('grant all on public.%I to service_role',t);
 end loop;
end $$;
revoke all on public.football_feature_stats from anon,authenticated;
grant select on public.football_feature_stats to service_role;
create function public.football_feature_commit(p_run uuid,p_items jsonb,p_results jsonb) returns jsonb
language plpgsql security invoker set search_path=public,pg_temp as $$
declare i jsonb; s jsonb; r jsonb; n integer:=0; q integer:=0; begin
 for i in select value from jsonb_array_elements(p_items) loop
 insert into football_feature_matches(match_key,kickoff_at,competition_name,home_team,away_team)
 values(i->>'match_key',(i->>'kickoff_at')::timestamptz,i->>'competition_name',i->>'home_team',i->>'away_team')
 on conflict(match_key) do update set kickoff_at=excluded.kickoff_at,last_seen_at=now();
 insert into football_feature_observations(run_id,match_key,bookmaker,observed_at,payload,all_five)
 values(p_run,i->>'match_key',i->>'bookmaker',(i->>'observed_at')::timestamptz,i->'observation',coalesce((i->>'all_five')::boolean,false)) on conflict do nothing;
 for s in select value from jsonb_array_elements(i->'signals') loop
 insert into football_feature_signals(match_key,bookmaker,kind,side,trigger_at,handicap,total_line,evidence)
 values(i->>'match_key',i->>'bookmaker',s->>'kind',s->>'side',(i->>'observed_at')::timestamptz,(s->>'handicap')::numeric,(s->>'total_line')::numeric,s->'evidence') on conflict do nothing;
 get diagnostics q=row_count; n:=n+q;
 end loop;
 end loop;
 for r in select value from jsonb_array_elements(p_results) loop
 update football_feature_signals set outcome=r->>'outcome',value=(r->>'value')::numeric,settled_at=now() where id=(r->>'id')::uuid;
 update football_feature_matches set status=r->'result'->>'status',result=r->'result' where match_key=r->>'match_key';
 end loop;
 return jsonb_build_object('new_signals',n,'settled',jsonb_array_length(p_results));
end $$;
revoke execute on function public.football_feature_commit(uuid,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.football_feature_commit(uuid,jsonb,jsonb) to service_role;
;
