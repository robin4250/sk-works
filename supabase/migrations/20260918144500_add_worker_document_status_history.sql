create table if not exists public.worker_document_status_history (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  source_status_id uuid,
  worker_id uuid not null,
  requirement_id uuid not null,
  operation text not null
    check (operation in ('insert', 'update', 'delete')),
  status text not null
    check (status in ('not_submitted', 'submitted', 'verified', 'missing', 'expired')),
  expires_at date,
  original_verified boolean not null default false,
  attachment_path text,
  notes text,
  changed_by uuid references auth.users(id) on delete set null,
  changed_at timestamptz not null default now()
);

create index if not exists worker_document_status_history_company_worker_idx
  on public.worker_document_status_history(company_id, worker_id, changed_at desc);
create index if not exists worker_document_status_history_requirement_idx
  on public.worker_document_status_history(company_id, requirement_id, changed_at desc);

alter table public.worker_document_status_history enable row level security;

create policy "company members can read worker document status history"
on public.worker_document_status_history
for select
to authenticated
using (
  exists (
    select 1 from public.company_members cm
    where cm.company_id = worker_document_status_history.company_id
      and cm.user_id = auth.uid()
  )
);

create or replace function public.capture_worker_document_status_history()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    insert into public.worker_document_status_history (
      company_id,
      source_status_id,
      worker_id,
      requirement_id,
      operation,
      status,
      expires_at,
      original_verified,
      attachment_path,
      notes,
      changed_by
    ) values (
      old.company_id,
      old.id,
      old.worker_id,
      old.requirement_id,
      'delete',
      old.status,
      old.expires_at,
      old.original_verified,
      old.attachment_path,
      old.notes,
      coalesce(auth.uid(), old.updated_by)
    );
    return old;
  end if;

  insert into public.worker_document_status_history (
    company_id,
    source_status_id,
    worker_id,
    requirement_id,
    operation,
    status,
    expires_at,
    original_verified,
    attachment_path,
    notes,
    changed_by
  ) values (
    new.company_id,
    new.id,
    new.worker_id,
    new.requirement_id,
    lower(tg_op),
    new.status,
    new.expires_at,
    new.original_verified,
    new.attachment_path,
    new.notes,
    coalesce(auth.uid(), new.updated_by)
  );
  return new;
end;
$$;

drop trigger if exists audit_worker_document_status_changes
on public.worker_document_statuses;

create trigger audit_worker_document_status_changes
after insert or update or delete on public.worker_document_statuses
for each row
execute function public.capture_worker_document_status_history();
