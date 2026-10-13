-- Only detail pages. Never changes payable amounts or backfills old documents.
create table private.expense_document_snapshots (
 kind text not null, document_id uuid not null, revision integer not null,
 company_id uuid not null, subject_id uuid not null, month date not null,
 claims jsonb not null, captured_at timestamptz not null default clock_timestamp(),
 primary key(kind,document_id,revision)
);
alter table private.expense_document_snapshots enable row level security;
revoke all on private.expense_document_snapshots from public,anon,authenticated;
create function private.expense_document_claims(p_kind text,p_company uuid,p_subject uuid,p_month date) returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(e) order by e.incurred_on,e.submitted_at,e.id),'[]'::jsonb)
 from private.expense_claims e where e.company_id=p_company
 and e.incurred_on>=date_trunc('month',p_month)::date and e.incurred_on<(date_trunc('month',p_month)+interval '1 month')::date
 and case p_kind when 'payroll' then e.applicant_id=p_subject
 when 'invoice' then e.allocation='customer' and e.counterparty_id=p_subject
 when 'paymentCertificate' then e.allocation='subcontractor' and e.counterparty_id=p_subject else false end
$$;
revoke all on function private.expense_document_claims(text,uuid,uuid,date) from public,anon,authenticated;
create function private.capture_expense_document() returns trigger
language plpgsql security definer set search_path='' as $$
declare current_row jsonb:=to_jsonb(new); previous_row jsonb; kind text; subject uuid; expense_month date; done boolean; was_done boolean; version integer;
begin
 if tg_op='UPDATE' then previous_row:=to_jsonb(old); end if;
 if tg_table_name='payroll_statements' then
  kind:='payroll';subject:=(current_row->>'worker_id')::uuid;expense_month:=(current_row->>'period_end')::date;
  done:=current_row->>'workflow_state'='finalized';was_done:=previous_row->>'workflow_state'<>'draft';
 elsif tg_table_name='invoices' then
  kind:='invoice';subject:=(current_row->>'customer_id')::uuid;expense_month:=(current_row->>'billing_period_start')::date;
  done:=current_row->>'status'<>'draft' or current_row->>'finalized_at' is not null;
  was_done:=previous_row->>'status'<>'draft' or previous_row->>'finalized_at' is not null;
 elsif tg_table_name='payment_certificates' then
  kind:='paymentCertificate';subject:=(current_row->>'partner_company_id')::uuid;expense_month:=(current_row->>'period_start')::date;
  done:=current_row->>'status'='finalized';was_done:=previous_row->>'status'='finalized';
 else raise exception 'unknown expense document'; end if;
 -- Existing finalized/legacy documents are never augmented on unrelated updates.
 if not coalesce(done,false) or coalesce(was_done,false) then return new; end if;
 version:=coalesce((current_row->>'revision')::integer,1);
 insert into private.expense_document_snapshots(kind,document_id,revision,company_id,subject_id,month,claims)
 values(kind,new.id,version,new.company_id,subject,date_trunc('month',expense_month)::date,
 private.expense_document_claims(kind,new.company_id,subject,expense_month))
 on conflict do nothing;
 return new;
end $$;
revoke all on function private.capture_expense_document() from public,anon,authenticated;
create trigger zz_expense_document_snapshot after insert or update on public.payroll_statements for each row execute function private.capture_expense_document();
create trigger zz_expense_document_snapshot after insert or update on public.invoices for each row execute function private.capture_expense_document();
create trigger zz_expense_document_snapshot after insert or update on public.payment_certificates for each row execute function private.capture_expense_document();

create function private.read_expense_document(p_kind text,p_document uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare row_data jsonb; cid uuid; subject uuid; expense_month date; version integer; live boolean; allowed boolean:=false; claims jsonb;
begin
 if auth.uid() is null or not coalesce(private.account_access_allowed(),false) then raise exception 'account unavailable' using errcode='42501'; end if;
 if p_kind='payroll' then select to_jsonb(p) into row_data from public.payroll_statements p where id=p_document;
 elsif p_kind='invoice' then select to_jsonb(p) into row_data from public.invoices p where id=p_document;
 elsif p_kind='paymentCertificate' then select to_jsonb(p) into row_data from public.payment_certificates p where id=p_document;
 else raise exception 'invalid expense document kind' using errcode='22023'; end if;
 if row_data is null then raise exception 'document unavailable' using errcode='42501'; end if;
 cid:=(row_data->>'company_id')::uuid;version:=coalesce((row_data->>'revision')::integer,1);
 if p_kind='payroll' then
  subject:=(row_data->>'worker_id')::uuid;expense_month:=(row_data->>'period_end')::date;live:=row_data->>'workflow_state'='draft';
  allowed:=exists(select 1 from public.workers w where w.id=subject and w.company_id=cid and w.user_id=auth.uid()) or exists(
   select 1 from public.company_members m where m.company_id=cid and m.user_id=auth.uid() and
   (m.role::text in ('owner','admin','viewer') or (m.role::text='manager' and exists(select 1 from public.payroll_manager_worker_visibility v where v.company_id=cid and v.worker_id=subject and v.visible_to_manager)))
  );
 elsif p_kind='invoice' then
  subject:=(row_data->>'customer_id')::uuid;expense_month:=(row_data->>'billing_period_start')::date;live:=row_data->>'status'='draft' and row_data->>'finalized_at' is null;
  allowed:=private.has_company_feature(cid,'can_view_invoices');
 else
  subject:=(row_data->>'partner_company_id')::uuid;expense_month:=(row_data->>'period_start')::date;live:=row_data->>'status'='draft';
  allowed:=exists(select 1 from public.company_members m where m.company_id=cid and m.user_id=auth.uid() and m.role::text in ('owner','admin','manager'));
 end if;
 if not coalesce(allowed,false) or not exists(select 1 from public.companies where id=cid) then raise exception 'document access denied' using errcode='42501'; end if;
 if live then claims:=private.expense_document_claims(p_kind,cid,subject,expense_month);
 else
  select s.claims into claims from private.expense_document_snapshots s where s.kind=p_kind and s.document_id=p_document and s.revision=version and s.company_id=cid and s.subject_id=subject and s.month=date_trunc('month',expense_month)::date;
 end if;
 return jsonb_build_object('kind',p_kind,'document_id',p_document,'company_id',cid,'subject_id',subject,'month',date_trunc('month',expense_month)::date,'revision',version,'updated_at',row_data->'updated_at','frozen',not coalesce(live,false),'claims',coalesce(claims,'[]'::jsonb));
end $$;
create function public.read_expense_document(p_kind text,p_document uuid) returns jsonb language sql stable security invoker set search_path='' as $$select private.read_expense_document(p_kind,p_document)$$;
revoke all on function private.read_expense_document(text,uuid),public.read_expense_document(text,uuid) from public,anon;
grant execute on function private.read_expense_document(text,uuid),public.read_expense_document(text,uuid) to authenticated;
