-- Additive only: preserve the existing front/back columns and all permissions.
alter table public.worker_qualifications
  add column if not exists attachment_extra_paths text[] not null default '{}';
comment on column public.worker_qualifications.attachment_extra_paths is
  'Ordered private qualification certificate photos after the legacy front/back images';
