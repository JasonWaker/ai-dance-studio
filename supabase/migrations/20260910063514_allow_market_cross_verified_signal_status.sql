alter table public.football_feature_signals
         drop constraint if exists football_feature_signals_verification_status_check;

         alter table public.football_feature_signals
         add constraint football_feature_signals_verification_status_check
         check (verification_status = any (array[
           'cross_verified'::text,
           'history_verified'::text,
           'market_cross_verified'::text,
           'single_source'::text
         ]));;
