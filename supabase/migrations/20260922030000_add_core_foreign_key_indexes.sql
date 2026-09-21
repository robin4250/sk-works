create index if not exists attendance_entries_site_id_idx
  on public.attendance_entries(site_id);

create index if not exists attendance_entries_worker_id_idx
  on public.attendance_entries(worker_id);

create index if not exists daily_reports_site_id_idx
  on public.daily_reports(site_id);

create index if not exists daily_report_edit_requests_report_id_idx
  on public.daily_report_edit_requests(report_id);

create index if not exists daily_report_edit_approvals_approver_user_id_idx
  on public.daily_report_edit_approvals(approver_user_id);

create index if not exists company_approval_assignees_user_id_idx
  on public.company_approval_assignees(user_id);

create index if not exists employee_registration_invites_worker_id_idx
  on public.employee_registration_invites(worker_id);

create index if not exists employee_registration_invites_created_by_idx
  on public.employee_registration_invites(created_by);

create index if not exists employee_registration_invites_approved_by_idx
  on public.employee_registration_invites(approved_by);

create index if not exists employee_registration_invites_replace_approver_idx
  on public.employee_registration_invites(replace_approval_assignee_user_id);

create index if not exists invoices_customer_id_idx
  on public.invoices(customer_id);

create index if not exists chat_attachments_message_id_idx
  on public.chat_attachments(message_id);
