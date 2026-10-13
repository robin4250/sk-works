create index if not exists app_notifications_company_id_idx
on public.app_notifications using btree (company_id);

create index if not exists attendance_entries_created_by_idx
on public.attendance_entries using btree (created_by);

create index if not exists attendance_entries_updated_by_idx
on public.attendance_entries using btree (updated_by);

create index if not exists attendance_verification_settings_updated_by_idx
on public.attendance_verification_settings using btree (updated_by);

create index if not exists attendance_verifications_created_by_idx
on public.attendance_verifications using btree (created_by);

create index if not exists daily_report_edit_requests_requested_by_idx
on public.daily_report_edit_requests using btree (requested_by);

create index if not exists daily_reports_created_by_idx
on public.daily_reports using btree (created_by);

create index if not exists daily_reports_updated_by_idx
on public.daily_reports using btree (updated_by);

create index if not exists document_requirements_company_template_id_idx
on public.document_requirements using btree (company_template_id);
