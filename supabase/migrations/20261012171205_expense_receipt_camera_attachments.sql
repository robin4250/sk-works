-- Private receipt attachments. Upload before submission, link on the same fixed
-- submission UUID, and keep the reservation on failures for an exact retry.
create table private.expense_receipts (
 claim_id uuid primary key,company_id uuid not null,applicant_id uuid not null,created_by uuid not null,
 object_path text not null unique,sha256 text not null check(sha256 ~ '^[a-f0-9]{64}$'),
 size_bytes integer not null check(size_bytes between 1 and 10485760),
 mime_type text not null check(mime_type in ('image/jpeg','image/png')),
 attached boolean not null default false,created_at timestamptz not null default clock_timestamp()
);
alter table private.expense_receipts enable row level security;
revoke all on private.expense_receipts from public,anon,authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('expense-receipts','expense-receipts',false,10485760,array['image/jpeg','image/png']);
create function private.expense_receipt_access(p_path text,p_write boolean) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare receipt private.expense_receipts%rowtype;
begin
 if auth.uid() is null or not private.account_access_allowed() then return false;end if;
 select * into receipt from private.expense_receipts where object_path=p_path;
 if not found or not exists(select 1 from public.company_members where company_id=receipt.company_id and user_id=auth.uid()) then return false;end if;
 if p_write then return receipt.created_by=auth.uid() and not receipt.attached;end if;
 if receipt.created_by=auth.uid() then return true;end if;
 return receipt.attached and exists(select 1 from private.expense_claims where id=receipt.claim_id and company_id=receipt.company_id)
  and coalesce((private.expense_review_access(receipt.company_id)->>'can_review')::boolean,false);
end $$;
create function public.expense_receipt_access(p_path text,p_write boolean) returns boolean
language sql stable security invoker set search_path='' as $$select private.expense_receipt_access(p_path,p_write)$$;
revoke all on function private.expense_receipt_access(text,boolean),public.expense_receipt_access(text,boolean) from public;
grant execute on function private.expense_receipt_access(text,boolean),public.expense_receipt_access(text,boolean) to anon,authenticated;
create policy expense_receipt_insert on storage.objects for insert to authenticated
 with check(bucket_id='expense-receipts' and public.expense_receipt_access(name,true));
create policy expense_receipt_select on storage.objects for select to authenticated
 using(bucket_id='expense-receipts' and public.expense_receipt_access(name,false));
-- Existing bucket policies keep their meaning; generic permissive policies
-- cannot accidentally expose or overwrite this new private receipt bucket.
create policy expense_receipt_select_boundary on storage.objects as restrictive for select to public
 using(bucket_id<>'expense-receipts' or public.expense_receipt_access(name,false));
create policy expense_receipt_insert_boundary on storage.objects as restrictive for insert to public
 with check(bucket_id<>'expense-receipts' or public.expense_receipt_access(name,true));
create policy expense_receipt_update_boundary on storage.objects as restrictive for update to public
 using(bucket_id<>'expense-receipts') with check(bucket_id<>'expense-receipts');
create policy expense_receipt_delete_boundary on storage.objects as restrictive for delete to public
 using(bucket_id<>'expense-receipts');
create function private.expense_prepare_receipt(p_claim uuid,p_company uuid,p_worker uuid,p_sha256 text,p_size integer,p_mime text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare old private.expense_receipts%rowtype; object_path text;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501';end if;
 perform 1 from public.companies where id=p_company for key share;
 if not exists(select 1 from public.company_members where company_id=p_company and user_id=auth.uid()) or
  not exists(select 1 from public.workers where id=p_worker and company_id=p_company and user_id=auth.uid() and status='active') then
  raise exception 'own active worker required' using errcode='42501';end if;
 if p_claim is null or p_sha256 is null or p_sha256 !~ '^[a-f0-9]{64}$' or p_size is null or p_size not between 1 and 10485760
  or p_mime is null or p_mime not in ('image/jpeg','image/png') then raise exception 'invalid receipt' using errcode='22023';end if;
 if not exists(select 1 from private.expense_receipts where claim_id=p_claim)
  and exists(select 1 from private.expense_claims where id=p_claim) then
  raise exception '既存申請へ領収書を追加できません。新しい申請で登録してください。' using errcode='22023';end if;
 object_path:=p_company::text||'/'||auth.uid()::text||'/'||p_claim::text||case when p_mime='image/png' then '.png' else '.jpg' end;
 insert into private.expense_receipts(claim_id,company_id,applicant_id,created_by,object_path,sha256,size_bytes,mime_type)
 values(p_claim,p_company,p_worker,auth.uid(),object_path,p_sha256,p_size,p_mime) on conflict(claim_id) do nothing;
 select * into old from private.expense_receipts where claim_id=p_claim for update;
 if (old.company_id,old.applicant_id,old.created_by,old.sha256,old.size_bytes,old.mime_type)
  is distinct from (p_company,p_worker,auth.uid(),p_sha256,p_size,p_mime) then
  raise exception 'fixed receipt differs' using errcode='23505';end if;
 return jsonb_build_object('claim_id',p_claim,'object_path',old.object_path,'attached',old.attached,
  'uploaded',exists(select 1 from storage.objects where bucket_id='expense-receipts' and name=old.object_path
   and (metadata->>'size')::bigint=old.size_bytes and metadata->>'mimetype'=old.mime_type));
end $$;
create function public.expense_prepare_receipt(p_claim uuid,p_company uuid,p_worker uuid,p_sha256 text,p_size integer,p_mime text)
returns jsonb language sql security invoker set search_path='' as $$select private.expense_prepare_receipt(p_claim,p_company,p_worker,p_sha256,p_size,p_mime)$$;
create function private.expense_personal_submit_with_receipt(p_id uuid,p_company uuid,p_worker uuid,p_date date,p_description text,p_amount integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare receipt private.expense_receipts%rowtype; result jsonb;
begin
 if auth.uid() is null or not private.account_access_allowed() then raise exception 'account unavailable' using errcode='42501';end if;
 select * into receipt from private.expense_receipts where claim_id=p_id and company_id=p_company
  and applicant_id=p_worker and created_by=auth.uid() for update;
 if not found or not exists(select 1 from storage.objects where bucket_id='expense-receipts' and name=receipt.object_path
   and (metadata->>'size')::bigint=receipt.size_bytes and metadata->>'mimetype'=receipt.mime_type) then
  raise exception '領収書の保存を確認できません。同じ申請を再確認してください。' using errcode='22023';end if;
 result:=private.expense_personal_submit(p_id,p_company,p_worker,p_date,p_description,p_amount);
 update private.expense_receipts set attached=true where claim_id=p_id;
 return result||jsonb_build_object('receipt_object_path',receipt.object_path);
end $$;
create function public.expense_personal_submit_with_receipt(p_id uuid,p_company uuid,p_worker uuid,p_date date,p_description text,p_amount integer)
returns jsonb language sql security invoker set search_path='' as $$select private.expense_personal_submit_with_receipt(p_id,p_company,p_worker,p_date,p_description,p_amount)$$;
create function private.expense_personal_exact_with_receipt(p_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 result:=private.expense_personal_exact(p_id);
 if result is null then return null;end if;
 return result||jsonb_build_object('receipt_object_path',(select object_path from private.expense_receipts where claim_id=p_id and attached));
end $$;
create function public.expense_personal_exact_with_receipt(p_id uuid) returns jsonb
language sql security invoker set search_path='' as $$select private.expense_personal_exact_with_receipt(p_id)$$;
create function private.expense_personal_receipt_history(p_company uuid,p_worker uuid,p_month date) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 result:=private.expense_personal_settlement_history(p_company,p_worker,p_month);
 return (select coalesce(jsonb_agg(x.claim||jsonb_build_object('receipt_object_path',r.object_path) order by x.ordinality),'[]')
  from jsonb_array_elements(result) with ordinality x(claim,ordinality)
  left join private.expense_receipts r on r.claim_id=(x.claim->>'id')::uuid and r.attached);
end $$;
create function public.expense_personal_receipt_history(p_company uuid,p_worker uuid,p_month date) returns jsonb
language sql security invoker set search_path='' as $$select private.expense_personal_receipt_history(p_company,p_worker,p_month)$$;
revoke all on function private.expense_prepare_receipt(uuid,uuid,uuid,text,integer,text),public.expense_prepare_receipt(uuid,uuid,uuid,text,integer,text),
 private.expense_personal_submit_with_receipt(uuid,uuid,uuid,date,text,integer),public.expense_personal_submit_with_receipt(uuid,uuid,uuid,date,text,integer),
 private.expense_personal_exact_with_receipt(uuid),public.expense_personal_exact_with_receipt(uuid),
 private.expense_personal_receipt_history(uuid,uuid,date),public.expense_personal_receipt_history(uuid,uuid,date) from public,anon;
grant execute on function private.expense_prepare_receipt(uuid,uuid,uuid,text,integer,text),public.expense_prepare_receipt(uuid,uuid,uuid,text,integer,text),
 private.expense_personal_submit_with_receipt(uuid,uuid,uuid,date,text,integer),public.expense_personal_submit_with_receipt(uuid,uuid,uuid,date,text,integer),
 private.expense_personal_exact_with_receipt(uuid),public.expense_personal_exact_with_receipt(uuid),
 private.expense_personal_receipt_history(uuid,uuid,date),public.expense_personal_receipt_history(uuid,uuid,date) to authenticated;
create or replace function private.expense_review_flow_workspace(p_company uuid,p_month date) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; claims jsonb;
begin
 result:=private.expense_settlement_workspace(p_company,p_month);
 select coalesce(jsonb_agg(x.claim||jsonb_build_object('receipt_object_path',photo.object_path)||coalesce((select jsonb_build_object(
  'reviewed_at',r.result->'reviewed_at','reviewed_by',r.actor_id,'reviewed_by_name',r.result->'reviewed_by_name','review_memo',r.result->'review_memo')
  from private.expense_review_confirmations r where r.claim_id=(x.claim->>'id')::uuid and r.company_id=p_company
   and (r.result->>'revision')::integer=(x.claim->>'revision')::integer
  order by r.created_at desc,r.command_id desc limit 1),'{}'::jsonb) order by x.ordinality),'[]') into claims
 from jsonb_array_elements(result->'claims') with ordinality x(claim,ordinality)
 left join private.expense_receipts photo on photo.claim_id=(x.claim->>'id')::uuid and photo.attached;
 return result||jsonb_build_object('review_flow_enabled',true,'receipt_attachments_enabled',true,'claims',claims);
end $$;
