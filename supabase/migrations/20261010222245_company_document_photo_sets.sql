-- Additive: legacy attachment_path remains the first attachment for existing readers.
alter table public.company_required_documents
  add column if not exists attachment_paths text[] not null default '{}';

create or replace function public.validate_company_document_photo_paths()
returns trigger language plpgsql security invoker set search_path = public
as $$
declare p text;
begin
  -- Older clients intentionally replace only the primary file.
  if tg_op = 'UPDATE' and new.attachment_paths is not distinct from old.attachment_paths
      and new.attachment_path is distinct from old.attachment_path then
    new.attachment_paths := case when new.attachment_path is null then '{}'::text[]
      else array[new.attachment_path] end;
  end if;
  if cardinality(new.attachment_paths) > 0 then
    if new.attachment_path is distinct from new.attachment_paths[1] then
      raise exception 'The primary attachment must match the first photo';
    end if;
    foreach p in array new.attachment_paths loop
      if p is null or p = '' or p not like new.company_id::text || '/' || new.id::text || '/%'
         or p like '%/../%' then
        raise exception 'Invalid company document photo path';
      end if;
    end loop;
    if cardinality(new.attachment_paths) <> (
      select count(distinct x) from unnest(new.attachment_paths) x
    ) then raise exception 'Duplicate company document photo'; end if;
  end if;
  return new;
end;
$$;
create trigger validate_company_document_photo_paths
before insert or update of attachment_paths, attachment_path, company_id
on public.company_required_documents
for each row execute function public.validate_company_document_photo_paths();

-- Same company/member role predicate as the existing single-file read policy.
-- Existing policy and delivery-snapshot access remain intact.
create policy company_document_photo_files_read on storage.objects
for select to authenticated using (
  bucket_id = 'company-required-documents' and exists (
    select 1 from public.company_required_documents d
    join public.company_members m on m.company_id = d.company_id
    where objects.name = any(d.attachment_paths)
      and m.user_id = (select auth.uid())
      and m.role::text = any(array['owner','admin'])
  )
);
