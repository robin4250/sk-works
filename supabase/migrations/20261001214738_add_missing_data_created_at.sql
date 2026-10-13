alter table public.worker_document_statuses
  add column if not exists created_at timestamptz not null default now();

alter table public.company_required_documents
  add column if not exists created_at timestamptz not null default now();
