alter table public.plus8_analyses disable trigger plus8_analyses_append_only;

update public.plus8_analyses
set model_name=case when lower(model_name)='plus8' then 'Plus8' else model_name end,
    model_version=regexp_replace(model_version,'^Plus8[[:space:]]+','','i')
where lower(model_name)='plus8'
  and (model_name<>'Plus8' or model_version~*'^Plus8[[:space:]]+');

update public.plus8_analyses a
set is_final_pre_match=true
from public.plus8_settlements s
where s.final_analysis_id=a.id
  and a.analysis_type in ('pre_match','pre_match_review')
  and not a.is_final_pre_match;

alter table public.plus8_analyses enable trigger plus8_analyses_append_only;;
