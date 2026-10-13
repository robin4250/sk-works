-- Extend only newly created immutable snapshots. Existing saved documents are
-- returned unchanged; no backfill of current company settings into old records.
create or replace function private.saved_site_payment_document(p_proposal uuid,p_company uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare proposal private.site_payment_proposals; pair jsonb; result jsonb;
begin
 select * into proposal from private.site_payment_proposals where id=p_proposal;
 if proposal.id is null then raise exception '提案が見つかりません。'; end if;
 pair:=private.site_payment_pair(proposal.shared_item_id,p_company);
 perform 1 from private.site_payment_agreement_rollout r where r.company_id in
  ((pair->>'parent_company_id')::uuid,(pair->>'child_company_id')::uuid)
  order by r.company_id for share;
 perform 1 from private.company_connections c where c.parent_company_id=(pair->>'parent_company_id')::uuid
  and c.child_company_id=(pair->>'child_company_id')::uuid for share;
 perform 1 from private.site_share_inbox where data_item_id=proposal.shared_item_id for update;
 pair:=private.site_payment_pair(proposal.shared_item_id,p_company);
 if exists(select 1 from private.site_payment_proposals p where p.shared_item_id=proposal.shared_item_id
  and p.revision>proposal.revision) then raise exception '最新版を確認してください。' using errcode='40001'; end if;
 if not exists(select 1 from private.site_payment_confirmations c where c.proposal_id=p_proposal
  and c.company_id=(pair->>'parent_company_id')::uuid) or not exists(
  select 1 from private.site_payment_confirmations c where c.proposal_id=p_proposal
  and c.company_id=(pair->>'child_company_id')::uuid) then raise exception '双方の確認が必要です。'; end if;
 select snapshot into result from private.site_payment_document_snapshots where proposal_id=p_proposal;
 if result is null then
  select jsonb_build_object('proposal_id',proposal.id,'revision',proposal.revision,'terms',proposal.terms,
   'parent_company_name',parent.name,'subcontractor_company_name',child.name,'site_name',s.name,
   'parent_company_id',parent.id,'subcontractor_company_id',child.id,
   'snapshot_version',2,
   'parent_postal_code',coalesce(parent.postal_code,''),
   'parent_address',coalesce(parent.address,''),
   'parent_phone',coalesce(parent.phone,''),
   'parent_fax',coalesce(parent.fax,''),
   'parent_company_seal_enabled',parent.company_seal_enabled)
  into result from public.companies parent,public.companies child,public.sites s
  where parent.id=(pair->>'parent_company_id')::uuid and child.id=(pair->>'child_company_id')::uuid
  and s.id=(pair->>'source_site_id')::uuid;
  insert into private.site_payment_document_snapshots(proposal_id,snapshot,created_by)
  values(p_proposal,result,auth.uid());
 end if;
 return result;
end $$;
