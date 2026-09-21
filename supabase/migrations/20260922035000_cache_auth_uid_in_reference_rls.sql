alter policy "company members can read company document template versions"
on public.company_document_template_versions
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = company_document_template_versions.company_id
      and cm.user_id = (select auth.uid())
  )
);

alter policy "owners and admins can manage company document template versions"
on public.company_document_template_versions
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = company_document_template_versions.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
)
with check (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = company_document_template_versions.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
  and exists (
    select 1
    from public.company_document_templates ct
    where ct.id = company_document_template_versions.company_template_id
      and ct.company_id = company_document_template_versions.company_id
  )
);

alter policy "company members can read company document templates"
on public.company_document_templates
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = company_document_templates.company_id
      and cm.user_id = (select auth.uid())
  )
);

alter policy "owners and admins can manage company document templates"
on public.company_document_templates
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = company_document_templates.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
)
with check (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = company_document_templates.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
);

alter policy "company members can read daily report workers"
on public.daily_report_workers
using (
  exists (
    select 1
    from public.daily_reports dr
    join public.company_members cm on cm.company_id = dr.company_id
    where dr.id = daily_report_workers.report_id
      and cm.user_id = (select auth.uid())
  )
);

alter policy "company members can read document requirements"
on public.document_requirements
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = document_requirements.company_id
      and cm.user_id = (select auth.uid())
  )
);

alter policy "owners and admins can manage document requirements"
on public.document_requirements
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = document_requirements.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
)
with check (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = document_requirements.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
);

alter policy "company members can read partner companies"
on public.partner_companies
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = partner_companies.company_id
      and cm.user_id = (select auth.uid())
  )
);

alter policy "company members can read qualification master"
on public.qualification_master
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = qualification_master.company_id
      and cm.user_id = (select auth.uid())
  )
);

alter policy "owners and admins can manage qualification master"
on public.qualification_master
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = qualification_master.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
)
with check (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = qualification_master.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
);

alter policy "company members can read qualification aliases"
on public.qualification_master_aliases
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = qualification_master_aliases.company_id
      and cm.user_id = (select auth.uid())
  )
);

alter policy "owners and admins can manage qualification aliases"
on public.qualification_master_aliases
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = qualification_master_aliases.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
)
with check (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = qualification_master_aliases.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin')
  )
  and exists (
    select 1
    from public.qualification_master qm
    where qm.id = qualification_master_aliases.qualification_master_id
      and qm.company_id = qualification_master_aliases.company_id
  )
);

alter policy "worker or people manager can read worker qualifications"
on public.worker_qualifications
using (
  exists (
    select 1
    from public.workers w
    where w.id = worker_qualifications.worker_id
      and w.company_id = worker_qualifications.company_id
      and w.user_id = (select auth.uid())
  )
  or private.has_company_feature(
    worker_qualifications.company_id,
    'can_manage_people'
  )
);
