-- Mirrors production migration 20261004105505.
-- Splits write policies so SELECT does not evaluate duplicate permissive policies
-- and keeps the attention RPC under RLS as a security-invoker function.

drop policy if exists partner_payment_settings_management_write on public.partner_payment_settings;
drop policy if exists payment_certificates_management_write on public.payment_certificates;

create policy partner_payment_settings_admin_insert
on public.partner_payment_settings for insert
to authenticated
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = partner_payment_settings.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
);

create policy partner_payment_settings_admin_update
on public.partner_payment_settings for update
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = partner_payment_settings.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = partner_payment_settings.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
);

create policy partner_payment_settings_admin_delete
on public.partner_payment_settings for delete
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = partner_payment_settings.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
);

create policy payment_certificates_admin_insert
on public.payment_certificates for insert
to authenticated
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = payment_certificates.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
);

create policy payment_certificates_admin_update
on public.payment_certificates for update
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = payment_certificates.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
)
with check (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = payment_certificates.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
);

create policy payment_certificates_admin_delete
on public.payment_certificates for delete
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = payment_certificates.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
);

grant select, insert, update, delete on public.partner_payment_settings to authenticated;
grant select, insert, update, delete on public.payment_certificates to authenticated;
grant select on public.generation_setting_issues to authenticated;

alter function public.current_generation_setting_attention() security invoker;
