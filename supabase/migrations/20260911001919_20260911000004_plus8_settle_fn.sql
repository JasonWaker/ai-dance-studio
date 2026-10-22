create or replace function plus8_internal.settle_confirmed_results(
  p_reference_time timestamptz default now(),
  p_min_kickoff_offset interval default '3 hours',
  p_lookback interval default '14 days',
  p_batch_limit integer default 500
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
  declare
    v_cutoff_at timestamptz := p_reference_time - p_min_kickoff_offset;
    v_scan_from timestamptz := p_reference_time - p_lookback;
    v_checked integer := 0;
    v_settled integer := 0;
    v_skipped integer := 0;
    v_failed integer := 0;
    v_detail jsonb[] := '{}'::jsonb[];
    v_match record;
    v_result jsonb;
  begin
    if p_batch_limit is null or p_batch_limit <= 0 then
      p_batch_limit := 500;
    end if;

    for v_match in
      select
        m.match_key,
        m.home_score,
        m.away_score,
        coalesce(nullif(m.result_source, ''), 'auto') as result_source
      from public.plus8_matches m
      left join public.plus8_settlements s on s.match_id = m.id
      where m.home_score is not null
        and m.away_score is not null
        and m.kickoff_time <= v_cutoff_at
        and m.kickoff_time >= v_scan_from
        and m.status not in ('cancelled', 'postponed')
        and not coalesce(m.result_confirmed, false)
        and s.id is null
      order by m.kickoff_time asc
      limit p_batch_limit
    loop
      v_checked := v_checked + 1;
      begin
        v_result := public.plus8_settle_match(v_match.match_key, v_match.home_score, v_match.away_score, v_match.result_source);
        v_settled := v_settled + 1;
        v_detail := array_append(
          v_detail,
          jsonb_build_object(
            'match_key', v_match.match_key,
            'status', 'settled',
            'settlement_id', v_result->>'settlement_id',
            'total_result', v_result->>'total_result',
            'handicap_result', v_result->>'handicap_result'
          )
        );
      exception
        when others then
          v_failed := v_failed + 1;
          v_detail := array_append(
            v_detail,
            jsonb_build_object(
              'match_key', v_match.match_key,
              'status', 'failed',
              'error', SQLERRM
            )
          );
      end;
    end loop;

    v_skipped := greatest(0, v_checked - v_settled - v_failed);

    return jsonb_build_object(
      'success', true,
      'executed_at', p_reference_time,
      'scan_window', jsonb_build_object(
        'from', v_scan_from,
        'to', v_cutoff_at,
        'min_kickoff_offset', p_min_kickoff_offset,
        'lookback', p_lookback,
        'batch_limit', p_batch_limit
      ),
      'checked', v_checked,
      'settled', v_settled,
      'skipped', v_skipped,
      'failed', v_failed,
      'details', coalesce(to_jsonb(v_detail), '[]'::jsonb)
    );
  end;
$fn$;;
