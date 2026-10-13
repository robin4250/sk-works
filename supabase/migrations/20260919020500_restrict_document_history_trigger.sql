revoke execute on function public.capture_worker_document_status_history() from anon;
revoke execute on function public.capture_worker_document_status_history() from authenticated;
revoke execute on function public.capture_worker_document_status_history() from public;
grant execute on function public.capture_worker_document_status_history() to service_role;
