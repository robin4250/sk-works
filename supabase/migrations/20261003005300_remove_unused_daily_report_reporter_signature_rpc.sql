-- The restored app now uses the existing dual-signature RPC
-- public.save_daily_report_signature(...). Keep one signature write path.
drop function if exists public.save_daily_report_reporter_signature(uuid,text,jsonb);
