// Verbatim named-adjustment readers over isolated synthetic rows. No deployment.
// Route/expense/Auth and adjustment mutation APIs remain separate boundaries.
import fs from 'node:fs/promises';
export async function installNoticeAdjustmentProvider(db,c){
 const {A,B,id,q,check,pending}=c;
 const columns={
  'document_adjustment_private.templates':['kind text','party_id uuid','recurrence text','created_at timestamptz default now()'],
  'document_adjustment_private.template_versions':['version bigint','effective_month date','title text','sign text','amount_yen bigint','calculation_mode text','site_id uuid','stopped boolean default false'],
  'document_adjustment_private.occurrences':['id uuid','month date','override jsonb','canceled boolean default false'],
 };
 for(const [table,fields]of Object.entries(columns))for(const field of fields)await db.exec(`alter table ${table} add column if not exists ${field}`);
 const source=await fs.readFile('supabase/review/document_adjustment_install.incomplete.sql','utf8');
 for(const name of ['ledger_items','active_items']){
  const marker='create function document_adjustment_private.'+name+'(';
  const start=source.indexOf(marker),end=source.indexOf('revoke all on function document_adjustment_private.'+name+'(',start);
  if(start<0||end<start||source.indexOf(marker,start+1)!==-1)throw Error('adjustment reader source anchor changed');
  // active_items replaces only the explicitly empty disposable fixture stub.
  await db.exec(source.slice(start,source.indexOf(';',end)+1).replace('create function','create or replace function'));
  check(await q("select has_function_privilege('authenticated',$1,'EXECUTE') v",['document_adjustment_private.'+name+'(uuid,text,uuid,date)']),false);
  check(await q("select has_function_privilege('anon',$1,'EXECUTE') v",['document_adjustment_private.'+name+'(uuid,text,uuid,date)']),false);
 }
 const customer=await q('select customer_id v from public.invoices where id=$1',[pending.parent]);
 const active=()=>q("select document_adjustment_private.active_items($1,'invoice',$2,'2020-10-01') v",[A,customer]);
 const insertRows=async()=>{
  await db.query('insert into document_adjustment_private.rollout(company_id,enabled) values($1,true)',[A]);
  for(const [n,company,party,recurrence,month,sign,amount]of [
   [51001,A,customer,'monthly','2020-10-01','plus',1000],
   [51002,A,customer,'once','2020-10-01','minus',250],
   [51003,A,customer,'once','2020-09-01','plus',90000],
   [51004,B,customer,'monthly','2020-10-01','plus',80000],
   [51005,A,id(51999),'monthly','2020-10-01','plus',70000],
  ]){
   await db.query('insert into document_adjustment_private.templates(id,company_id,kind,party_id,recurrence) values($1,$2,\'invoice\',$3,$4)',[id(n),company,party,recurrence]);
   await db.query('insert into document_adjustment_private.template_versions(template_id,version,effective_month,title,sign,amount_yen,calculation_mode) values($1,1,$2,\'合成調整\',$3,$4,\'settlement_yen\')',[id(n),month,sign,amount]);
  }
 };
 await db.exec('begin');
 try{
  await insertRows();
  check((await active()).length,2);
  check((await q("select document_adjustment_private.active_items($1,'invoice',$2,'2020-11-01') v",[A,customer])).length,1);
  await db.query("insert into document_adjustment_private.template_versions(template_id,version,effective_month,title,sign,amount_yen,calculation_mode,stopped) values($1,2,'2020-11-01','合成停止','plus',1000,'settlement_yen',true)",[id(51001)]);
  check((await q("select document_adjustment_private.active_items($1,'invoice',$2,'2020-11-01') v",[A,customer])),[]);
  check((await active()).length,2);
  const proposal=await q('select invoice_month_close_candidate.preview_for_approver($1) v',[pending.parent]);
  check(proposal.grand_total,110750);check(proposal.proposed_snapshot.document_final_adjustment_yen,750);
  check(await q('select invoice_month_close_candidate.guarded($1) v',[pending.parent]),'data_changed');
  await db.query('insert into document_adjustment_private.occurrences(id,template_id,month,override) values($1,$2,\'2020-10-01\',$3::jsonb)',[id(51010),id(51001),JSON.stringify({amount_yen:1200})]);
  check((await q('select invoice_month_close_candidate.preview_for_approver($1) v',[pending.parent])).grand_total,110950);
  await db.query('update document_adjustment_private.occurrences set canceled=true where id=$1',[id(51010)]);
  check((await q('select invoice_month_close_candidate.preview_for_approver($1) v',[pending.parent])).grand_total,109750);
  await db.query('update document_adjustment_private.rollout set enabled=false where company_id=$1',[A]);
  check(await active(),[]);
  check(await q('select invoice_month_close_candidate.guarded($1) v',[pending.parent]),'ready');
 }finally{await db.exec('rollback');}
 check(await active(),[]);
 // Run again within the financial confirmation fixture's own transaction so
 // nonempty real adjustment output is committed by that writer and then the
 // entire synthetic scenario is rolled back by the outer fixture.
 return async()=>{
  await insertRows();
  const proposal=await q('select invoice_month_close_candidate.preview_for_approver($1) v',[pending.parent]);
  check(proposal.grand_total,110750);
  await db.query('update public.invoices set snapshot=$1::jsonb,subtotal=$2,tax=$3,welfare_amount=$4,grand_total=$5,updated_at=clock_timestamp() where id=$6',[JSON.stringify(proposal.proposed_snapshot),proposal.subtotal,proposal.tax,proposal.welfare,proposal.grand_total,pending.parent]);
  check(await q('select invoice_month_close_candidate.guarded($1) v',[pending.parent]),'ready');
 };
}
