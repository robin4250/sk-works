-- Photo-only requests extend the existing submission/approval contract.
-- No public qualification UPDATE policy or license upload pilot is changed.
do $$
begin
 if md5(pg_get_functiondef('private.personal_qualification_submission(text,jsonb)'::regprocedure))<>'6d9a1bd6d1572f62f513c4e85551a247'
 or md5(pg_get_functiondef('private.qualification_submission_access(text,boolean)'::regprocedure))<>'6f3b76f453f7a012d076a6f71c12a5ea' then
  raise exception 'Qualification submission definition changed; review before deployment' using errcode='55000';
 end if;
 if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='worker_qualifications' and column_name='attachment_extra_paths') then
  raise exception 'Qualification extra photo migration is required';
 end if;
end $$;

do $$ begin
 if not exists(select 1 from pg_proc p where p.oid=to_regprocedure('private.validate_qualification_extra_photos()') and md5(p.prosrc)='7ac28165bcc386922ba55c4eb7bf4823') then raise exception 'Qualification photo validator changed; review before deployment' using errcode='55000';end if;
end $$;

alter table private.qualification_submissions
 add column photo_contract_version integer check(photo_contract_version=1),
 add column photo_cancelled boolean not null default false,
 add column photo_slots jsonb,
 add column photo_paths text[] not null default '{}',
 add column photo_upload_paths text[] not null default '{}';

create function private.qualification_photo_submission_result(r private.qualification_submissions)
returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('version',1,'id',r.id,'target_id',r.target_id,
  'status',r.status,'cancelled',r.photo_cancelled,'reason',r.reason,'requested_by',r.requested_by,'photo_paths',to_jsonb(r.photo_paths),
  'upload_paths',coalesce((select jsonb_agg(jsonb_build_object('index',s.ordinality-1,
   'path',r.photo_paths[s.ordinality::integer],'extension',s.slot->>'extension') order by s.ordinality)
   from jsonb_array_elements(r.photo_slots) with ordinality s(slot,ordinality)
   where s.slot ? 'extension'),'[]'::jsonb));
$$;
revoke all on function private.qualification_photo_submission_result(private.qualification_submissions) from public,anon,authenticated;

create function private.personal_qualification_photo_submission(p_action text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); cid uuid; can_review boolean; req private.qualification_submissions%rowtype;
 oldrow public.worker_qualifications%rowtype; snapshot jsonb; target uuid; request_id uuid;
 slots jsonb; slot jsonb; paths text[]:='{}'; uploads text[]:='{}'; oldpaths text[];
 path text; ext text; prefix text; idx integer:=0; upload_allowed boolean;
begin
 if uid is null then raise exception 'ログインが必要です';end if;
 select company_id into cid from public.company_members where user_id=uid limit 1;
 if cid is null then raise exception '所属会社がありません';end if;
 select exists(select 1 from public.company_members where company_id=cid and user_id=uid and role::text in ('owner','admin'))
  or exists(select 1 from public.company_approval_assignees where company_id=cid and user_id=uid) into can_review;
 -- Conservative capability: a restrictive INSERT gate must be reviewed before
 -- promising upload availability. The existing pilot policy remains untouched.
 select not exists(select 1 from pg_catalog.pg_policy p join pg_catalog.pg_class c on c.oid=p.polrelid
  join pg_catalog.pg_namespace n on n.oid=c.relnamespace
  where n.nspname='storage' and c.relname='objects' and p.polcmd in ('a','*') and not p.polpermissive)
  into upload_allowed;
 if p_action='photo_capability' then
  return jsonb_build_object('version',1,'photo_submission_available',true,'photo_upload_allowed',upload_allowed,'max_photos',20);
 end if;
 if p_action='prepare_photos' then
  target:=(p_data->>'target_id')::uuid;request_id:=(p_data->>'request_id')::uuid;slots:=p_data->'photo_slots';
  if target is null or request_id is null or jsonb_typeof(slots) is distinct from 'array'
   or jsonb_array_length(slots)>20 then raise exception '写真申請の対象・枚数を確認してください';end if;
  select * into req from private.qualification_submissions where id=request_id for update;
  if found then
   if req.company_id<>cid or req.requested_by is distinct from uid or req.target_id<>target
    or req.photo_contract_version is distinct from 1 or req.photo_slots is distinct from slots then
    raise exception '写真申請IDの内容が一致しません' using errcode='23505';
   end if;
   return private.qualification_photo_submission_result(req);
  end if;
  select q.* into oldrow from public.worker_qualifications q join public.workers w on w.id=q.worker_id and w.company_id=q.company_id
   join public.qualification_master m on m.id=q.qualification_master_id and m.company_id=q.company_id
   where q.id=target and q.company_id=cid and w.user_id=uid;
  if not found then raise exception '本人の登録済み資格だけ写真申請できます';end if;
  perform pg_advisory_xact_lock(hashtextextended(oldrow.worker_id::text||oldrow.qualification_master_id::text,0));
  select q.* into oldrow from public.worker_qualifications q join public.workers w on w.id=q.worker_id and w.company_id=q.company_id
   join public.qualification_master m on m.id=q.qualification_master_id and m.company_id=q.company_id
   where q.id=target and q.company_id=cid and w.user_id=uid
    and q.worker_id=oldrow.worker_id and q.qualification_master_id=oldrow.qualification_master_id for update of q;
  if not found then raise exception '写真申請の対象が変更されました';end if;
  select * into req from private.qualification_submissions where id=request_id;
  if found then
   if req.company_id<>cid or req.requested_by is distinct from uid or req.target_id<>target
    or req.photo_contract_version is distinct from 1 or req.photo_slots is distinct from slots then
    raise exception '写真申請IDの内容が一致しません' using errcode='23505';
   end if;
   return private.qualification_photo_submission_result(req);
  end if;
  snapshot:=to_jsonb(oldrow);oldpaths:=array_remove(array[oldrow.attachment_path,oldrow.attachment_back_path]||oldrow.attachment_extra_paths,null);
  prefix:=cid::text||'/'||oldrow.worker_id::text||'/'||target::text||'/';
  for slot in select value from jsonb_array_elements(slots) loop
   idx:=idx+1;
   if jsonb_typeof(slot) is distinct from 'object' or (slot ? 'existing_path')=(slot ? 'extension')
    or exists(select 1 from jsonb_object_keys(slot) k where k not in ('existing_path','extension')) then
    raise exception '写真の選択内容を確認してください';end if;
   if slot ? 'existing_path' then
    if jsonb_typeof(slot->'existing_path') is distinct from 'string' then raise exception '写真の保存先を確認してください';end if;
    path:=slot->>'existing_path';
    if path is null or not coalesce(path=any(oldpaths),false) then raise exception '登録済み写真だけ選択してください';end if;

   else
    ext:=slot->>'extension';
    if jsonb_typeof(slot->'extension') is distinct from 'string' or ext not in ('pdf','jpg','jpeg','png','heic','heif') then raise exception '写真またはPDFを選択してください';end if;
    if not upload_allowed then raise exception '資格写真の送信は現在停止しています';end if;
    path:=prefix||'submissions/'||request_id::text||'-'||idx::text||'.'||ext;
    if exists(select 1 from storage.objects where bucket_id='qualification-certificates' and name=path) then raise exception '写真の保存先が既に使用されています';end if;
    uploads:=array_append(uploads,path);
   end if;
   if path=any(paths) then raise exception '写真が重複しています';end if;
   paths:=array_append(paths,path);
  end loop;
  insert into private.qualification_submissions(id,company_id,worker_id,qualification_master_id,target_id,
   certificate_number,issuer,issued_at,expires_at,notes,requested_by,previous,attachment_path,
   photo_contract_version,photo_slots,photo_paths,photo_upload_paths)
  values(request_id,cid,oldrow.worker_id,oldrow.qualification_master_id,target,
   oldrow.certificate_number,oldrow.issuer,oldrow.issued_at,oldrow.expires_at,oldrow.notes,uid,snapshot,paths[1],1,slots,paths,uploads)
  returning * into req;
  return private.qualification_photo_submission_result(req);
 end if;
 select * into req from private.qualification_submissions where id=(p_data->>'id')::uuid and company_id=cid for update;
 if not found or req.photo_contract_version is distinct from 1 then raise exception '写真申請が見つかりません';end if;
 if p_action='get_photos' then
  if req.requested_by is distinct from uid and not(can_review and (req.status='pending' or (req.status in ('approved','rejected') and req.reviewed_by is not distinct from uid))) then raise exception '写真申請を確認できません';end if;
  return private.qualification_photo_submission_result(req);
 end if;
 if p_action='cancel_photos' then
  if req.requested_by is distinct from uid or not exists(select 1 from public.workers where id=req.worker_id and company_id=cid and user_id=uid) then raise exception 'この申請は取り消せません';end if;
  if req.photo_cancelled and req.status='rejected' then return private.qualification_photo_submission_result(req);end if;
  if req.status<>'draft' then raise exception '未送信の写真申請だけ取り消せます';end if;
  update private.qualification_submissions set status='rejected',photo_cancelled=true,reason='本人が未送信の写真申請を取り消しました' where id=req.id returning * into req;
  return private.qualification_photo_submission_result(req);
 end if;
 if p_action='submit_photos' then
  if req.requested_by is distinct from uid or not exists(select 1 from public.workers where id=req.worker_id and company_id=cid and user_id=uid) then raise exception 'この申請は送信できません';end if;
  if req.status in ('pending','approved') then return private.qualification_photo_submission_result(req);end if;
  if req.status<>'draft' then raise exception 'この申請は送信できません';end if;
 elsif p_action='approve_photos' then
  if not can_review or req.status<>'pending' then raise exception '承認権限または申請状態を確認してください';end if;
  perform pg_advisory_xact_lock(hashtextextended(req.worker_id::text||req.qualification_master_id::text,0));
  select to_jsonb(q) into snapshot from public.worker_qualifications q where q.id=req.target_id and q.worker_id=req.worker_id
   and q.qualification_master_id=req.qualification_master_id and q.company_id=cid for update;
  if snapshot is distinct from req.previous then raise exception '申請後に資格証が更新されました。再申請してください';end if;
  if not exists(select 1 from public.workers where id=req.worker_id and company_id=cid and user_id=req.requested_by) then raise exception '申請者の所属を確認してください';end if;
 else raise exception '操作を確認してください';end if;
 foreach path in array req.photo_paths loop
  if not exists(select 1 from storage.objects where bucket_id='qualification-certificates' and name=path) then raise exception '添付資格証が見つかりません。再申請してください';end if;
 end loop;
 if p_action='submit_photos' then
  update private.qualification_submissions set status='pending' where id=req.id returning * into req;
 else
  update public.worker_qualifications set attachment_path=req.photo_paths[1],attachment_back_path=req.photo_paths[2],
   attachment_extra_paths=coalesce(req.photo_paths[3:cardinality(req.photo_paths)],'{}'::text[]),updated_at=now()
   where id=req.target_id and company_id=cid;
  update private.qualification_submissions set status='approved',reviewed_by=uid,reviewed_at=now() where id=req.id returning * into req;
 end if;
 return private.qualification_photo_submission_result(req);
end $$;
revoke all on function private.personal_qualification_photo_submission(text,jsonb) from public,anon,authenticated;

-- References in draft, pending and terminal requests cannot be overwritten or
-- deleted. This composes with all existing live/history/delivery protections.
create function private.qualification_submission_photos_unreferenced(p_bucket text,p_path text)
returns boolean language sql stable security definer set search_path='' as $$
 select p_bucket<>'qualification-certificates' or not exists(select 1 from private.qualification_submissions r
  where p_path=any(r.photo_paths) or p_path=any(r.photo_upload_paths));
$$;
revoke all on function private.qualification_submission_photos_unreferenced(text,text) from public,anon;
grant execute on function private.qualification_submission_photos_unreferenced(text,text) to authenticated;
create policy qualification_submission_photo_delete_guard on storage.objects as restrictive for delete to authenticated
 using(private.qualification_submission_photos_unreferenced(bucket_id,name));
create policy qualification_submission_photo_update_guard on storage.objects as restrictive for update to authenticated
 using(private.qualification_submission_photos_unreferenced(bucket_id,name))
 with check(private.qualification_submission_photos_unreferenced(bucket_id,name));

CREATE OR REPLACE FUNCTION private.personal_qualification_submission(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid:=auth.uid();cid uuid;wid uuid;rid uuid;can_review boolean;req private.qualification_submissions%rowtype;oldrow jsonb;newpath text;ext text;target uuid;
begin
 if uid is null then raise exception 'ログインが必要です';end if;
 select company_id into cid from public.company_members where user_id=uid limit 1;
 if cid is null then raise exception '所属会社がありません';end if;
 select exists(select 1 from public.company_members where company_id=cid and user_id=uid and role::text in ('owner','admin')) or exists(select 1 from public.company_approval_assignees where company_id=cid and user_id=uid) into can_review;
 if p_action in ('photo_capability','prepare_photos','get_photos','cancel_photos') then
  return private.personal_qualification_photo_submission(p_action,p_data);
 end if;
 if p_action='list' then
  return coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object('worker_name',w.name,'qualification_name',d.name,'can_review',can_review) order by r.created_at desc) from private.qualification_submissions r join public.workers w on w.id=r.worker_id join public.qualification_master d on d.id=r.qualification_master_id where r.company_id=cid and r.status<>'draft' and ((can_review and r.status='pending') or r.requested_by=uid)),'[]');
 end if;
 if p_action='prepare' then
  wid:=(p_data->>'worker_id')::uuid;rid:=(p_data->>'qualification_master_id')::uuid;
  if not exists(select 1 from public.workers where id=wid and company_id=cid and user_id=uid) then raise exception '本人の資格証だけ申請できます';end if;
  if not exists(select 1 from public.qualification_master where id=rid and company_id=cid) then raise exception '資格証の種類を確認してください';end if;
  perform pg_advisory_xact_lock(hashtextextended(wid::text||rid::text,0));
  target:=nullif(p_data->>'target_id','')::uuid;
  if target is not null then
   select to_jsonb(s) into oldrow from public.worker_qualifications s where id=target and worker_id=wid and qualification_master_id=rid and company_id=cid for update;
   if oldrow is null then raise exception '変更対象の資格が見つかりません';end if;
  else
   if exists(select 1 from public.worker_qualifications where worker_id=wid and qualification_master_id=rid and company_id=cid) then raise exception '登録済みの資格から変更を申請してください';end if;
   target:=gen_random_uuid();
  end if;
  if exists(select 1 from public.qualification_master where id=rid and expiry_required) and nullif(p_data->>'expires_at','') is null then raise exception '有効期限を入力してください';end if;
  ext:=p_data->>'extension';
  if ext is not null and ext not in ('pdf','jpg','jpeg','png','heic','heif') then raise exception '写真またはPDFを選択してください';end if;
  insert into private.qualification_submissions(company_id,worker_id,qualification_master_id,target_id,certificate_number,issuer,issued_at,requested_by,previous,attachment_path,notes,expires_at)
  values(cid,wid,rid,target,p_data->>'certificate_number',p_data->>'issuer',nullif(p_data->>'issued_at','')::date,uid,oldrow,oldrow->>'attachment_path',p_data->>'notes',nullif(p_data->>'expires_at','')::date) returning * into req;
  if ext is not null then
   newpath:=cid::text||'/'||wid::text||'/'||rid::text||'/'||req.id::text||'/submission.'||ext;
   update private.qualification_submissions set upload_path=newpath,attachment_path=newpath where id=req.id;
  end if;
  return jsonb_build_object('id',req.id,'upload_path',newpath);
 end if;
 select * into req from private.qualification_submissions where id=(p_data->>'id')::uuid and company_id=cid for update;
 if not found then raise exception '申請が見つかりません';end if;
 if p_action='submit' and req.photo_contract_version=1 then
  return private.personal_qualification_photo_submission('submit_photos',p_data);
 end if;
 if p_action='submit' then
  if req.requested_by<>uid or req.status<>'draft' then raise exception 'この申請は送信できません';end if;
  if req.attachment_path is null or not exists(select 1 from storage.objects where bucket_id='qualification-certificates' and name=req.attachment_path) then raise exception '写真またはPDFを登録してください';end if;
  update private.qualification_submissions set status='pending' where id=req.id;
  return '{}';
 end if;
 if not can_review or req.status<>'pending' then raise exception '承認権限または申請状態を確認してください';end if;
 if p_action='reject' then
  if nullif(trim(p_data->>'reason'),'') is null then raise exception '差し戻す理由が必要です';end if;
  update private.qualification_submissions set status='rejected',reason=p_data->>'reason',reviewed_by=uid,reviewed_at=now() where id=req.id;return '{}';
 end if;
 if p_action<>'approve' then raise exception '操作を確認してください';end if;
 if req.photo_contract_version=1 then
  return private.personal_qualification_photo_submission('approve_photos',p_data);
 end if;
 perform pg_advisory_xact_lock(hashtextextended(req.worker_id::text||req.qualification_master_id::text,0));
 select to_jsonb(s) into oldrow from public.worker_qualifications s where id=req.target_id and worker_id=req.worker_id and qualification_master_id=req.qualification_master_id and company_id=cid for update;
 if oldrow is distinct from req.previous then raise exception '申請後に資格証が更新されました。再申請してください';end if;
 if not exists(select 1 from public.workers where id=req.worker_id and company_id=cid and user_id=req.requested_by) then raise exception '申請者の所属を確認してください';end if;
 if not exists(select 1 from storage.objects where bucket_id='qualification-certificates' and name=req.attachment_path) then raise exception '添付資格証が見つかりません。再申請してください';end if;
 if req.previous is null then
  if exists(select 1 from public.worker_qualifications where company_id=cid and worker_id=req.worker_id and qualification_master_id=req.qualification_master_id) then raise exception 'すでに資格が登録されています。再申請してください';end if;
  insert into public.worker_qualifications(id,company_id,worker_id,qualification_master_id,certificate_number,issuer,issued_at,expires_at,attachment_path,notes)
  values(req.target_id,cid,req.worker_id,req.qualification_master_id,req.certificate_number,req.issuer,req.issued_at,req.expires_at,req.attachment_path,req.notes);
 else
  update public.worker_qualifications set certificate_number=req.certificate_number,issuer=req.issuer,issued_at=req.issued_at,expires_at=req.expires_at,attachment_path=req.attachment_path,notes=req.notes,updated_at=now() where id=req.target_id and company_id=cid;
 end if;
 update private.qualification_submissions set status='approved',reviewed_by=uid,reviewed_at=now() where id=req.id;
 return '{}';
end $function$;


CREATE OR REPLACE FUNCTION private.qualification_submission_access(p_path text, p_upload boolean)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select auth.uid() is not null and exists(select 1 from private.qualification_submissions r where exists(select 1 from public.company_members m where m.company_id=r.company_id and m.user_id=auth.uid()) and ((p_upload and (r.upload_path=p_path or (r.photo_contract_version=1 and p_path=any(r.photo_upload_paths)))) or (not p_upload and (r.attachment_path=p_path or (r.photo_contract_version=1 and p_path=any(r.photo_paths)) or r.previous->>'attachment_path'=p_path or r.previous->>'attachment_back_path'=p_path or coalesce(r.previous->'attachment_extra_paths','[]'::jsonb) ? p_path))) and ((p_upload and r.status='draft' and r.requested_by=auth.uid() and exists(select 1 from public.workers w where w.id=r.worker_id and w.company_id=r.company_id and w.user_id=auth.uid())) or (not p_upload and (r.requested_by=auth.uid() or exists(select 1 from public.company_members m where m.company_id=r.company_id and m.user_id=auth.uid() and m.role::text in ('owner','admin')) or exists(select 1 from public.company_approval_assignees a where a.company_id=r.company_id and a.user_id=auth.uid())))))
$function$;


-- Allow only already-owned legacy photos to be reordered on the same qualification.
create or replace function private.validate_qualification_extra_photos() returns trigger
language plpgsql set search_path='' security definer as $$
declare photo text; prefix text;
begin
  prefix:=new.company_id::text||'/'||new.worker_id::text||'/'||new.id::text||'/';
  if array_ndims(new.attachment_extra_paths)>1 then
    raise exception '追加写真の形式が不正です。' using errcode='22023';
  end if;
  foreach photo in array new.attachment_extra_paths loop
    if photo is null or position('..' in photo)>0 or photo=prefix
      or (left(photo,length(prefix)) is distinct from prefix and not (
       tg_op='UPDATE' and new.id is not distinct from old.id
       and new.company_id is not distinct from old.company_id
       and new.worker_id is not distinct from old.worker_id
       and left(photo,length(new.company_id::text||'/'||new.worker_id::text||'/'))=new.company_id::text||'/'||new.worker_id::text||'/'
       and photo=any(array_remove(array[old.attachment_path,old.attachment_back_path]||old.attachment_extra_paths,null)))) then
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
