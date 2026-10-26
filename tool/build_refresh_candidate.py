"""Generate review-only source edits from captured real functions, fail closed on drift."""
from pathlib import Path
import hashlib
import re
root=Path(__file__).resolve().parents[1]
def replace_once(text,old,new):
    assert text.count(old)==1,repr(old[:100])
    return text.replace(old,new,1)
def read(name):
    return (root/'supabase/tests/fixtures/trade_document_adjustments_20261026'/name).read_text()
invoice=read('private.refresh_automatic_invoice.sql')
certificate=read('private.refresh_automatic_payment_certificate.sql')
rows=read('private.certificate_calculation_rows.sql')
expected=[('private.refresh_automatic_invoice(uuid,uuid,date)',invoice,'9173c4e7237b764ecb4c1e79bad85005'),
 ('private.refresh_automatic_payment_certificate(uuid,uuid,date)',certificate,'5828ec68ad83ace5f0c0fc8f21851cf8'),
 ('private.certificate_calculation_rows(uuid,uuid,date,date)',rows,'5b245861b26afe2ffb581be84f8dfa4c')]
for signature,source,digest in expected:
    body=re.search(r'AS \$function\$([\s\S]*?)\$function\$',source).group(1)
    assert hashlib.md5(body.encode()).hexdigest()==digest,signature
invoice=replace_once(invoice,'declare\n','declare\n  named_items jsonb; named_item jsonb; named_final numeric:=0;\n')
invoice=replace_once(invoice,"  if found and (existing.status<>'draft' or existing.finalized_at is not null) then", "  if found and (existing.status<>'draft' or existing.finalized_at is not null or existing.approval_finalized_at is not null or coalesce(existing.invoice_seal_frozen,false) or exists(select 1 from public.invoice_approvals ia where ia.invoice_id=existing.id and ia.status='approved')) then")
invoice=replace_once(invoice,"  select name into customer_name", """  if existing.snapshot?'document_adjustments_v1' and not exists(
    select 1 from document_adjustment_private.rollout r where r.company_id=cid and r.enabled
  ) then return;end if;
  perform document_adjustment_private.ensure_occurrences(cid,'invoice',customer,first_day);
  named_items:=document_adjustment_private.active_items(cid,'invoice',customer,first_day);
  select name into customer_name""")
invoice=replace_once(invoice,'      and exists(\n        select 1\n        from public.attendance_entries e','      and (exists(\n        select 1\n        from public.attendance_entries e')
invoice=replace_once(invoice,'      )\n    order by st.created_at, st.id',"      ) or exists(select 1 from jsonb_array_elements(named_items) x where x->>'calculation_mode'='before_charges' and x->>'site_id'=st.id::text))\n    order by st.created_at, st.id")
invoice=invoice.replace('if n=0 and expense_amount=0','if n=0 and expense_amount=0 and jsonb_array_length(named_items)=0 and not coalesce(existing.snapshot?\'document_adjustments_v1\',false)')
invoice=replace_once(invoice,'  route_parts:=', '  route_parts:=') if False else invoice
# Insert pre-charge lines into the same site and before its existing welfare/tax.
invoice=replace_once(invoice,'    d:=round(site_pre_tax*s.welfare_rate/100);',"""    for named_item in select value from jsonb_array_elements(
      document_adjustment_private.active_items(cid,'invoice',customer,first_day))
      where value->>'calculation_mode'='before_charges' and value->>'site_id'=s.id::text
    loop
      a:=(named_item->>'amount_yen')::numeric * case when named_item->>'sign'='minus' then -1 else 1 end;
      site_pre_tax:=site_pre_tax+a;
      lines:=lines||jsonb_build_array(jsonb_build_object('site_label','〃',
        'work_content',named_item->>'title','quantity',1,'unit_price',a,
        'unit_price_text',a::text,'amount',a,'document_adjustment',named_item));
    end loop;
    d:=round(site_pre_tax*s.welfare_rate/100);""")
# The saved grand total receives only final-amount entries; pre-charge entries
# already passed through the exact source's per-site rounding above.
invoice=replace_once(invoice,"  snapshot_value :=", "  snapshot_value :=") if False else invoice
anchor="  snapshot_value:=jsonb_build_object("
if anchor not in invoice: anchor="  snapshot_value := jsonb_build_object("
invoice=replace_once(invoice,anchor,"""  named_items:=document_adjustment_private.active_items(cid,'invoice',customer,first_day);
  select coalesce(sum((x->>'amount_yen')::numeric * case when x->>'sign'='minus' then -1 else 1 end),0)
  into named_final from jsonb_array_elements(named_items) x where x->>'calculation_mode'='settlement_yen';
"""+anchor)
# Add the final delta wherever the source writes its computed grand total.
invoice=invoice.replace('total_pre_tax+total_tax+expense_amount','total_pre_tax+total_tax+expense_amount+named_final')
invoice=replace_once(invoice,"  if existing.id is null then", "  if existing.id is null then") if False else invoice
marker="  -- Company seal"
# Snapshot construction ends before company-seal augmentation; locate the
# insertion using the exact saved-source seal call rather than broad rewrites.
seal="  snapshot_value:=snapshot_value||"
if seal in invoice:
    # Source may have multiple snapshot augmentations. Only first is sufficient.
    pos=invoice.index(seal)
else:
    pos=invoice.index('  if existing.id is null then',invoice.index(anchor))
invoice=invoice[:pos]+"  if jsonb_array_length(named_items)>0 or coalesce(existing.snapshot?'document_adjustments_v1',false) then\n  snapshot_value:=snapshot_value||jsonb_build_object('document_adjustments_v1',named_items,'document_final_adjustment_yen',named_final);\n  end if;\n"+invoice[pos:]
# Certificate before-charge lines enter the existing pre_totals CTE, so partner
# welfare and tax retain their exact original aggregate rounding contract.
rows=replace_once(rows,'  pre_totals as (',"""  named_lines as (
    select '〃'::text as site_name,x->>'title' as work_content,'1'::text as quantity_label,
      ((x->>'amount_yen')::bigint * case when x->>'sign'='minus' then -1 else 1 end)::integer as unit_price_yen,
      ((x->>'amount_yen')::bigint * case when x->>'sign'='minus' then -1 else 1 end)::integer as amount_yen,
      5 as sort_order
    from jsonb_array_elements(document_adjustment_private.active_items(
      v_company_id,'payment_certificate',v_partner_id,v_start)) x
    where x->>'calculation_mode'='before_charges'
  ),
  pre_totals as (""")
rows=replace_once(rows,'      select al.amount_yen from allowance_lines al','      select al.amount_yen from allowance_lines al\n      union all select nl.amount_yen from named_lines nl')
rows=replace_once(rows,'    union all select * from summary_lines','    union all select * from named_lines\n    union all select * from summary_lines')
certificate=replace_once(certificate,'declare\n','declare\n named_items jsonb;named_plus numeric:=0;named_minus numeric:=0;\n')
certificate=replace_once(certificate," if found and (existing.status<>'draft' or not existing.automatic_calculation) then return; end if;", " if found and (existing.status<>'draft' or existing.finalized_at is not null or not existing.automatic_calculation) then return; end if;\n if existing.snapshot?'document_adjustments_v1' and not exists(select 1 from document_adjustment_private.rollout r where r.company_id=cid and r.enabled) then return;end if;\n perform document_adjustment_private.ensure_occurrences(cid,'payment_certificate',partner,first_day);\n named_items:=document_adjustment_private.active_items(cid,'payment_certificate',partner,first_day);")
certificate=certificate.replace('if attendance_count=0 and not (expense_component',"if attendance_count=0 and jsonb_array_length(named_items)=0 and not coalesce(existing.snapshot?'document_adjustments_v1',false) and not (expense_component")
certificate=replace_once(certificate,' expense_net:=gross-expense_deductions;',""" named_items:=document_adjustment_private.active_items(cid,'payment_certificate',partner,first_day);
 select coalesce(sum((x->>'amount_yen')::numeric) filter(where x->>'sign'='plus'),0),
        coalesce(sum((x->>'amount_yen')::numeric) filter(where x->>'sign'='minus'),0)
 into named_plus,named_minus from jsonb_array_elements(named_items) x
 where x->>'calculation_mode'='settlement_yen';
 gross:=gross+named_plus;expense_deductions:=expense_deductions+named_minus;
 expense_net:=gross-expense_deductions;""")
certificate=certificate.replace("'other_deductions_yen',0","'other_deductions_yen',named_minus")
certificate=replace_once(certificate," if use_v2 then\n snapshot_value:=", " if jsonb_array_length(named_items)>0 or coalesce(existing.snapshot?'document_adjustments_v1',false) then\n snapshot_value:=snapshot_value||jsonb_build_object('document_adjustments_v1',named_items,'document_final_plus_yen',named_plus,'document_final_minus_yen',named_minus);\n end if;\n if use_v2 then\n snapshot_value:=")
invoice=replace_once(invoice,'end;\n$function$',"  if jsonb_array_length(named_items)>0 then\n  perform document_adjustment_private.bind_occurrences(cid,'invoice',customer,first_day,\n    (select id from public.invoices where company_id=cid and customer_id=customer and billing_period_start=first_day and automatic_calculation));\n  end if;\nend;\n$function$")
certificate=replace_once(certificate,'end\n$function$'," if jsonb_array_length(named_items)>0 then\n perform document_adjustment_private.bind_occurrences(cid,'payment_certificate',partner,first_day,\n   (select id from public.payment_certificates where company_id=cid and partner_company_id=partner and period_start=first_day));\n end if;\nend\n$function$")
# These generated functions still need zero-source protections, frozen-document
# protections and snapshot/display integration. Do not apply this file alone.
out=root/'supabase/review/refresh_functions.incomplete.sql'
out.write_text('-- INCOMPLETE REVIEW ONLY. NOT DEPLOYABLE.\n'+invoice+'\n'+rows+'\n'+certificate)
preflight='do $check$ begin\n'
for signature,source,digest in expected:
    preflight+=f"if (select md5(prosrc) from pg_proc where oid=to_regprocedure('{signature}')) is distinct from '{digest}' then raise exception 'Source drift: {signature}';end if;\n"
preflight+="if to_regclass('document_adjustment_private.rollout') is not null then raise exception 'Inspect existing installation; do not apply twice';end if;\nend $check$;\n"
parts=[]
for name in ['document_adjustments.sql','refresh_functions.incomplete.sql','document_adjustment_api.incomplete.sql']:
    text=(root/'supabase/review'/name).read_text()
    text=re.sub(r'^begin;\s*$','',text,flags=re.M)
    text=re.sub(r'^commit;\s*$','',text,flags=re.M)
    parts.append(text)
(root/'supabase/review/document_adjustment_install.incomplete.sql').write_text(
 '-- REVIEW CANDIDATE. CI, security/parallel and rendered PDF proof pending. NOT APPROVED FOR PRODUCTION.\n'
 +'begin;\n'+preflight+'\n'.join(parts)+'\ncommit;\n')
print(out)
