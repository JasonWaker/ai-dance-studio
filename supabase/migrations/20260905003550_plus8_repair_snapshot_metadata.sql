alter table public.plus8_recommendations disable trigger plus8_recommendations_append_only;

update public.plus8_recommendations r
set model_name=a.model_name,
    model_version=a.model_version,
    analysis_source=a.analysis_source
from public.plus8_analyses a
where a.id=r.analysis_id
  and (
    r.model_name is distinct from a.model_name
    or r.model_version is distinct from a.model_version
    or r.analysis_source is distinct from a.analysis_source
  );

alter table public.plus8_recommendations enable trigger plus8_recommendations_append_only;

update public.plus8_settlements s
set model_name=a.model_name,
    model_version=a.model_version,
    analysis_source=a.analysis_source
from public.plus8_analyses a
where a.id=s.final_analysis_id
  and (
    s.model_name is distinct from a.model_name
    or s.model_version is distinct from a.model_version
    or s.analysis_source is distinct from a.analysis_source
  );

do $do$
declare d date;
begin
  for d in select distinct stat_date from public.plus8_daily_stats order by stat_date
  loop
    perform public.plus8_refresh_daily_stats(d);
  end loop;
end;
$do$;;
