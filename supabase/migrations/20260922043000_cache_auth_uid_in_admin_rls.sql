alter policy "company members can read company"
on public.companies
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = companies.id
      and cm.user_id = (select auth.uid())
  )
);

alter policy "owners and admins can delete company"
on public.companies
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = companies.id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
);

alter policy "owners and admins can update company"
on public.companies
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = companies.id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
)
with check (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = companies.id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
);

alter policy "company managers can read feature permissions"
on public.member_feature_permissions
using (
  user_id = (select auth.uid())
  or exists (
    select 1
    from public.company_members cm
    where cm.company_id = member_feature_permissions.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
);

alter policy "owners and admins can manage feature permissions"
on public.member_feature_permissions
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = member_feature_permissions.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
)
with check (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = member_feature_permissions.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
);

alter policy "company members can read module settings"
on public.company_module_settings
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = company_module_settings.company_id
      and cm.user_id = (select auth.uid())
  )
);

alter policy "owners and admins can insert module settings"
on public.company_module_settings
with check (
  updated_by = (select auth.uid())
  and exists (
    select 1
    from public.company_members cm
    where cm.company_id = company_module_settings.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
);

alter policy "owners and admins can update module settings"
on public.company_module_settings
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = company_module_settings.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
)
with check (
  updated_by = (select auth.uid())
  and exists (
    select 1
    from public.company_members cm
    where cm.company_id = company_module_settings.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
);

alter policy "owners and admins can read line binding audit"
on public.line_binding_audit
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = line_binding_audit.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
);

alter policy "owners and admins can read line binding claims"
on public.line_binding_claims
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = line_binding_claims.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
);

alter policy "company members can create non-direct communication groups"
on public.communication_groups
with check (
  group_type = any (array['company'::text,'site'::text])
  and exists (
    select 1
    from public.company_members cm
    where cm.company_id = communication_groups.company_id
      and cm.user_id = (select auth.uid())
  )
);

alter policy "company members can read attendance verification settings"
on public.attendance_verification_settings
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = attendance_verification_settings.company_id
      and cm.user_id = (select auth.uid())
  )
);
