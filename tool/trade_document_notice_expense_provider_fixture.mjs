// Verbatim approved cost-recovery reader over isolated rows. No deployment.
// Expense approval/allocation mutation APIs and real Auth remain separate gaps.
import fs from 'node:fs/promises';
export async function installNoticeExpenseProvider(db,c){
 const {A,B,UA,id,q,check,pending}=c;
 const columns={
  'private.expense_claims':['id uuid','revision integer','applicant_id uuid','applicant_name text','incurred_on date','description text','amount_yen integer','allocation text','counterparty_id uuid','approval text','withdrawn boolean default false'],
  'private.expense_settlement_choices':['claim_id uuid','method text','settlement_month date','approval_current boolean default false','cost_allocation_current boolean default false'],
  'private.expense_amount_consumptions':['claim_id uuid','purpose text','document_kind text','document_id uuid'],
 };
 for(const [table,fields]of Object.entries(columns))for(const field of fields)await db.exec(`alter table ${table} add column if not exists ${field}`);
 const source=await fs.readFile('supabase/migrations/20261012142138_expense_document_original_costs.sql','utf8');
 const marker='create function private.expense_cost_components(';
 const start=source.indexOf(marker),end=source.indexOf('revoke all on function private.expense_cost_components(',start);
 if(start<0||end<start||source.indexOf(marker,start+1)!==-1)throw Error('expense cost reader source anchor changed');
 await db.exec(source.slice(start,source.indexOf(';',end)+1).replace('create function','create or replace function'));
 for(const role of ['authenticated','anon'])check(await q('select has_function_privilege($1,$2,\'EXECUTE\') v',[role,'private.expense_cost_components(text,uuid,uuid,date,date,uuid)']),false);
 const customer=await q('select customer_id v from public.invoices where id=$1',[pending.parent]);
 const active=(kind='invoice',company=A,party=customer,document=pending.parent)=>q('select private.expense_cost_components($1,$2,$3,\'2020-10-01\',\'2020-10-31\',$4) v',[kind,company,party,document]);
 const insertRows=async()=>{
  for(const [n,company,party,day,approval,withdrawn,approvalCurrent,costCurrent,allocation,amount]of [
   [52001,A,customer,'2020-10-20','approved',false,true,true,'customer',1500],
   [52002,A,customer,'2020-10-21','approved',false,true,true,'customer',500],
   [52003,B,customer,'2020-10-20','approved',false,true,true,'customer',90000],
   [52004,A,id(52999),'2020-10-20','approved',false,true,true,'customer',80000],
   [52005,A,customer,'2020-09-30','approved',false,true,true,'customer',70000],
   [52006,A,customer,'2020-10-20','pending',false,true,true,'customer',60000],
   [52007,A,customer,'2020-10-20','approved',true,true,true,'customer',50000],
   [52008,A,customer,'2020-10-20','approved',false,false,true,'customer',40000],
   [52009,A,customer,'2020-10-20','approved',false,true,false,'customer',30000],
   [52010,A,customer,'2020-10-20','approved',false,true,true,'company',20000],
   [52011,A,customer,'2020-10-20','approved',false,true,true,'customer',10000],
  ]){
   await db.query('insert into private.expense_claims(id,company_id,revision,applicant_id,applicant_name,incurred_on,description,amount_yen,allocation,counterparty_id,approval,withdrawn) values($1,$2,1,$3,\'合成申請者\',$4,\'合成追加原価\',$5,$6,$7,$8,$9)',[id(n),company,UA,day,amount,allocation,party,approval,withdrawn]);
   await db.query('insert into private.expense_settlement_choices(company_id,claim_id,method,settlement_month,approval_current,cost_allocation_current) values($1,$2,\'cash\',\'2020-10-01\',$3,$4)',[company,id(n),approvalCurrent,costCurrent]);
  }
  // A claim already captured by this same document remains a stable source;
  // the other-document capture must never be charged twice.
  await db.query('insert into private.expense_amount_consumptions(company_id,claim_id,purpose,document_kind,document_id) values($1,$2,\'cost_recovery\',\'invoice\',$3),($1,$4,\'cost_recovery\',\'invoice\',$5)',[A,id(52002),pending.parent,id(52011),id(52998)]);
 };
 await db.exec('begin');
 try{
  await insertRows();
  const value=await active();check(value.amount_yen,2000);check(value.claims.map(x=>x.id),[id(52001),id(52002)]);check(value.has_choices,true);
  check((await active('paymentCertificate')).amount_yen,0);
  check((await active('invoice',B)).amount_yen,90000);
  check((await active('invoice',A,id(52997))).has_choices,false);
  check((await active('invoice',A,customer,id(52996))).amount_yen,1500);
  const proposal=await q('select invoice_month_close_candidate.preview_for_approver($1) v',[pending.parent]);
  check(proposal.grand_total,112000);check(proposal.proposed_snapshot.expense_extra_amount_yen,2000);check(proposal.proposed_snapshot.expense_extra_claims.length,2);
  check(await q('select invoice_month_close_candidate.guarded($1) v',[pending.parent]),'data_changed');
  await db.query('update private.expense_settlement_choices set approval_current=false where claim_id=$1',[id(52001)]);
  check((await active()).amount_yen,500);
  check((await q('select invoice_month_close_candidate.preview_for_approver($1) v',[pending.parent])).grand_total,110500);
 }finally{await db.exec('rollback');}
 check((await active()).amount_yen,0);check((await active()).has_choices,false);
 check(await q('select invoice_month_close_candidate.guarded($1) v',[pending.parent]),'ready');
 return async()=>{
  const before=await q('select invoice_month_close_candidate.preview_for_approver($1) v',[pending.parent]);
  await insertRows();
  const proposal=await q('select invoice_month_close_candidate.preview_for_approver($1) v',[pending.parent]);
  check(proposal.grand_total,Number(before.grand_total)+2000);
  check(proposal.proposed_snapshot.expense_extra_amount_yen,2000);
  await db.query('update public.invoices set snapshot=$1::jsonb,subtotal=$2,tax=$3,welfare_amount=$4,grand_total=$5,updated_at=clock_timestamp() where id=$6',[JSON.stringify(proposal.proposed_snapshot),proposal.subtotal,proposal.tax,proposal.welfare,proposal.grand_total,pending.parent]);
  check(await q('select invoice_month_close_candidate.guarded($1) v',[pending.parent]),'ready');
 };
}
