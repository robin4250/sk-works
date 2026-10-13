-- Invoice-only lifecycle; no snapshot backfill or payroll/payment trigger changes.
begin;
do $$ begin
 if (select tgfoid from pg_trigger where tgrelid='public.invoices'::regclass and tgname='zz_company_seal_snapshot')
   is distinct from 'private.preserve_document_company_seal_snapshot()'::regprocedure::oid then
  raise exception 'Unexpected invoice seal trigger; inspect before applying';
 end if;
 if (select tgfoid from pg_trigger where tgrelid='public.invoices'::regclass and tgname='invoice_material_change_after_update')
   is distinct from 'private.invoice_material_change_trigger()'::regprocedure::oid then
  raise exception 'Unexpected invoice material-change trigger; inspect before applying';
 end if;
end $$;
alter table public.invoices add column invoice_seal_frozen boolean not null default false;

create function private.invoice_seal_first_freeze(p_old public.invoices,p_new public.invoices)
returns boolean language sql immutable set search_path='' as $$
 select p_old.status='draft' and p_old.finalized_at is null
 and p_old.approval_finalized_at is null and not p_old.invoice_seal_frozen
 and p_new.status in ('draft','finalized')
 and p_old.company_id is not distinct from p_new.company_id
 and (p_new.finalized_at is not null or p_new.approval_finalized_at is not null or p_new.status='finalized')
 and (to_jsonb(p_old)-array['updated_at','approval_finalized_at','status','finalized_at','invoice_seal_frozen','snapshot'])
  is not distinct from (to_jsonb(p_new)-array['updated_at','approval_finalized_at','status','finalized_at','invoice_seal_frozen','snapshot'])
 and (coalesce(p_old.snapshot,'{}'::jsonb)-'company_seal_snapshot')
  is not distinct from (coalesce(p_new.snapshot,'{}'::jsonb)-'company_seal_snapshot')
$$;
revoke all on function private.invoice_seal_first_freeze(public.invoices,public.invoices) from public,anon,authenticated;

create function private.preserve_invoice_company_seal_snapshot() returns trigger
language plpgsql security definer set search_path='' as $$
declare preserved jsonb;
begin
 if tg_op='INSERT' then
  preserved:=private.document_company_seal_snapshot(null,new.company_id,true);
  new.invoice_seal_frozen:=new.status is distinct from 'draft' or new.finalized_at is not null or new.approval_finalized_at is not null;
 elsif private.invoice_seal_first_freeze(old,new) then
  preserved:=private.document_company_seal_snapshot(null,new.company_id,true);
  new.invoice_seal_frozen:=true;
 else
  preserved:=private.document_company_seal_snapshot(old.snapshot,old.company_id,false);
  -- Cancellation/reopening cannot reset the fact that a document was frozen.
  new.invoice_seal_frozen:=new.invoice_seal_frozen or old.invoice_seal_frozen or old.status is distinct from 'draft'
   or old.finalized_at is not null or old.approval_finalized_at is not null
   or new.status is distinct from 'draft' or new.finalized_at is not null or new.approval_finalized_at is not null;
 end if;
 if tg_op='UPDATE' and new.snapshot is not distinct from old.snapshot
  and not private.invoice_seal_first_freeze(old,new) then
  new.snapshot:=old.snapshot;
 else
  new.snapshot:=(coalesce(new.snapshot,'{}'::jsonb)-'company_seal_snapshot')||preserved;
 end if;
 return new;
end $$;
revoke all on function private.preserve_invoice_company_seal_snapshot() from public,anon,authenticated;

-- Only this invoice trigger is replaced. Generic financial functions stay intact.
drop trigger zz_company_seal_snapshot on public.invoices;
create trigger zz_company_seal_snapshot before insert or update on public.invoices
for each row execute function private.preserve_invoice_company_seal_snapshot();

create function private.invoice_seal_material_change_trigger() returns trigger
language plpgsql security definer set search_path='' as $$
declare previous jsonb; incoming jsonb;
begin
 previous:=to_jsonb(old)-array['updated_at','approval_finalized_at','status','finalized_at','invoice_seal_frozen'];
 incoming:=to_jsonb(new)-array['updated_at','approval_finalized_at','status','finalized_at','invoice_seal_frozen'];
 if private.invoice_seal_first_freeze(old,new) and new.invoice_seal_frozen then
  previous:=jsonb_set(previous,'{snapshot}',coalesce(old.snapshot,'{}'::jsonb)-'company_seal_snapshot');
  incoming:=jsonb_set(incoming,'{snapshot}',coalesce(new.snapshot,'{}'::jsonb)-'company_seal_snapshot');
 end if;
 if incoming is distinct from previous then perform private.invalidate_invoice_approval(new.id);end if;
 return null;
end $$;
revoke all on function private.invoice_seal_material_change_trigger() from public,anon,authenticated;
drop trigger invoice_material_change_after_update on public.invoices;
create trigger invoice_material_change_after_update after update on public.invoices
for each row execute function private.invoice_seal_material_change_trigger();

-- Seed only lifecycle metadata, never seal JSON or approval history.
-- Any historical approval audit is conservatively treated as already frozen.
update public.invoices i set invoice_seal_frozen=true
where not i.invoice_seal_frozen and (i.status is distinct from 'draft'
 or i.finalized_at is not null or i.approval_finalized_at is not null
 or exists(select 1 from public.invoice_approval_audit a where a.invoice_id=i.id));

commit;
