-- Existing companies were seeded by the assigned-confirmation migration.
-- Future companies start with their first registered administrator as confirmer.
-- Never replace an explicitly configured set when another administrator joins.
create or replace function private.seed_company_payroll_confirmer()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.role is null or new.role::text not in ('owner', 'admin') then
    return new;
  end if;

  -- Serialize with set_payroll_confirmers and other membership inserts.
  perform 1 from public.companies where id = new.company_id for update;
  if not exists (
    select 1 from public.payroll_confirmers where company_id = new.company_id
  ) then
    insert into public.payroll_confirmers(company_id, position, user_id)
    values (new.company_id, 1, new.user_id);
  end if;
  return new;
end;
$$;

revoke all on function private.seed_company_payroll_confirmer()
  from public, anon, authenticated;

drop trigger if exists company_members_seed_payroll_confirmer
  on public.company_members;
create trigger company_members_seed_payroll_confirmer
after insert or update of company_id, user_id, role on public.company_members
for each row execute function private.seed_company_payroll_confirmer();
