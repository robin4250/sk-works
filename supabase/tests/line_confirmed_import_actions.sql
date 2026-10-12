create table private.line_attendance_submissions (
 company_id uuid not null,worker_id uuid not null,work_date date not null,
 draft_id uuid not null references private.line_import_drafts(id),revision integer not null,
 request_id uuid not null references public.attendance_correction_requests(id),
 active boolean not null default true,
 primary key(company_id,worker_id,work_date,request_id)
);
create unique index line_attendance_one_active_day on private.line_attendance_submissions(company_id,worker_id,work_date) where active;
create table private.line_invoice_submissions (
 company_id uuid not null,customer_id uuid not null,work_month date not null,
 draft_id uuid not null references private.line_import_drafts(id),revision integer not null,
 invoice_id uuid not null references public.invoices(id),
 primary key(company_id,customer_id,work_month)
);
alter table private.line_attendance_submissions enable row level security;
alter table private.line_invoice_submissions enable row level security;
revoke all on private.line_attendance_submissions,private.line_invoice_submissions from public,anon,authenticated;
create function private.require_current_line_import_draft(p_draft_id uuid,p_revision integer,p_target text) returns private.line_import_drafts
language plpgsql security definer set search_path='' as $$
declare draft private.line_import_drafts; access jsonb; source jsonb; r jsonb;
begin
 select * into draft from private.line_import_drafts where id=p_draft_id for update;
 if draft.id is null or draft.target<>p_target then raise exception 'LINE確認データが見つかりません。' using errcode='22023';end if;
 access:=private.line_import_access(draft.group_id,p_target);
 if not (access->>'can_edit')::boolean then raise exception 'LINE登録権限がありません。' using errcode='42501';end if;
 perform 1 from private.line_import_feature_settings where target=p_target for share;
 if not coalesce((select enabled from private.line_import_feature_settings where target=p_target),false) then raise exception 'LINE追加機能はOFFです。' using errcode='42501';end if;
 if draft.revision<>p_revision or not draft.confirmed or nullif(trim(draft.note_comparison),'') is null then raise exception 'LINE確認データを保存し直してください。' using errcode='40001';end if;
 if draft.source_kind in ('received','mixed') then
  for source in select value from jsonb_array_elements(draft.source_messages) loop
   if (draft.source_kind='received' or source->>'source_type'='received') and not exists(select 1 from public.chat_messages m where m.id::text=source->>'id' and m.company_id=draft.company_id and m.communication_group_id=draft.group_id and m.origin='line' and m.body=source->>'body' and m.sent_at=(source->>'sent_at')::timestamptz) then raise exception '元のLINE投稿が変わりました。再取込してください。' using errcode='40001';end if;
  end loop;
 end if;
 for r in select value from jsonb_array_elements(draft.candidate_rows) where coalesce(value->>'excluded','false')<>'true' loop
  if (r->>'work_date')::date > (now() at time zone 'Asia/Tokyo')::date then raise exception '未来の作業は確認して登録できません。' using errcode='22023';end if;
  if not exists(select 1 from public.workers w where w.id=(r->>'worker_id')::uuid and w.company_id=draft.company_id and w.name=r->>'worker_name' and w.status='active')
  or not exists(select 1 from public.sites s where s.id=(r->>'site_id')::uuid and s.company_id=draft.company_id and s.name=r->>'site_name') then raise exception '作業員・現場の登録情報を確認してください。' using errcode='40001';end if;
 end loop;
 return draft;
end $$;
revoke all on function private.require_current_line_import_draft(uuid,integer,text) from public,anon,authenticated,service_role;

create function private.line_invoice_preview(p_draft_id uuid,p_revision integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare draft private.line_import_drafts; rows jsonb; customer record; quote jsonb; quotes jsonb:='[]'; data jsonb;
begin
 draft:=private.require_current_line_import_draft(p_draft_id,p_revision,'invoice');
 select jsonb_agg(jsonb_build_object('company_id',draft.company_id,'site_id',(r->>'site_id')::uuid,'work_date',(r->>'work_date')::date,
 'work_category',coalesce(r->>'work_category',case when r->>'night_work'='true' then 'night' else 'day' end),
 'base_man_days',(r->>'man_days')::numeric,'overtime_hours',(r->>'overtime_hours')::numeric,'early_hours',(r->>'early_hours')::numeric,
 'allowance_names',coalesce(r->'allowance_names','[]'::jsonb))) into rows
 from jsonb_array_elements(draft.candidate_rows) r where coalesce(r->>'excluded','false')<>'true';
 if rows is null or not exists(select 1 from jsonb_array_elements(rows)) then raise exception '請求の対象がありません。' using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(rows) r join public.sites s on s.id=(r->>'site_id')::uuid where s.customer_id is null or not exists(select 1 from public.customers c where c.id=s.customer_id and c.company_id=draft.company_id)) then raise exception '現場の取引会社を設定してください。' using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(draft.candidate_rows) r where coalesce(r->>'excluded','false')<>'true' and r->>'steel_allowance'='true' and jsonb_array_length(coalesce(r->'allowance_names','[]'))=0) then raise exception 'PC・鉄骨手当の登録名称を確認してください。' using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(draft.candidate_rows) r
  cross join lateral jsonb_array_elements_text(coalesce(r->'allowance_names','[]')) allowance(name)
  left join public.site_financial_settings fs on fs.site_id=(r->>'site_id')::uuid and fs.company_id=draft.company_id
  where coalesce(r->>'excluded','false')<>'true' and (
   (allowance.name=fs.billing_allowance_1_name and fs.billing_allowance_1_amount_yen>0) or
   (allowance.name=fs.billing_allowance_2_name and fs.billing_allowance_2_amount_yen>0) or
   (allowance.name=fs.billing_allowance_3_name and fs.billing_allowance_3_amount_yen>0)
  ) is not true) then raise exception '現場に登録した手当の名称・単価を確認してください。' using errcode='22023';end if;
 for customer in select distinct c.id,c.name,c.billing_address from public.customers c join public.sites s on s.customer_id=c.id and s.company_id=c.company_id
 where c.company_id=draft.company_id and exists(select 1 from jsonb_array_elements(rows) r where (r->>'site_id')::uuid=s.id) order by c.id loop
  quote:=private.line_confirmed_invoice_components(draft.company_id,customer.id,draft.work_month,rows);
  if jsonb_array_length(quote->'sites')=0 then raise exception '請求明細を確認してください。' using errcode='22023';end if;
  quotes:=quotes||jsonb_build_array(quote||jsonb_build_object('customer_id',customer.id,'customer_name',customer.name,'customer_address',coalesce(customer.billing_address,'')));
 end loop;
 data:=jsonb_build_object('draft_id',draft.id,'revision',draft.revision,'work_month',draft.work_month,'quotes',quotes);
 return data||jsonb_build_object('fingerprint',md5(data::text));
end $$;
create function private.create_line_invoices(p_command_id uuid,p_draft_id uuid,p_revision integer,p_expected_fingerprint text) returns jsonb language plpgsql security definer set search_path='' as $$
declare draft private.line_import_drafts; cid uuid; payload jsonb; receipt private.line_import_commands; preview jsonb; quote jsonb; iid uuid; ids jsonb:='[]'; result jsonb; snapshot jsonb;
begin
 select company_id into cid from private.line_import_drafts where id=p_draft_id;
 if cid is null or p_command_id is null then raise exception 'LINE請求データがありません。' using errcode='22023';end if;
 perform private.line_import_access((select group_id from private.line_import_drafts where id=p_draft_id),'invoice');
 payload:=jsonb_build_object('action','invoice','draft',p_draft_id,'revision',p_revision,'fingerprint',p_expected_fingerprint);
 perform pg_advisory_xact_lock(hashtextextended('line-import-command:'||cid::text||auth.uid()::text||p_command_id::text,0));
 select * into receipt from private.line_import_commands where company_id=cid and actor_id=auth.uid() and command_id=p_command_id;
 if found then if receipt.payload is distinct from payload then raise exception 'command reused with different content' using errcode='22023';end if;return receipt.result;end if;
 draft:=private.require_current_line_import_draft(p_draft_id,p_revision,'invoice');
 preview:=private.line_invoice_preview(p_draft_id,p_revision);
 if preview->>'fingerprint' is distinct from p_expected_fingerprint then raise exception '請求単価・税率・確認データが変わりました。金額を再確認してください。' using errcode='40001';end if;
 -- Serialize with every invoice INSERT/UPDATE, including existing manual and automatic inputs.
 -- No existing invoice is ever overwritten by a LINE import.
 for quote in select value from jsonb_array_elements(preview->'quotes') order by value->>'customer_id' loop
  perform pg_advisory_xact_lock(hashtextextended('invoice:'||cid::text||(quote->>'customer_id')||draft.work_month::text,0));
 end loop;
 lock table public.invoices in share row exclusive mode;
 for quote in select value from jsonb_array_elements(preview->'quotes') loop
  if exists(select 1 from public.invoices where company_id=cid and customer_id=(quote->>'customer_id')::uuid and billing_period_start<=((draft.work_month+interval '1 month - 1 day')::date) and billing_period_end>=draft.work_month)
    or exists(select 1 from private.line_invoice_submissions where company_id=cid and customer_id=(quote->>'customer_id')::uuid and work_month=draft.work_month) then raise exception '同じ取引会社・月の請求書があります。既存の請求書を確認してください。' using errcode='22023';end if;
  snapshot:=jsonb_build_object('customer_name',quote->>'customer_name','customer_address',quote->>'customer_address','billing_period',to_char(draft.work_month,'YYYY年MM月'),
   'tax_rate_bps',quote->'tax_rate_bps','subtotal',quote->'subtotal','tax',quote->'tax','grand_total',quote->'grand_total','sites',quote->'sites','detail_mode','consolidated_only',
   'line_import_evidence',jsonb_build_object('draft_id',draft.id,'revision',draft.revision,'source_kind',draft.source_kind,'source_ids',(select jsonb_agg(s->>'id') from jsonb_array_elements(draft.source_messages) s)));
  insert into public.invoices(company_id,customer_id,billing_period_start,billing_period_end,status,subtotal,tax,welfare_amount,adjustments,grand_total,snapshot,detail_mode,automatic_calculation)
  values(cid,(quote->>'customer_id')::uuid,draft.work_month,(draft.work_month+interval '1 month - 1 day')::date,'draft',(quote->>'subtotal')::numeric,(quote->>'tax')::numeric,(quote->>'welfare')::numeric,0,(quote->>'grand_total')::numeric,snapshot,'consolidated_only',false) returning id into iid;
  insert into private.line_invoice_submissions values(cid,(quote->>'customer_id')::uuid,draft.work_month,draft.id,draft.revision,iid);
  ids:=ids||jsonb_build_array(jsonb_build_object('invoice_id',iid,'customer_id',quote->>'customer_id','grand_total',quote->'grand_total'));
 end loop;
 result:=jsonb_build_object('invoices',ids);
 insert into private.line_import_commands values(cid,auth.uid(),p_command_id,payload,result);
 return result;
end $$;
create function private.submit_line_attendance(p_command_id uuid,p_draft_id uuid,p_revision integer,p_signer_name text,p_signature_json jsonb,p_worker_ids uuid[]) returns jsonb language plpgsql security definer set search_path='' as $$
declare draft private.line_import_drafts; cid uuid; payload jsonb; receipt private.line_import_commands; r jsonb; items jsonb:='[]'; request_id uuid; result jsonb;
begin
 select company_id into cid from private.line_import_drafts where id=p_draft_id;
 if cid is null or p_command_id is null then raise exception 'LINE出勤データがありません。' using errcode='22023';end if;
 perform private.line_import_access((select group_id from private.line_import_drafts where id=p_draft_id),'attendance');
 payload:=jsonb_build_object('action','attendance','draft',p_draft_id,'revision',p_revision,'signer',p_signer_name,'signature',p_signature_json,'workers',to_jsonb(p_worker_ids));
 perform pg_advisory_xact_lock(hashtextextended('line-import-command:'||cid::text||auth.uid()::text||p_command_id::text,0));
 select * into receipt from private.line_import_commands where company_id=cid and actor_id=auth.uid() and command_id=p_command_id;
 if found then if receipt.payload is distinct from payload then raise exception 'command reused with different content' using errcode='22023';end if;return receipt.result;end if;
 draft:=private.require_current_line_import_draft(p_draft_id,p_revision,'attendance');
 if p_worker_ids is not null and (cardinality(p_worker_ids)=0 or exists(select 1 from unnest(p_worker_ids) wid where wid is null or not exists(select 1 from jsonb_array_elements(draft.candidate_rows) rr where rr->>'worker_id'=wid::text and coalesce(rr->>'excluded','false')<>'true'))) then raise exception '申請する作業員を確認してください。' using errcode='22023';end if;
 if nullif(trim(p_signer_name),'') is null or p_signature_json is null then raise exception '申請の署名を入力してください。' using errcode='22023';end if;
 -- Existing manual submissions do not take a LINE lock; table locks close the
 -- gap while this wrapper checks duplicates and creates its ordinary request.
 lock table public.attendance_correction_requests,public.attendance_entries in share row exclusive mode;
 for r in select value from jsonb_array_elements(draft.candidate_rows) where coalesce(value->>'excluded','false')<>'true' and (p_worker_ids is null or (value->>'worker_id')::uuid=any(p_worker_ids)) order by value->>'worker_id',value->>'work_date' loop
  if (r->>'work_date')::date >= (now() at time zone 'Asia/Tokyo')::date then raise exception '過去の日付だけをまとめて申請できます。' using errcode='22023';end if;
  update private.line_attendance_submissions sub set active=false where sub.company_id=cid and sub.worker_id=(r->>'worker_id')::uuid and sub.work_date=(r->>'work_date')::date and sub.active
   and exists(select 1 from public.attendance_correction_requests req where req.id=sub.request_id and req.status='rejected');
  if exists(select 1 from public.attendance_entries where company_id=cid and worker_id=(r->>'worker_id')::uuid and work_date=(r->>'work_date')::date)
   or exists(select 1 from private.line_attendance_submissions where company_id=cid and worker_id=(r->>'worker_id')::uuid and work_date=(r->>'work_date')::date and active)
   or exists(select 1 from public.attendance_correction_items i join public.attendance_correction_requests req on req.id=i.request_id
    where req.company_id=cid and req.request_kind='past_attendance' and req.status in ('draft','submitted') and (i.proposed_snapshot->>'workerId')=(r->>'worker_id') and replace(i.proposed_snapshot->>'date','/','-')=r->>'work_date') then raise exception '同日の出勤または申請があります。勤務修正から確認してください。' using errcode='22023';end if;
  if r->>'steel_allowance'='true' and jsonb_array_length(coalesce(r->'allowance_names','[]'))=0 then raise exception 'PC・鉄骨手当の登録名称を確認してください。' using errcode='22023';end if;
  items:=items||jsonb_build_array(jsonb_build_object('date',r->>'work_date','workerName',r->>'worker_name','siteName',r->>'site_name','manDays',r->'man_days','overtimeHours',r->'overtime_hours','earlyHours',r->'early_hours',
   'workCategory',coalesce(r->>'work_category',case when r->>'night_work'='true' then 'night' else 'day' end),'nightHours',0,'allowanceYen',0,'allowanceNames',coalesce(r->'allowance_names','[]'),
   'notes','LINE確認取込 '||draft.id::text||' / v'||draft.revision::text||' / '||(r->>'source_message_id')));
 end loop;
 if jsonb_array_length(items)<1 or jsonb_array_length(items)>100 then raise exception '1～100件をまとめて申請してください。' using errcode='22023';end if;
 request_id:=public.submit_past_attendance_request(items,p_signer_name,p_signature_json);
 insert into private.line_attendance_submissions(company_id,worker_id,work_date,draft_id,revision,request_id)
 select cid,(item.value->>'worker_id')::uuid,(item.value->>'work_date')::date,draft.id,draft.revision,request_id from jsonb_array_elements(draft.candidate_rows) item where coalesce(item.value->>'excluded','false')<>'true' and (p_worker_ids is null or (item.value->>'worker_id')::uuid=any(p_worker_ids));
 result:=jsonb_build_object('request_id',request_id,'status','submitted','item_count',jsonb_array_length(items));
 insert into private.line_import_commands values(cid,auth.uid(),p_command_id,payload,result);
 return result;
end $$;
create function public.line_invoice_preview(p_draft_id uuid,p_revision integer) returns jsonb language sql security invoker set search_path='' as $$select private.line_invoice_preview(p_draft_id,p_revision)$$;
create function public.create_line_invoices(p_command_id uuid,p_draft_id uuid,p_revision integer,p_expected_fingerprint text) returns jsonb language sql security invoker set search_path='' as $$select private.create_line_invoices(p_command_id,p_draft_id,p_revision,p_expected_fingerprint)$$;
create function public.submit_line_attendance(p_command_id uuid,p_draft_id uuid,p_revision integer,p_signer_name text,p_signature_json jsonb,p_worker_ids uuid[]) returns jsonb language sql security invoker set search_path='' as $$select private.submit_line_attendance(p_command_id,p_draft_id,p_revision,p_signer_name,p_signature_json,p_worker_ids)$$;
revoke all on function private.line_invoice_preview(uuid,integer),private.create_line_invoices(uuid,uuid,integer,text),private.submit_line_attendance(uuid,uuid,integer,text,jsonb,uuid[]) from public,anon;
revoke all on function public.line_invoice_preview(uuid,integer),public.create_line_invoices(uuid,uuid,integer,text),public.submit_line_attendance(uuid,uuid,integer,text,jsonb,uuid[]) from public,anon;
grant execute on function private.line_invoice_preview(uuid,integer),private.create_line_invoices(uuid,uuid,integer,text),private.submit_line_attendance(uuid,uuid,integer,text,jsonb,uuid[]) to authenticated;
grant execute on function public.line_invoice_preview(uuid,integer),public.create_line_invoices(uuid,uuid,integer,text),public.submit_line_attendance(uuid,uuid,integer,text,jsonb,uuid[]) to authenticated;
