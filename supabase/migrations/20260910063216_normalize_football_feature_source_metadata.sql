create or replace function public.football_feature_normalize_source_metadata()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $$
declare
  history_label text;
begin
  new.source_count := greatest(1, coalesce(new.source_count, 1));
  new.verification_status := coalesce(nullif(new.verification_status, ''), 'single_source');

  if new.kind in ('losing_streak', 'over_streak')
     and new.verification_status = 'history_verified'
     and jsonb_typeof(new.evidence->'history_sources') = 'array'
     and jsonb_array_length(new.evidence->'history_sources') >= 2 then
    select string_agg(
      case value
        when '7M historical results and closing lines' then '7M 历史赛果与收盘'
        when 'LiveScore result archive' then 'LiveScore 赛果档案'
        when 'ESPN result archive' then 'ESPN 赛果档案'
        else value
      end,
      ' + ' order by ordinality
    )
    into history_label
    from jsonb_array_elements_text(new.evidence->'history_sources')
         with ordinality as src(value, ordinality);

    new.source_platform := coalesce(nullif(history_label, ''), new.source_platform);
    new.included_in_stats := true;
  end if;

  new.evidence :=
    jsonb_set(
      jsonb_set(
        jsonb_set(
          coalesce(new.evidence, '{}'::jsonb),
          '{source_count}', to_jsonb(new.source_count), true
        ),
        '{verification_status}', to_jsonb(new.verification_status), true
      ),
      '{eligible_for_official_stats}', to_jsonb(coalesce(new.included_in_stats, false)), true
    );

  return new;
end
$$;

drop trigger if exists football_feature_normalize_source_metadata_trg
  on public.football_feature_signals;

create trigger football_feature_normalize_source_metadata_trg
before insert or update of evidence, source_platform, source_count, verification_status, included_in_stats
on public.football_feature_signals
for each row
execute function public.football_feature_normalize_source_metadata();

update public.football_feature_signals
set evidence = evidence;;
