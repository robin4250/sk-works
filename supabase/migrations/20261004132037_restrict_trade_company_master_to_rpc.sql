-- Mirrors production migration 20261004132037.
-- Trade company data is intentionally RPC-only from the app.
revoke all on table public.trade_companies from anon,authenticated;
revoke all on table public.trade_company_contracts from anon,authenticated;
revoke all on table public.site_calculation_source_preferences from anon,authenticated;
