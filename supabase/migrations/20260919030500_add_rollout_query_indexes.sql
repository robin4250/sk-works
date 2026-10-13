-- Target the query paths used heavily by chat/LINE, attendance and invoices.
-- Indexes are additive and safe to apply on the empty/early production database.

create index if not exists chat_messages_company_group_sent_idx
  on public.chat_messages(company_id, communication_group_id, sent_at);

create index if not exists communication_groups_company_site_idx
  on public.communication_groups(company_id, site_id);

create index if not exists line_binding_claims_company_group_status_idx
  on public.line_binding_claims(company_id, communication_group_id, status, expires_at);

create index if not exists line_binding_audit_binding_idx
  on public.line_binding_audit(binding_id);

create index if not exists line_binding_audit_group_idx
  on public.line_binding_audit(communication_group_id, occurred_at desc);

create index if not exists attendance_entries_company_worker_date_idx
  on public.attendance_entries(company_id, worker_id, work_date);

create index if not exists attendance_entries_company_site_date_idx
  on public.attendance_entries(company_id, site_id, work_date);

create index if not exists invoices_company_customer_period_idx
  on public.invoices(company_id, customer_id, billing_period_start desc);

create index if not exists invoice_site_calculations_invoice_idx
  on public.invoice_site_calculations(invoice_id);

create index if not exists invoice_site_calculations_company_site_idx
  on public.invoice_site_calculations(company_id, site_id);

create index if not exists invoice_detail_lines_calculation_sort_idx
  on public.invoice_detail_lines(invoice_site_calculation_id, sort_order);

create index if not exists customers_company_name_idx
  on public.customers(company_id, name);

create index if not exists workers_company_name_idx
  on public.workers(company_id, name);

create index if not exists sites_company_name_idx
  on public.sites(company_id, name);
