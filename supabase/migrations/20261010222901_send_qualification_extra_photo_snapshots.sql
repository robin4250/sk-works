-- Requires company and worker attachment_paths additive migrations. Existing deliveries remain immutable.
CREATE OR REPLACE FUNCTION private.company_document_exchange(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c uuid; cn text; target uuid; tn text; token uuid; did uuid; x jsonb; r record; item record; ancestry jsonb; fid uuid; count_items integer:=0; exchange_path text; exchange_photo_index integer; qualification_extra_path text; qualification_extra_index integer;
begin
 if auth.uid() is null then raise exception 'ログインしてください。'; end if;
 select m.company_id,co.name into c,cn from public.company_members m join public.companies co on co.id=m.company_id
 where m.user_id=auth.uid() and m.role::text in ('owner','admin') limit 1;
 if c is null then raise exception '会社の管理者だけが操作できます。';end if;
 if p_action='issue' then
  insert into private.document_receive_codes(company_id,created_by) values(c,auth.uid()) returning code into token;
  return jsonb_build_object('code',token,'company_name',cn,'expires_days',7);
 elsif p_action='resolve' then
  select rc.company_id,co.name into target,tn from private.document_receive_codes rc join public.companies co on co.id=rc.company_id
  where rc.code=(p_data->>'code')::uuid and rc.expires_at>now() and rc.used_at is null;
  if target is null or target=c then raise exception '有効な相手会社の受取コードを入力してください。';end if;
  return jsonb_build_object('company_name',tn);
 elsif p_action='list' then
  return coalesce((select jsonb_agg(to_jsonb(d)||jsonb_build_object('received',d.recipient_company_id=c) order by d.created_at desc)
   from private.document_deliveries d where d.recipient_company_id=c or d.sender_company_id=c),'[]'::jsonb);
 elsif p_action='items' then
  if not exists(select 1 from private.document_deliveries d where d.id=(p_data->>'id')::uuid and (d.recipient_company_id=c or d.sender_company_id=c)) then raise exception 'この提出書類は確認できません。';end if;
  return coalesce((select jsonb_agg(to_jsonb(i) order by i.name) from private.document_delivery_items i where i.delivery_id=(p_data->>'id')::uuid),'[]'::jsonb);
 elsif p_action='data_items' then
  if not exists(select 1 from private.document_deliveries d where d.id=(p_data->>'id')::uuid and (d.recipient_company_id=c or d.sender_company_id=c)) then raise exception 'この提出データは確認できません。';end if;
  return coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at,i.id) from private.company_data_delivery_items i where i.delivery_id=(p_data->>'id')::uuid),'[]'::jsonb);
 elsif p_action='sources' then
  return coalesce((select jsonb_agg(v) from (
   select jsonb_build_object('id',d.id,'kind','company','name',d.name,'group',cn) v from public.company_required_documents d
   where d.company_id=c and d.attachment_path is not null and d.is_active and d.scope='upstream'
   union all
   select jsonb_build_object('id',d.id,'kind','archive','name',d.name,'group',f.name) from public.partner_archive_documents d
   join public.partner_archive_folders f on f.id=d.folder_id where d.company_id=c and d.attachment_path is not null and d.is_active
   union all
   select jsonb_build_object(
     'id',s.id,
     'kind','worker_document',
     'name',w.name||' / '||dr.name,
     'group',w.name,
     'worker_id',s.worker_id
   )
   from public.worker_document_statuses s
   join public.document_requirements dr on dr.id=s.requirement_id
   join public.workers w on w.id=s.worker_id
   where s.company_id=c
     and w.company_id=c
     and dr.company_id=c
     and dr.scope='upstream'
     and dr.is_active
     and s.attachment_path is not null
     and s.status in ('submitted','verified')
   union all
   select jsonb_build_object(
     'id',q.id,
     'kind','worker_qualification',
     'name',w.name||' / '||qm.name,
     'group',w.name,
     'worker_id',q.worker_id
   )
   from public.worker_qualifications q
   join public.qualification_master qm on qm.id=q.qualification_master_id
   join public.workers w on w.id=q.worker_id
   where q.company_id=c
     and w.company_id=c
     and qm.company_id=c
   union all
   select jsonb_build_object(
     'id',w.id,
     'kind','worker_personnel',
     'name',w.name,
     'group',cn,
     'worker_id',w.id
   )
   from public.workers w
   where w.company_id=c and w.status='active'
  ) s),'[]'::jsonb);
 elsif p_action<>'send' then raise exception '操作を確認してください。';end if;
 did:=(p_data->>'request_id')::uuid;
 if did is null then raise exception '送信をやり直してください。';end if;
 -- Network retries return the same result and never send twice.
 if exists(select 1 from private.document_deliveries d where d.id=did and d.sender_company_id=c and d.sent_by=auth.uid()) then return jsonb_build_object('id',did);end if;
 if jsonb_typeof(p_data->'items') is distinct from 'array' then raise exception '書類を選択してください。';end if;
 if jsonb_array_length(p_data->'items') not between 1 and 100 or length(coalesce(p_data->>'note',''))>2000 then raise exception '書類は1〜100件、案内は2000文字以内にしてください。';end if;
 token:=(p_data->>'code')::uuid;
 select rc.company_id into target from private.document_receive_codes rc where rc.code=token and rc.expires_at>now() and rc.used_at is null for update;
 if target is null or target=c then raise exception '受取コードが無効・使用済みです。相手管理者に確認してください。';end if;
 select name into tn from public.companies where id=target;
 insert into private.document_deliveries(id,sender_company_id,recipient_company_id,sender_name,recipient_name,sent_by,note)
 values(did,c,target,cn,tn,auth.uid(),coalesce(p_data->>'note',''));
 for x in select value from jsonb_array_elements(p_data->'items') loop
  if x->>'kind'='received' then
   select i.* into r from private.document_delivery_items i join private.document_deliveries d on d.id=i.delivery_id
   where i.id=(x->>'id')::uuid and d.recipient_company_id=c;
   if not found then raise exception '再提出できる受領書類がありません。';end if;
   ancestry:=jsonb_build_array(cn)||r.company_path;
   if jsonb_array_length(ancestry)>32 then raise exception '所属関係が長すぎます。';end if;
   insert into private.document_delivery_items(delivery_id,name,bucket,path,company_path,source_item_id,expires_at)
   values(did,r.name,r.bucket,r.path,ancestry,r.id,r.expires_at);
  elsif x->>'kind'='received_data' then
   select i.* into r
   from private.company_data_delivery_items i
   join private.document_deliveries d on d.id=i.delivery_id
   where i.id=(x->>'id')::uuid and d.recipient_company_id=c;
   if not found then raise exception '再提出できる受領データがありません。';end if;
   ancestry:=jsonb_build_array(cn)||r.company_path;
   if jsonb_array_length(ancestry)>32 then raise exception '所属関係が長すぎます。';end if;
   insert into private.company_data_delivery_items(delivery_id,payload_kind,payload,company_path,source_item_id)
   values(did,r.payload_kind,r.payload,ancestry,r.id);
  elsif x->>'kind'='worker_personnel' then
   select w.* into r
   from public.workers w
   where w.id=(x->>'id')::uuid
     and w.company_id=c
     and w.status='active';
   if not found then raise exception '送信できる人員情報がありません。';end if;
   ancestry:=jsonb_build_array(cn);
   insert into private.company_data_delivery_items(delivery_id,payload_kind,payload,company_path)
   values(
     did,
     'personnel',
     jsonb_build_object(
       'source_worker_id',r.id,
       'name',r.name,
       'kana',r.kana,
       'phone',r.phone,
       'email',r.email,
       'affiliation',r.affiliation,
       'role',r.role,
       'experience_years',r.experience_years
     ),
     ancestry
   );

   for item in
    select q.*,qm.name qualification_name,qm.issuer master_issuer
    from public.worker_qualifications q
    join public.qualification_master qm on qm.id=q.qualification_master_id
    where q.company_id=c
      and q.worker_id=r.id
      and qm.company_id=c
   loop
    insert into private.company_data_delivery_items(delivery_id,payload_kind,payload,company_path)
    values(
      did,
      'qualification',
      jsonb_build_object(
        'source_worker_id',item.worker_id,
        'source_qualification_id',item.id,
        'worker_name',r.name,
        'qualification_name',item.qualification_name,
        'certificate_number',item.certificate_number,
        'issuer',coalesce(item.issuer,item.master_issuer),
        'issued_at',item.issued_at,
        'expires_at',item.expires_at,
        'notes',item.notes,
        'attachment_paths',to_jsonb(array_remove(array[item.attachment_path,item.attachment_back_path]||item.attachment_extra_paths,null))
      ),
      ancestry
    );
    if item.attachment_path is not null then
     if not exists(select 1 from storage.objects o where o.bucket_id='qualification-certificates' and o.name=item.attachment_path) then raise exception '資格証ファイルが見つかりません。';end if;
     insert into private.document_delivery_items(delivery_id,name,bucket,path,company_path,expires_at)
     values(did,r.name||' / '||item.qualification_name,'qualification-certificates',item.attachment_path,ancestry,item.expires_at);
    end if;
    if item.attachment_back_path is not null then
     if not exists(select 1 from storage.objects o where o.bucket_id='qualification-certificates' and o.name=item.attachment_back_path) then raise exception '資格証裏面ファイルが見つかりません。';end if;
     insert into private.document_delivery_items(delivery_id,name,bucket,path,company_path,expires_at)
     values(did,r.name||' / '||item.qualification_name||'（裏面）','qualification-certificates',item.attachment_back_path,ancestry,item.expires_at);
    end if;
    qualification_extra_index:=2;
    foreach qualification_extra_path in array item.attachment_extra_paths loop
     qualification_extra_index:=qualification_extra_index+1;
     if not exists(select 1 from storage.objects o where o.bucket_id='qualification-certificates' and o.name=qualification_extra_path) then
       raise exception '資格証追加写真ファイルが見つかりません。';
     end if;
     insert into private.document_delivery_items(delivery_id,name,bucket,path,company_path,expires_at)
     values(did,r.name||' / '||item.qualification_name||'（写真'||qualification_extra_index::text||'）','qualification-certificates',qualification_extra_path,ancestry,item.expires_at);
    end loop;
   end loop;

   for item in
    select s.*,dr.name document_name
    from public.worker_document_statuses s
    join public.document_requirements dr on dr.id=s.requirement_id
    where s.company_id=c
      and s.worker_id=r.id
      and dr.company_id=c
      and dr.scope='upstream'
      and dr.is_active
      and s.attachment_path is not null
      and s.status in ('submitted','verified')
   loop
    exchange_photo_index:=0;
    foreach exchange_path in array case when cardinality(item.attachment_paths)>0
        then item.attachment_paths else array[item.attachment_path] end loop
     exchange_photo_index:=exchange_photo_index+1;
     if not exists(select 1 from storage.objects o where o.bucket_id='worker-documents' and o.name=exchange_path) then raise exception '添付ファイルが見つかりません。';end if;
     insert into private.document_delivery_items(delivery_id,name,bucket,path,company_path,expires_at)
     values(did,r.name||' / '||item.document_name||case when exchange_photo_index=1 then '' else '（写真'||exchange_photo_index::text||'）' end,'worker-documents',exchange_path,ancestry,item.expires_at);
    end loop;
   end loop;
  elsif x->>'kind'='worker_qualification' then
   select
     q.*,
     qm.name qualification_name,
     qm.issuer master_issuer,
     w.name worker_name
   into r
   from public.worker_qualifications q
   join public.qualification_master qm on qm.id=q.qualification_master_id
   join public.workers w on w.id=q.worker_id
   where q.id=(x->>'id')::uuid
     and q.company_id=c
     and w.company_id=c
     and qm.company_id=c;
   if not found then raise exception '送信できる資格情報がありません。';end if;
   ancestry:=jsonb_build_array(cn);
   insert into private.company_data_delivery_items(delivery_id,payload_kind,payload,company_path)
   values(
     did,
     'qualification',
     jsonb_build_object(
       'source_worker_id',r.worker_id,
       'source_qualification_id',r.id,
       'worker_name',r.worker_name,
       'qualification_name',r.qualification_name,
       'certificate_number',r.certificate_number,
       'issuer',coalesce(r.issuer,r.master_issuer),
       'issued_at',r.issued_at,
       'expires_at',r.expires_at,
       'notes',r.notes,
        'attachment_paths',to_jsonb(array_remove(array[r.attachment_path,r.attachment_back_path]||r.attachment_extra_paths,null))
     ),
     ancestry
   );
   if r.attachment_path is not null then
    if not exists(select 1 from storage.objects o where o.bucket_id='qualification-certificates' and o.name=r.attachment_path) then raise exception '資格証ファイルが見つかりません。';end if;
    insert into private.document_delivery_items(delivery_id,name,bucket,path,company_path,expires_at)
    values(did,r.worker_name||' / '||r.qualification_name,'qualification-certificates',r.attachment_path,ancestry,r.expires_at);
   end if;
   if r.attachment_back_path is not null then
    if not exists(select 1 from storage.objects o where o.bucket_id='qualification-certificates' and o.name=r.attachment_back_path) then raise exception '資格証裏面ファイルが見つかりません。';end if;
    insert into private.document_delivery_items(delivery_id,name,bucket,path,company_path,expires_at)
    values(did,r.worker_name||' / '||r.qualification_name||'（裏面）','qualification-certificates',r.attachment_back_path,ancestry,r.expires_at);
   end if;
    qualification_extra_index:=2;
    foreach qualification_extra_path in array r.attachment_extra_paths loop
     qualification_extra_index:=qualification_extra_index+1;
     if not exists(select 1 from storage.objects o where o.bucket_id='qualification-certificates' and o.name=qualification_extra_path) then
       raise exception '資格証追加写真ファイルが見つかりません。';
     end if;
     insert into private.document_delivery_items(delivery_id,name,bucket,path,company_path,expires_at)
     values(did,r.worker_name||' / '||r.qualification_name||'（写真'||qualification_extra_index::text||'）','qualification-certificates',qualification_extra_path,ancestry,r.expires_at);
    end loop;
  else
   if x->>'kind'='company' then
    select d.name,d.attachment_path,d.attachment_paths,d.expires_at,'company-required-documents'::text bucket,null::uuid folder_id into r
    from public.company_required_documents d where d.id=(x->>'id')::uuid and d.company_id=c and d.is_active and d.scope='upstream';
   elsif x->>'kind'='archive' then
    select d.name,d.attachment_path,array[d.attachment_path]::text[] attachment_paths,d.expires_at,'partner-archive-documents'::text bucket,d.folder_id into r
    from public.partner_archive_documents d where d.id=(x->>'id')::uuid and d.company_id=c and d.is_active;
   elsif x->>'kind'='worker_document' then
    select w.name||' / '||dr.name as name,s.attachment_path,s.attachment_paths,s.expires_at,'worker-documents'::text bucket,null::uuid folder_id into r
    from public.worker_document_statuses s
    join public.document_requirements dr on dr.id=s.requirement_id
    join public.workers w on w.id=s.worker_id
    where s.id=(x->>'id')::uuid
      and s.company_id=c
      and w.company_id=c
      and dr.company_id=c
      and dr.scope='upstream'
      and dr.is_active
      and s.status in ('submitted','verified');
   else raise exception '書類の種類を確認してください。';end if;
   if not found or r.attachment_path is null then raise exception '送信できる添付書類がありません。';end if;
   ancestry:='[]'::jsonb;fid:=r.folder_id;count_items:=0;
   while fid is not null loop
    select f.parent_id,jsonb_build_array(f.name)||ancestry into fid,ancestry from public.partner_archive_folders f where f.id=fid and f.company_id=c;
    count_items:=count_items+1;
    if count_items>30 then raise exception '所属関係を確認してください。';end if;
   end loop;
   ancestry:=jsonb_build_array(cn)||ancestry;
   exchange_photo_index:=0;
   foreach exchange_path in array case when cardinality(r.attachment_paths)>0
       then r.attachment_paths else array[r.attachment_path] end loop
    exchange_photo_index:=exchange_photo_index+1;
    if not exists(select 1 from storage.objects o where o.bucket_id=r.bucket and o.name=exchange_path) then raise exception '添付ファイルが見つかりません。';end if;
    insert into private.document_delivery_items(delivery_id,name,bucket,path,company_path,expires_at)
    values(did,r.name||case when exchange_photo_index=1 then '' else '（写真'||exchange_photo_index::text||'）' end,r.bucket,exchange_path,ancestry,r.expires_at);
   end loop;
  end if;
 end loop;
 update private.document_receive_codes set used_at=now() where code=token;
 insert into public.app_notifications(company_id,recipient_user_id,kind,title,body,action_key,action_id)
 select target,m.user_id,'info','協力会社から書類が届きました',cn||'からの提出書類を確認してください。','company_document_delivery',did
 from public.company_members m where m.company_id=target and m.role::text in ('owner','admin');
 return jsonb_build_object('id',did);
end;
$function$
;
