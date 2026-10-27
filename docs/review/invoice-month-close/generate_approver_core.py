#!/usr/bin/env python3
"""Derive a review-only approver calculator from the pinned preview candidate.

No database access. Exact anchors make upstream drift fail closed. This does not
modify the correction preview, and grants no direct access to the derived core.
"""
import hashlib
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text()
output = pathlib.Path(sys.argv[2])

def one(text, old, new):
    if text.count(old) != 1:
        raise ValueError('preview source anchor changed')
    return text.replace(old, new, 1)

start = source.index('create function invoice_correction_preview_private.preview(')
end = source.index('revoke all on function invoice_correction_preview_private.preview(uuid)', start)
preview = source[start:end]
preview = one(preview, 'invoice_correction_preview_private.preview(p_invoice_id uuid)', 'invoice_month_close_candidate.preview_for_approver(p_invoice_id uuid)')
preview = one(preview, " or not coalesce(existing.invoice_seal_frozen,false)", '')
preview = one(preview, " or exists(select 1 from public.invoice_approvals a where a.invoice_id=existing.id and a.status='approved')", '')
prior = "if not exists(select 1 from public.company_members m where m.company_id=cid and m.user_id=auth.uid() and m.role::text in ('owner','admin','manager')) or private.has_company_feature(cid,'can_manage_invoices') is not true then raise exception 'invoice_revision_not_allowed';end if;"
allowed = "if not exists(select 1 from public.company_members m join public.invoice_approvals a on a.company_id=m.company_id and a.approver_user_id=m.user_id where m.company_id=cid and m.user_id=auth.uid() and a.invoice_id=p_invoice_id and a.status in ('pending','approved')) then raise exception 'invoice_revision_not_allowed';end if;"
preview = one(preview, prior, allowed)

start = source.index('create function invoice_correction_preview_private.revalidate_for_commit(')
end = source.index('revoke all on function invoice_correction_preview_private.revalidate_for_commit(', start)
gate = source[start:end]
gate = one(gate, 'invoice_correction_preview_private.revalidate_for_commit(p_invoice_id uuid,p_source text,p_original text)', 'invoice_month_close_candidate.revalidate_for_approver(p_invoice_id uuid,p_source text,p_original text)')
prior = "if cid is null or not exists(select 1 from public.company_members m where m.company_id=cid and m.user_id=auth.uid() and m.role::text in ('owner','admin','manager')) or private.has_company_feature(cid,'can_manage_invoices') is not true then raise exception 'invoice_revision_not_allowed';end if;"
allowed = "if cid is null or not exists(select 1 from public.company_members m join public.invoice_approvals a on a.company_id=m.company_id and a.approver_user_id=m.user_id where m.company_id=cid and m.user_id=auth.uid() and a.invoice_id=p_invoice_id and a.status in ('pending','approved')) then raise exception 'invoice_revision_not_allowed';end if;"
gate = one(gate, prior, allowed)
start = gate.index(' select m.role::text into member_role')
end = gate.index(' select encode(sha256(', start)
gate = gate[:start] + """ perform 1 from public.company_members m where m.company_id=cid and m.user_id=auth.uid() for share;
 if not found then raise exception 'invoice_revision_not_allowed';end if;
 perform 1 from public.invoice_approvals a where a.invoice_id=p_invoice_id and a.company_id=cid and a.approver_user_id=auth.uid() and a.status in ('pending','approved') for share;
 if not found then raise exception 'invoice_revision_not_allowed';end if;
""" + gate[end:]

def body_hash(definition, dollar):
    return hashlib.md5(definition.split('as '+dollar, 1)[1].rsplit(dollar+';', 1)[0].encode(), usedforsecurity=False).hexdigest()

preview_md5 = body_hash(preview, '$body$')
gate_md5 = body_hash(gate, '$gate$')
catalog = f"""
create function invoice_month_close_candidate.approver_core_intact() returns boolean
language sql volatile security definer set search_path='' as $$
 select exists(select 1 from pg_proc p where p.oid=to_regprocedure('invoice_month_close_candidate.preview_for_approver(uuid)') and md5(p.prosrc)='{preview_md5}')
 and exists(select 1 from pg_proc p where p.oid=to_regprocedure('invoice_month_close_candidate.revalidate_for_approver(uuid,text,text)') and md5(p.prosrc)='{gate_md5}')
$$;
revoke all on function invoice_month_close_candidate.preview_for_approver(uuid), invoice_month_close_candidate.revalidate_for_approver(uuid,text,text), invoice_month_close_candidate.approver_core_intact() from public,anon,authenticated,service_role;
"""
output.write_text('-- Generated review-only candidate; never run in production.\n'+preview+gate+catalog)
