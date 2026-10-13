alter table public.worker_qualifications
  add column if not exists attachment_back_path text;

comment on column public.worker_qualifications.attachment_path
  is 'Qualification certificate front image path (legacy-compatible front side).';

comment on column public.worker_qualifications.attachment_back_path
  is 'Optional qualification certificate back image path.';
