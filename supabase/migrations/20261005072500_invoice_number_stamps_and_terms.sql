-- Invoice presentation settings, automatic numbering, and month-end issue dates.

alter table public.company_private_billing_settings
  add column if not exists invoice_subject text,
  add column if not exists invoice_contact_name text,
  add column if not exists payment_due_text text;

create table if not exists private.invoice_number_counters (
  company_id uuid primary key references public.companies(id) on delete cascade,
  last_number bigint not null default 0 check (last_number >= 0),
  updated_at timestamptz not null default now()
);

alter table private.invoice_number_counters enable row level security;

create or replace function private.assign_invoice_number_and_issue_date()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_number bigint;
begin
  if nullif(trim(coalesce(new.invoice_number, '')), '') is null then
    insert into private.invoice_number_counters(company_id, last_number, updated_at)
    values (new.company_id, 1, now())
    on conflict (company_id) do update
      set last_number = private.invoice_number_counters.last_number + 1,
          updated_at = now()
    returning last_number into v_number;

    new.invoice_number := v_number::text;
  end if;

  if new.issue_date is null then
    new.issue_date := new.billing_period_end;
  end if;

  return new;
end;
$function$;

drop trigger if exists invoices_assign_number_and_issue_date
  on public.invoices;

create trigger invoices_assign_number_and_issue_date
before insert or update on public.invoices
for each row
execute function private.assign_invoice_number_and_issue_date();

-- Existing drafts also receive a stable counter number and month-end issue date.
update public.invoices
set invoice_number = invoice_number,
    issue_date = coalesce(issue_date, billing_period_end)
where nullif(trim(coalesce(invoice_number, '')), '') is null
   or issue_date is null;

create or replace function public.save_invoice_settings_v2(
  p_tax_rate numeric,
  p_welfare_rate numeric,
  p_template_title text,
  p_footer_note text,
  p_bank_name text,
  p_bank_branch text,
  p_bank_account_type text,
  p_bank_account_number text,
  p_bank_account_holder text,
  p_invoice_subject text,
  p_invoice_contact_name text,
  p_payment_due_text text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_company_id uuid;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  select cm.company_id
  into v_company_id
  from public.company_members cm
  where cm.user_id = v_user_id
  limit 1;

  if v_company_id is null
     or not private.has_company_feature(v_company_id, 'can_manage_invoices') then
    raise exception 'invoice management permission required';
  end if;

  if p_tax_rate is null or p_tax_rate < 0 or p_tax_rate > 100 then
    raise exception 'invalid tax rate';
  end if;

  if p_welfare_rate is null or p_welfare_rate < 0 or p_welfare_rate > 100 then
    raise exception 'invalid welfare rate';
  end if;

  update public.companies
  set tax_rate = p_tax_rate,
      default_welfare_rate = p_welfare_rate,
      invoice_template_title = coalesce(
        nullif(trim(coalesce(p_template_title, '')), ''),
        '請求書'
      ),
      invoice_footer_note = nullif(trim(coalesce(p_footer_note, '')), '')
  where id = v_company_id;

  insert into public.company_private_billing_settings (
    company_id,
    bank_name,
    bank_branch,
    bank_account_type,
    bank_account_number,
    bank_account_holder,
    invoice_subject,
    invoice_contact_name,
    payment_due_text,
    updated_by,
    updated_at
  )
  values (
    v_company_id,
    nullif(trim(coalesce(p_bank_name, '')), ''),
    nullif(trim(coalesce(p_bank_branch, '')), ''),
    nullif(trim(coalesce(p_bank_account_type, '')), ''),
    nullif(trim(coalesce(p_bank_account_number, '')), ''),
    nullif(trim(coalesce(p_bank_account_holder, '')), ''),
    nullif(trim(coalesce(p_invoice_subject, '')), ''),
    nullif(trim(coalesce(p_invoice_contact_name, '')), ''),
    nullif(trim(coalesce(p_payment_due_text, '')), ''),
    v_user_id,
    now()
  )
  on conflict (company_id) do update
  set bank_name = excluded.bank_name,
      bank_branch = excluded.bank_branch,
      bank_account_type = excluded.bank_account_type,
      bank_account_number = excluded.bank_account_number,
      bank_account_holder = excluded.bank_account_holder,
      invoice_subject = excluded.invoice_subject,
      invoice_contact_name = excluded.invoice_contact_name,
      payment_due_text = excluded.payment_due_text,
      updated_by = v_user_id,
      updated_at = now();
end;
$function$;

revoke all on function public.save_invoice_settings_v2(
  numeric,numeric,text,text,text,text,text,text,text,text,text,text
) from public, anon;

grant execute on function public.save_invoice_settings_v2(
  numeric,numeric,text,text,text,text,text,text,text,text,text,text
) to authenticated;
