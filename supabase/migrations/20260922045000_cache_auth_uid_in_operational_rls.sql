alter policy "accessible members can insert chat attachments"
on public.chat_attachments
with check (
  uploaded_by = (select auth.uid())
  and private.can_access_communication_group(communication_group_id)
);

alter policy "authors can delete own chat attachments"
on public.chat_attachments
using (
  uploaded_by = (select auth.uid())
  and private.can_access_communication_group(communication_group_id)
);

alter policy "accessible members can send sko chat messages"
on public.chat_messages
with check (
  origin = 'sk_works'
  and sender_user_id = (select auth.uid())
  and private.can_access_communication_group(communication_group_id)
);

alter policy "authors can delete own accessible chat messages"
on public.chat_messages
using (
  origin = 'sk_works'
  and sender_user_id = (select auth.uid())
  and private.can_access_communication_group(communication_group_id)
);

alter policy "authors can update own accessible chat messages"
on public.chat_messages
using (
  origin = 'sk_works'
  and sender_user_id = (select auth.uid())
  and private.can_access_communication_group(communication_group_id)
)
with check (
  origin = 'sk_works'
  and sender_user_id = (select auth.uid())
  and private.can_access_communication_group(communication_group_id)
);

alter policy "requester or authorized approver can read edit requests"
on public.daily_report_edit_requests
using (
  requested_by = (select auth.uid())
  or private.has_company_feature(company_id, 'can_approve_daily_report_edits')
);

alter policy "requester or authorized approver can read approvals"
on public.daily_report_edit_approvals
using (
  exists (
    select 1
    from public.daily_report_edit_requests req
    where req.id = daily_report_edit_approvals.request_id
      and (
        req.requested_by = (select auth.uid())
        or private.has_company_feature(
          req.company_id,
          'can_approve_daily_report_edits'
        )
      )
  )
);

alter policy "worker or people manager can read document statuses"
on public.worker_document_statuses
using (
  exists (
    select 1
    from public.workers w
    where w.id = worker_document_statuses.worker_id
      and w.company_id = worker_document_statuses.company_id
      and w.user_id = (select auth.uid())
  )
  or private.has_company_feature(company_id, 'can_manage_people')
);

alter policy "worker or people manager can read document status history"
on public.worker_document_status_history
using (
  exists (
    select 1
    from public.workers w
    where w.id = worker_document_status_history.worker_id
      and w.company_id = worker_document_status_history.company_id
      and w.user_id = (select auth.uid())
  )
  or private.has_company_feature(company_id, 'can_manage_people')
);

alter policy "company members can read site worker assignments"
on public.site_worker_assignments
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = site_worker_assignments.company_id
      and cm.user_id = (select auth.uid())
  )
);

alter policy "managers can manage site worker assignments"
on public.site_worker_assignments
using (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = site_worker_assignments.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin','manager')
  )
)
with check (
  exists (
    select 1
    from public.company_members cm
    where cm.company_id = site_worker_assignments.company_id
      and cm.user_id = (select auth.uid())
      and cm.role::text in ('owner','admin','manager')
  )
  and exists (
    select 1
    from public.workers w
    where w.id = site_worker_assignments.worker_id
      and w.company_id = site_worker_assignments.company_id
  )
  and exists (
    select 1
    from public.sites s
    where s.id = site_worker_assignments.site_id
      and s.company_id = site_worker_assignments.company_id
  )
);

alter policy "worker or attendance manager can create verification"
on public.attendance_verifications
with check (
  (
    exists (
      select 1
      from public.workers w
      where w.id = attendance_verifications.worker_id
        and w.company_id = attendance_verifications.company_id
        and w.user_id = (select auth.uid())
    )
    or private.has_company_feature(
      attendance_verifications.company_id,
      'can_manage_attendance'
    )
  )
  and exists (
    select 1
    from public.sites s
    where s.id = attendance_verifications.site_id
      and s.company_id = attendance_verifications.company_id
  )
);

alter policy "worker or attendance manager can read attendance verifications"
on public.attendance_verifications
using (
  exists (
    select 1
    from public.workers w
    where w.id = attendance_verifications.worker_id
      and w.company_id = attendance_verifications.company_id
      and w.user_id = (select auth.uid())
  )
  or private.has_company_feature(
    attendance_verifications.company_id,
    'can_manage_attendance'
  )
);
