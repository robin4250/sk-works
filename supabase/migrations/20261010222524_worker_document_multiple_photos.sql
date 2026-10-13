-- Additive multi-photo support. Preserve existing rows, history and upload pause.
set local lock_timeout = '5s';
alter table public.worker_document_statuses
 add column attachment_paths text[] not null default '{}';
alter table public.worker_document_status_history
 add column attachment_paths text[] not null default '{}';

-- Normalize legacy single-path writes and validate the complete current list.
-- No UPDATE/backfill: existing single-path data is read through its old column.
create function private.normalize_worker_document_photos()
returns trigger language plpgsql security invoker set search_path='' as $$
declare p text; expected_prefix text;
begin
 if tg_op='INSERT' then
  if cardinality(new.attachment_paths)=0 and new.attachment_path is not null then
   new.attachment_paths:=array[new.attachment_path];
  end if;
 elsif (new.attachment_path is distinct from old.attachment_path
   and new.attachment_paths is not distinct from old.attachment_paths)
   or (cardinality(new.attachment_paths)=0 and new.attachment_path is not null
       and new.attachment_paths is not distinct from old.attachment_paths) then
  new.attachment_paths:=case when new.attachment_path is null then '{}'::text[]
    else array[new.attachment_path] end;
 end if;
 if cardinality(new.attachment_paths)=0 then
  new.attachment_path:=null;
 else
  new.attachment_path:=new.attachment_paths[1];
 end if;
 if cardinality(new.attachment_paths)>20
   or array_ndims(new.attachment_paths)>1
   or (cardinality(new.attachment_paths)>0 and array_lower(new.attachment_paths,1)<>1)
   or cardinality(new.attachment_paths)<>(select count(distinct value) from unnest(new.attachment_paths) value) then
  raise exception 'Invalid document photo list' using errcode='22023';
 end if;
 expected_prefix:=new.company_id::text||'/'||new.worker_id::text||'/'||new.requirement_id::text||'/';
 foreach p in array new.attachment_paths loop
  if p is null or p='' or p not like expected_prefix||'%'
    or cardinality(string_to_array(p,'/'))<>5 then
   raise exception 'Document photo belongs to another worker or requirement' using errcode='22023';
  end if;
 end loop;
 return new;
end $$;
revoke all on function private.normalize_worker_document_photos() from public,anon,authenticated;
create trigger normalize_worker_document_photos
before insert or update on public.worker_document_statuses
for each row execute function private.normalize_worker_document_photos();

-- Add the complete list to the existing audit implementation, fail on drift.
-- Keep original operation/status/changed_by semantics and existing ACLs.
do $$
declare definition text; anchor text;
begin
 definition:=pg_get_functiondef('public.capture_worker_document_status_history()'::regprocedure);
 anchor:='attachment_path,';
 if (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>4 then
  raise exception 'Unexpected worker document audit definition';
 end if;
 definition:=regexp_replace(definition,E'(^|[\r\n])([ \t]*)attachment_path,','\1\2attachment_path,'||chr(10)||'\2attachment_paths,','g');
 definition:=replace(definition,'old.attachment_path,','old.attachment_path,'||chr(10)||'      old.attachment_paths,');
 definition:=replace(definition,'new.attachment_path,','new.attachment_path,'||chr(10)||'    new.attachment_paths,');
 execute definition;
end $$;

-- Older rows may predate audit history. Capture the original baseline before
-- a photo list changes, so a replacement never releases an unaudited old photo.
create function private.capture_worker_document_photo_baseline()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.worker_document_status_history(
  company_id,source_status_id,worker_id,requirement_id,operation,status,
  expires_at,original_verified,attachment_path,attachment_paths,notes,changed_by
 ) values(
  old.company_id,old.id,old.worker_id,old.requirement_id,'update',old.status,
  old.expires_at,old.original_verified,old.attachment_path,old.attachment_paths,
  old.notes,coalesce(auth.uid(),old.updated_by)
 );
 return new;
end $$;
revoke all on function private.capture_worker_document_photo_baseline() from public,anon,authenticated;
create trigger worker_document_photo_baseline
before update on public.worker_document_statuses
for each row when(old.attachment_path is distinct from new.attachment_path
 or old.attachment_paths is distinct from new.attachment_paths)
execute function private.capture_worker_document_photo_baseline();

-- Extend official retention without replacing the existing shared helper or
-- altering any permissive read/upload/table policy. Existing history continues
-- to protect legacy attachment_path. Every additional photo is protected too.
create function private.worker_document_photos_are_retained(p_path text)
returns boolean language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then return true; end if;
 return exists(select 1 from public.worker_document_statuses s
   where p_path=any(s.attachment_paths))
 or exists(select 1 from public.worker_document_status_history h
   where p_path=any(h.attachment_paths));
end $$;
revoke all on function private.worker_document_photos_are_retained(text) from public,anon;
grant execute on function private.worker_document_photos_are_retained(text) to authenticated;
create policy worker_document_multiple_photos_no_delete on storage.objects
as restrictive for delete to authenticated
using(bucket_id<>'worker-documents' or not private.worker_document_photos_are_retained(name));
create policy worker_document_multiple_photos_no_overwrite on storage.objects
as restrictive for update to authenticated
using(bucket_id<>'worker-documents' or not private.worker_document_photos_are_retained(name))
with check(bucket_id<>'worker-documents' or not private.worker_document_photos_are_retained(name));
