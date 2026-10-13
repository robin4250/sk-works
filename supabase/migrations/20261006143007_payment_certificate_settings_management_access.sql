-- Allow management roles to configure payment certificates.
drop policy if exists partner_payment_settings_admin_insert
on public.partner_payment_settings;
drop policy if exists partner_payment_settings_admin_update
on public.partner_payment_settings;
drop policy if exists partner_payment_settings_admin_delete
on public.partner_payment_settings;

create policy partner_payment_settings_management_insert
on public.partner_payment_settings
for insert
to authenticated
with check (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id=partner_payment_settings.company_id
      and cm.user_id=(select auth.uid())
      and cm.role::text in ('owner','admin','manager')
  )
);

create policy partner_payment_settings_management_update
on public.partner_payment_settings
for update
to authenticated
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id=partner_payment_settings.company_id
      and cm.user_id=(select auth.uid())
      and cm.role::text in ('owner','admin','manager')
  )
)
with check (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id=partner_payment_settings.company_id
      and cm.user_id=(select auth.uid())
      and cm.role::text in ('owner','admin','manager')
  )
);

create policy partner_payment_settings_management_delete
on public.partner_payment_settings
for delete
to authenticated
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id=partner_payment_settings.company_id
      and cm.user_id=(select auth.uid())
      and cm.role::text in ('owner','admin','manager')
  )
);
