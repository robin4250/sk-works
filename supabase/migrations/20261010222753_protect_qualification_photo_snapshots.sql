-- Photo-specific protection. Existing qualification visibility and editing RLS stays unchanged.
create table private.qualification_photo_history (
  id bigint generated always as identity primary key,
  qualification_id uuid not null,
  company_id uuid not null,
  worker_id uuid not null,
  paths text[] not null,
  recorded_at timestamptz not null default now()
);
alter table private.qualification_photo_history enable row level security;
revoke all on private.qualification_photo_history from public,anon,authenticated;
create index qualification_photo_history_paths on private.qualification_photo_history using gin(paths);

create function private.validate_qualification_extra_photos() returns trigger
language plpgsql set search_path='' security definer as $$
declare photo text; prefix text;
begin
  prefix:=new.company_id::text||'/'||new.worker_id::text||'/'||new.id::text||'/';
  if array_ndims(new.attachment_extra_paths)>1 then
    raise exception '追加写真の形式が不正です。' using errcode='22023';
  end if;
  foreach photo in array new.attachment_extra_paths loop
    if photo is null or left(photo,length(prefix)) is distinct from prefix
      or position('..' in photo)>0 or photo=prefix then
      raise exception '追加写真はこの資格の保存先を指定してください。' using errcode='22023';
    end if;
    if not exists(select 1 from storage.objects o where o.bucket_id='qualification-certificates' and o.name=photo) then
      raise exception '追加写真ファイルが見つかりません。' using errcode='22023';
    end if;
  end loop;
  if cardinality(new.attachment_extra_paths)<>(select count(distinct p) from unnest(new.attachment_extra_paths) p) then
    raise exception '追加写真が重複しています。' using errcode='22023';
  end if;
  return new;
end $$;
revoke all on function private.validate_qualification_extra_photos() from public,anon,authenticated;
create trigger qualification_extra_photo_validation
before insert or update of attachment_extra_paths,company_id,worker_id,id on public.worker_qualifications
for each row execute function private.validate_qualification_extra_photos();

create function private.archive_qualification_photos() returns trigger
language plpgsql set search_path='' security definer as $$
begin
  if tg_op<>'INSERT' then
    insert into private.qualification_photo_history(qualification_id,company_id,worker_id,paths)
    values(old.id,old.company_id,old.worker_id,array_remove(array[old.attachment_path,old.attachment_back_path]||old.attachment_extra_paths,null));
  end if;
  if tg_op<>'DELETE' then
    insert into private.qualification_photo_history(qualification_id,company_id,worker_id,paths)
    values(new.id,new.company_id,new.worker_id,array_remove(array[new.attachment_path,new.attachment_back_path]||new.attachment_extra_paths,null));
  end if;
  return null;
end $$;
revoke all on function private.archive_qualification_photos() from public,anon,authenticated;
create trigger qualification_photo_history_capture
  after insert or delete or update of attachment_path,attachment_back_path,attachment_extra_paths,company_id,worker_id,id
  on public.worker_qualifications for each row execute function private.archive_qualification_photos();

-- Backfill references, not blobs; no existing data is modified or deleted.
insert into private.qualification_photo_history(qualification_id,company_id,worker_id,paths)
select id,company_id,worker_id,array_remove(array[attachment_path,attachment_back_path]||attachment_extra_paths,null)
from public.worker_qualifications;

create function private.qualification_photo_unreferenced(p_bucket text,p_name text) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare referenced boolean;
begin
 if p_bucket<>'qualification-certificates' then return true; end if;
 if exists(
   select 1 from public.worker_qualifications q
    where q.attachment_path=p_name or q.attachment_back_path=p_name or q.attachment_extra_paths @> array[p_name]
   union all select 1 from private.qualification_photo_history h where h.paths @> array[p_name]
   union all select 1 from private.document_delivery_items i where i.bucket=p_bucket and i.path=p_name
 ) then return false; end if;
 -- Production approval history predates this additive feature. Preserve every side.
 if to_regclass('private.worker_qualification_history') is not null then
   execute 'select exists(select 1 from private.worker_qualification_history h
     where h.snapshot->>''attachment_path''=$1 or h.snapshot->>''attachment_back_path''=$1
       or coalesce(h.snapshot->''attachment_extra_paths'',''[]''::jsonb) ? $1)'
   into referenced using p_name;
   if referenced then return false; end if;
 end if;
 if to_regclass('private.qualification_submissions') is not null then
   execute 'select exists(select 1 from private.qualification_submissions s
     where s.attachment_path=$1 or s.previous->>''attachment_path''=$1
       or s.previous->>''attachment_back_path''=$1
       or coalesce(s.previous->''attachment_extra_paths'',''[]''::jsonb) ? $1)'
   into referenced using p_name;
   if referenced then return false; end if;
 end if;
 return true;
end
$$;
revoke all on function private.qualification_photo_unreferenced(text,text) from public,anon;
grant execute on function private.qualification_photo_unreferenced(text,text) to authenticated;
create policy qualification_referenced_photo_delete_guard on storage.objects as restrictive for delete to authenticated
using(private.qualification_photo_unreferenced(bucket_id,name));
create policy qualification_referenced_photo_update_guard on storage.objects as restrictive for update to authenticated
using(private.qualification_photo_unreferenced(bucket_id,name))
with check(private.qualification_photo_unreferenced(bucket_id,name));
