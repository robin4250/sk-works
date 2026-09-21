revoke select (
  bank_settings,
  bank_name,
  bank_branch,
  bank_account_type,
  bank_account_number,
  bank_account_holder
) on table public.companies from authenticated;
