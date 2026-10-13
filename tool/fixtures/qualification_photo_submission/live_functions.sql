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
 select auth.uid() is not null and exists(select 1 from private.qualification_submissions r where exists(select 1 from public.company_members m where m.company_id=r.company_id and m.user_id=auth.uid()) and ((p_upload and r.upload_path=p_path) or (not p_upload and (r.attachment_path=p_path or r.previous->>'attachment_path'=p_path))) and ((p_upload and r.status='draft' and r.requested_by=auth.uid() and exists(select 1 from public.workers w where w.id=r.worker_id and w.company_id=r.company_id and w.user_id=auth.uid())) or (not p_upload and (r.requested_by=auth.uid() or exists(select 1 from public.company_members m where m.company_id=r.company_id and m.user_id=auth.uid() and m.role::text in ('owner','admin')) or exists(select 1 from public.company_approval_assignees a where a.company_id=r.company_id and a.user_id=auth.uid())))))
$function$;
