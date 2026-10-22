-- Unified football feature: latest five direct meetings have a raw over rate
-- strictly above 70% (therefore 4/5 or 5/5). Historical evidence and current
-- multi-book market lines arrive independently and are joined by match_key.
alter table public.football_feature_signals
  drop constraint football_feature_signals_kind_check;

alter table public.football_feature_signals
  add constraint football_feature_signals_kind_check
  check (kind = any (array[
    'away_zero','home_weak_zero','reversal','rise_075','handicap_rise_05',
    'losing_streak','winning_streak','over_streak','weak_favorite',
    'total_line_jump','home_receive_225_25','h2h_over_70','five_plus_total'
  ]));

create table if not exists public.football_feature_h2h_evidence (
  match_key text primary key references public.football_feature_matches(match_key) on delete cascade,
  observed_at timestamptz not null,
  sample_size integer not null check (sample_size between 0 and 5),
  over_count integer not null check (over_count between 0 and sample_size),
  over_rate numeric(5,4) check (over_rate is null or over_rate between 0 and 1),
  complete_recent boolean not null default false,
  basis text not null check (basis='total_goals_ge_3'),
  matches jsonb not null default '[]'::jsonb check (jsonb_typeof(matches)='array'),
  source_platform text not null,
  source_url text not null check (source_url ~ '^https://'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((complete_recent and sample_size=5 and over_rate=over_count::numeric/5)
    or (not complete_recent and sample_size<5 and over_rate is null))
);

create index if not exists football_feature_h2h_evidence_qualified_idx
  on public.football_feature_h2h_evidence(over_rate desc, observed_at desc)
  where complete_recent and over_rate>.70;

alter table public.football_feature_h2h_evidence enable row level security;
revoke all on table public.football_feature_h2h_evidence from anon, authenticated;
grant all on table public.football_feature_h2h_evidence to service_role;

create table if not exists public.football_sevenm_h2h_requests (
  request_id bigint primary key,
  match_id bigint not null,
  requested_at timestamptz not null default now()
);

create table if not exists public.football_sevenm_h2h_cache (
  match_id bigint primary key,
  content text not null,
  fetched_at timestamptz not null,
  response_status integer not null check (response_status=200)
);

alter table public.football_sevenm_h2h_requests enable row level security;
alter table public.football_sevenm_h2h_cache enable row level security;
revoke all on table public.football_sevenm_h2h_requests from anon, authenticated;
revoke all on table public.football_sevenm_h2h_cache from anon, authenticated;
grant select on table public.football_sevenm_h2h_cache to service_role;

create or replace function public.football_enqueue_sevenm_h2h(p_offset integer,p_limit integer)
returns integer language sql security definer set search_path=public,pg_temp as $$
with live as (
  select regexp_matches(content,'sDt2\[([0-9]+)\]=\[([^\]]+)\]','g') as m
  from public.football_source_cache where source_key='7m_live'
), fixtures as (
  select m[1] as id from (
    select regexp_matches(content,
      'sDt\[([0-9]+)\]=\[''([^'']*)'',''([^'']*)'',''([^'']*)'',''([^'']*)''','g') as m
    from public.football_source_cache where source_key='7m_fixtures'
  ) f
  where (m[2]||m[4]||m[5]) !~* '(女|women|ladies|femeni|feminino|femenil|frauen|dames)'
), parsed as (
  select m[1] as id,
    string_to_array(substring(m[2] from '''([0-9]{4},[0-9]{2},[0-9]{2},[0-9]{2},[0-9]{2},[0-9]{1,2})'''),',') as k
  from live where split_part(m[2],',',1)='17'
), timed as (
  select p.id::bigint as match_id,
    make_timestamptz(k[1]::int,k[2]::int,k[3]::int,k[4]::int,k[5]::int,k[6]::int,'Asia/Shanghai') as kickoff
  from parsed p join fixtures f using(id) where k is not null
), selected as (
  select match_id from timed
  where kickoff between now() and now()+interval '24 hours'
  order by kickoff,match_id offset p_offset limit p_limit
), queued as (
  insert into public.football_sevenm_h2h_requests(request_id,match_id)
  select net.http_get(
    url := 'https://analyse.7m.com.cn/'||match_id||'/data/gamehistory_gb.js',
    timeout_milliseconds := 12000
  ),match_id from selected
  returning 1
)
select count(*)::integer from queued;
$$;

revoke all on function public.football_enqueue_sevenm_h2h(integer,integer) from public;
grant execute on function public.football_enqueue_sevenm_h2h(integer,integer) to postgres,service_role;

select cron.schedule('football-sevenm-h2h-1','39 */2 * * *',
  'select public.football_enqueue_sevenm_h2h(0,12);');
select cron.schedule('football-sevenm-h2h-2','41 */2 * * *',
  'select public.football_enqueue_sevenm_h2h(12,12);');
select cron.schedule('football-sevenm-h2h-3','43 */2 * * *',
  'select public.football_enqueue_sevenm_h2h(24,12);');
select cron.schedule('football-sevenm-h2h-4','45 */2 * * *',
  'select public.football_enqueue_sevenm_h2h(36,12);');
select cron.schedule('football-sevenm-h2h-ingest','48 */2 * * *',
$job$
insert into public.football_sevenm_h2h_cache(match_id,content,fetched_at,response_status)
select distinct on (r.match_id) r.match_id,h.content,r.requested_at,h.status_code
from public.football_sevenm_h2h_requests r
join net._http_response h on h.id=r.request_id
where r.requested_at>now()-interval '15 minutes'
  and h.status_code=200 and length(h.content)>200
order by r.match_id,r.requested_at desc
on conflict(match_id) do update set
  content=excluded.content,fetched_at=excluded.fetched_at,
  response_status=excluded.response_status;
$job$);

-- Keep all existing aggregation logic and only add the new zero-row kind to
-- the stats enumeration. The by-bookmaker view groups signal kinds directly.
do $migration$
declare definition text;
begin
  definition := pg_get_viewdef('public.football_feature_stats'::regclass, true);
  if position('h2h_over_70' in definition)=0 then
    if position('(''home_receive_225_25''::text)' in definition)=0 then
      raise exception 'football_feature_stats definition changed; inspect before extending h2h feature';
    end if;
    definition := replace(definition,
      '(''home_receive_225_25''::text)',
      '(''home_receive_225_25''::text), (''h2h_over_70''::text)');
    execute 'create or replace view public.football_feature_stats with (security_invoker = true) as ' || definition;
  end if;
end
$migration$;

revoke all on table public.football_feature_stats from anon, authenticated;
grant select on table public.football_feature_stats to service_role;

comment on table public.football_feature_h2h_evidence is
  '最近5场直接交锋原始证据；不足5场仅记录覆盖缺口，不生成特征信号。';
comment on constraint football_feature_signals_kind_check on public.football_feature_signals is
  '统一足球特征枚举；h2h_over_70 代表最近5次直接交锋大球率严格大于70%。';
;
