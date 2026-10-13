revoke update on table public.chat_attachments from authenticated;

revoke insert, update, delete
  on table public.communication_group_members from authenticated;

revoke insert on table public.companies from authenticated;
revoke delete on table public.company_module_settings from authenticated;

revoke insert, update, delete
  on table public.document_template_library from authenticated;
revoke insert, update, delete
  on table public.document_template_library_versions from authenticated;

revoke insert, update, delete
  on table public.line_binding_audit from authenticated;
revoke insert, update, delete
  on table public.line_binding_claims from authenticated;
revoke insert, update, delete
  on table public.line_group_bindings from authenticated;

revoke delete on table public.user_profiles from authenticated;

revoke insert, update, delete
  on table public.worker_document_status_history from authenticated;
