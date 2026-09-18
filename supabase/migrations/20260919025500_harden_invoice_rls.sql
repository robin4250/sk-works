-- Keep invoice/customer data readable to company members for compatibility,
-- but restrict financial master/calculation writes to owner/admin/manager roles.

alter table public.customers enable row level security;
alter table public.invoices enable row level security;
alter table public.invoice_site_calculations enable row level security;
alter table public.invoice_detail_lines enable row level security;

drop policy if exists "customers_company_access" on public.customers;
drop policy if exists "company members can read customers" on public.customers;
drop policy if exists "managers can manage customers" on public.customers;
create policy "company members can read customers"
on public.customers for select to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = customers.company_id
      and cm.user_id = auth.uid()
  )
);
create policy "managers can manage customers"
on public.customers for all to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = customers.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin','manager')
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = customers.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin','manager')
  )
);

drop policy if exists "invoices_company_access" on public.invoices;
drop policy if exists "company members can read invoices" on public.invoices;
drop policy if exists "managers can manage invoices" on public.invoices;
create policy "company members can read invoices"
on public.invoices for select to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = invoices.company_id
      and cm.user_id = auth.uid()
  )
);
create policy "managers can manage invoices"
on public.invoices for all to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = invoices.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin','manager')
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = invoices.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin','manager')
  )
);

drop policy if exists "invoice_site_calculations_company_access"
  on public.invoice_site_calculations;
drop policy if exists "company members can read invoice site calculations"
  on public.invoice_site_calculations;
drop policy if exists "managers can manage invoice site calculations"
  on public.invoice_site_calculations;
create policy "company members can read invoice site calculations"
on public.invoice_site_calculations for select to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = invoice_site_calculations.company_id
      and cm.user_id = auth.uid()
  )
);
create policy "managers can manage invoice site calculations"
on public.invoice_site_calculations for all to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = invoice_site_calculations.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin','manager')
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = invoice_site_calculations.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin','manager')
  )
);

drop policy if exists "invoice_detail_lines_company_access"
  on public.invoice_detail_lines;
drop policy if exists "company members can read invoice detail lines"
  on public.invoice_detail_lines;
drop policy if exists "managers can manage invoice detail lines"
  on public.invoice_detail_lines;
create policy "company members can read invoice detail lines"
on public.invoice_detail_lines for select to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = invoice_detail_lines.company_id
      and cm.user_id = auth.uid()
  )
);
create policy "managers can manage invoice detail lines"
on public.invoice_detail_lines for all to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = invoice_detail_lines.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin','manager')
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = invoice_detail_lines.company_id
      and cm.user_id = auth.uid()
      and cm.role::text in ('owner','admin','manager')
  )
);
