#!/usr/bin/env python3
"""Offline exact-source producer for the review-only paid-hours connection."""
import argparse,hashlib,json,pathlib,re
ROOT=pathlib.Path(__file__).resolve().parents[1]

def body(s):
    m=re.search(r'\bAS\s+(\$[A-Za-z_0-9]*\$)([\s\S]*)\1\s*;?\s*$',s,re.I)
    if not m:raise ValueError('source body unavailable')
    return m.group(2)

def once(s,a,b):
    if s.count(a)!=1:raise ValueError('nonunique exact source anchor: '+a[:80])
    return s.replace(a,b)

def produce():
    fixture=json.loads((ROOT/'tool/fixtures/checkout_paid_hours_actual_sources.json').read_text())
    sources={}
    for f in fixture['functions']:
        sig=f['signature'];sig=sig if '.' in sig.split('(')[0] else 'public.'+sig
        if hashlib.md5(body(f['definition']).encode()).hexdigest()!=f['source_md5']:raise ValueError('source hash mismatch')
        sources[sig]=f
    basis=sources['company_checkout_allowance_private.report_basis(uuid)']['definition']
    basis=once(basis,' from public.daily_reports r where r.id=rid'," || jsonb_build_object('paid_work_hours',checkout_paid_hours_candidate_private.draft_basis(rid))\n from public.daily_reports r where r.id=rid")
    sign=sources['public.sign_daily_report(uuid,text,jsonb)']['definition']
    sign=once(sign,'  checkout_receipts:=company_checkout_allowance_private.capture_report(p_report_id);',
                   '  checkout_receipts:=company_checkout_allowance_private.capture_report(p_report_id);\n  perform checkout_paid_hours_candidate_private.capture_report(p_report_id,p_signature_json);')
    aggregate=sources['company_checkout_allowance_private.aggregate(jsonb)']['definition']
    aggregate=once(aggregate,'company_checkout_allowance_private.aggregate(p_receipts jsonb)',
                        'checkout_paid_hours_candidate_private.aggregate_with_hours(p_receipts jsonb, p_hours jsonb)')
    aggregate=once(aggregate,"quantity:=null;\n    reasons:=reasons||jsonb_build_array(jsonb_build_object('code','actual_work_hours_unavailable','id',item->>'id','work_date',r->>'work_date'));", """quantity:=case when p_hours#>>array[r->>'work_date','available']='true'
      then (p_hours#>>array[r->>'work_date','hours'])::numeric else null end;
    if quantity is not null and (quantity<0 or quantity>24 or scale(quantity)>4 or quantity::text in('NaN','Infinity','-Infinity')) then
     raise exception 'invalid signed paid hours' using errcode='22023';end if;
    if quantity is null then
     reasons:=reasons||jsonb_build_array(jsonb_build_object('code','signed_paid_hours_unavailable','id',item->>'id','work_date',r->>'work_date'));
    end if;""")
    aggregate=once(aggregate,"   entry:=jsonb_set(entry,'{work_dates}',(entry->'work_dates')||jsonb_build_array(r->>'work_date'));", """   entry:=jsonb_set(entry,'{work_dates}',(entry->'work_dates')||jsonb_build_array(r->>'work_date'));
   if item->>'unit'='hour' then
    entry:=entry||jsonb_build_object('hours_evidence',coalesce(entry->'hours_evidence','[]')||jsonb_build_array(
     jsonb_build_object('work_date',r->>'work_date','evidence',p_hours->(r->>'work_date'))));
   end if;""")
    aggregate=once(aggregate,"'source','confirmed_checkout_receipt'));", "'source','confirmed_checkout_receipt')||case when item->>'unit'='hour' then jsonb_build_object('quantity_basis','dual_signed_closed_day_ledger','hours_evidence',entry->'hours_evidence') else '{}'::jsonb end);")
    resolve=sources['company_checkout_allowance_private.resolve(uuid,uuid,date,date)']['definition']
    resolve=once(resolve,' answer:=company_checkout_allowance_private.aggregate(receipts);',
      ' answer:=checkout_paid_hours_candidate_private.aggregate_with_hours(receipts,checkout_paid_hours_candidate_private.month_quantities(cid,wid,p_start,p_end));')
    pins='DO $pins$ BEGIN\n'
    for sig in ('company_checkout_allowance_private.report_basis(uuid)','public.sign_daily_report(uuid,text,jsonb)','company_checkout_allowance_private.resolve(uuid,uuid,date,date)'):
        f=sources[sig];pins+=f" IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('{sig}') AND md5(prosrc)='{f['source_md5']}') THEN RAISE EXCEPTION 'paid-hours source differs: {sig}'; END IF;\n"
    pins+='END $pins$;\n'
    definitions='\n'.join(source.rstrip().rstrip(';')+';' for source in (aggregate,basis,sign,resolve))
    sql=pins+'\n'+definitions+'''\nREVOKE ALL ON FUNCTION checkout_paid_hours_candidate_private.aggregate_with_hours(jsonb,jsonb) FROM public,anon,authenticated,service_role;\n'''
    return sql

def main():
    p=argparse.ArgumentParser();p.add_argument('--output',required=True);a=p.parse_args()
    pathlib.Path(a.output).write_text(produce())
if __name__=='__main__':main()
