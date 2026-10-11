-- Payment-certificate previews explicitly read this non-financial seal setting.
-- Keep the existing member/account RLS, all bank-column restrictions and DML
-- privileges intact. Do not grant table-wide SELECT or backfill saved documents.
do $$
begin
  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'companies'
      and c.relrowsecurity
  ) then
    raise exception 'companies RLS must remain enabled';
  end if;
end
$$;

grant select (company_seal_style) on table public.companies to authenticated;
