import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
import path from 'node:path';
import fs from 'node:fs';
if(!process.argv[2])throw Error('runtime module required');
process.env.SKO_DOCUMENT_ADJUSTMENT_HOLD_FIXTURE='1';
const runtimeUrl=pathToFileURL(path.resolve(process.argv[2])).href;
process.argv[2]=runtimeUrl;
const runtime=await import(runtimeUrl);
await import('./verify_adjustment_real_refresh.mjs');
const db=runtime.fixtureDb(),left=await runtime.connectFixture(),right=await runtime.connectFixture();
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const [company,actor,customer,,partner]=[1,2,3,4,5].map(id);
for(const c of [left,right]) await c.query(`set test.uid='${actor}';set role authenticated;set statement_timeout='8s';set lock_timeout='5s'`);
let checks=0;
const command=(kind,party,month,amount)=>({command_id:crypto.randomUUID(),company_id:company,kind,party_id:party,
 month,expected_version:0,action:'add',entry_id:null,sign:'plus',title:'並行合成項目',amount_yen:amount,
 recurrence:'once',effective_month:month,calculation_mode:'settlement_yen',site_id:null,expected_template_version:null,update_scope:'current_month'});
const preview=async c=>(await db.query('select public.preview_trade_document_adjustment($1) v',[JSON.stringify(c)])).rows[0].v;
const apply=async(client,c,p)=>(await client.query('select public.apply_trade_document_adjustment($1,$2) v',[JSON.stringify(c),p.token])).rows[0].v;
const rightPid=(await right.query('select pg_backend_pid() pid')).rows[0].pid;
await db.exec(`alter table public.invoice_approvals add column company_id uuid,add column approver_user_id uuid,
 add column position integer,add column approved_at timestamptz,add column display_date_override date;
 create unique index fixture_invoice_approver_unique on public.invoice_approvals(invoice_id,approver_user_id);
 create table public.invoice_approvers(company_id uuid,user_id uuid,position integer);
 create table public.invoice_approval_audit(invoice_id uuid,company_id uuid,actor_user_id uuid,action text);
 insert into public.invoice_approvers values('${company}','${actor}',1);`);
for(const file of ['private.ensure_invoice_approval_rows.sql','public.approve_invoice.sql']) {
 await db.exec(fs.readFileSync(new URL('../supabase/tests/fixtures/trade_document_adjustments_20261026/'+file,import.meta.url),'utf8'));
}
const settle=promise=>promise.then(value=>({ok:true,value}),error=>({ok:false,error}));
async function waitForRightLock() {
 const deadline=Date.now()+3000;
 while(Date.now()<deadline) {
  const row=(await db.query('select wait_event_type from pg_stat_activity where pid=$1',[rightPid])).rows[0];
  if(row?.wait_event_type==='Lock')return;
  await new Promise(resolve=>setTimeout(resolve,20));
 }
 throw Error('expected second session to block on a real PostgreSQL lock');
}
try {
 for(const [kind,party] of [['invoice',customer],['payment_certificate',partner]]) {
  const a=command(kind,party,'2026-12-01',7),b=command(kind,party,'2026-12-01',9);
  const pa=await preview(a),pb=await preview(b);
  const results=await Promise.allSettled([apply(left,a,pa),apply(right,b,pb)]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);checks++;
  assert.equal(results.filter(r=>r.status==='rejected').length,1);checks++;
  const index=results[0].status==='fulfilled'?0:1,c=index===0?a:b,p=index===0?pa:pb;
  const receipt=results[index].value;
  const retry=await Promise.all([apply(left,c,p),apply(right,c,p)]);
  assert.deepEqual(retry,[receipt,receipt]);checks++;
  const lookup=(await right.query('select public.lookup_trade_document_adjustment($1,$2) v',[company,c.command_id])).rows[0].v;
  assert.deepEqual(lookup,receipt);checks++;
  const count=(await db.query("select count(*)::int n from document_adjustment_private.commands where request->>'month'='2026-12-01' and request->>'kind'=$1",[kind])).rows[0].n;
  assert.equal(count,1);checks++;
  const monthly={...command(kind,party,'2027-01-01',10),recurrence:'monthly'};
  const mp=await preview(monthly),mr=await apply(left,monthly,mp);
  for(const month of ['2027-02-01','2027-03-01'])await db.query('select public.read_trade_document_adjustments($1,$2,$3,$4)',[company,kind,month,party]);
  const table=kind==='invoice'?'invoices':'payment_certificates',period=kind==='invoice'?'billing_period_start':'period_start';
  await db.query(`update ${table} set status='finalized',finalized_at=now() where company_id=$1 and ${period}='2027-03-01'`,[company]);
  const frozen=(await db.query(`select snapshot from ${table} where company_id=$1 and ${period}='2027-03-01'`,[company])).rows[0].snapshot;
  const edit=amount=>({...monthly,command_id:crypto.randomUUID(),action:'edit',entry_id:mr.entry_id,
   expected_version:1,expected_template_version:1,update_scope:'from_month',amount_yen:amount});
  const ea=edit(11),eb=edit(12),epa=await preview(ea),epb=await preview(eb);
  const edits=await Promise.allSettled([apply(left,ea,epa),apply(right,eb,epb)]);
  assert.equal(edits.filter(r=>r.status==='fulfilled').length,1);checks++;
  assert.equal(edits.filter(r=>r.status==='rejected').length,1);checks++;
  const win=edits.find(r=>r.status==='fulfilled').value;
  const feb=(await db.query('select document_adjustment_private.source($1,$2,$3,$4) v',[company,kind,party,'2027-02-01'])).rows[0].v;
  assert.equal(feb.total,win.result_total_yen);checks++;
  const unchanged=(await db.query(`select snapshot from ${table} where company_id=$1 and ${period}='2027-03-01'`,[company])).rows[0].snapshot;
  assert.deepEqual(unchanged,frozen);checks++;

  // These are lock-order tests, not a substitute for production RLS tests.
  // Fixture owner sessions model security-definer callers of the original
  // finance/confirmation functions. auth.uid remains the synthetic admin.
  await left.query('reset role');await right.query('reset role');
  const total=kind==='invoice'?'grand_total':'net_amount';
  const refreshName=kind==='invoice'?'private.refresh_automatic_invoice':'private.refresh_automatic_payment_certificate';
  const source=async month=>(await db.query('select document_adjustment_private.source($1,$2,$3,$4) v',[company,kind,party,month])).rows[0].v;
  const saved=async month=>(await db.query(`select status,snapshot,${total} total from ${table} where company_id=$1 and ${period}=$2`,[company,month])).rows[0];
  const finalizeSql=`update ${table} set status='finalized',finalized_at=clock_timestamp() where company_id=$1 and ${period}=$2`;

  // Finalization wins: its real triggers retain the scope lock until COMMIT.
  const fMonth='2027-04-01',fc=command(kind,party,fMonth,2),fp=await preview(fc);
  await left.query('begin');await left.query(finalizeSql,[company,fMonth]);
  const finalFirst=settle(apply(right,fc,fp));
  await waitForRightLock();checks++;
  await left.query('commit');
  const finalRejected=await finalFirst;
  assert.equal(finalRejected.ok,false);assert.match(finalRejected.error.message,/確定|承認/);checks++;
  const fs=await saved(fMonth);assert.equal(fs.status,'finalized');checks++;
  assert.equal(fs.total,fp.base_total_yen);checks++;
  assert.equal((await db.query('select count(*)::int n from document_adjustment_private.commands where command_id=$1',[fc.command_id])).rows[0].n,0);checks++;

  // Inverse lock order: finalize owns the row, apply owns the scope and waits
  // for that row. Original expense_cost_scope_lock must fail fast (40001),
  // rather than waiting for the scope and deadlocking against apply.
  const aMonth='2027-05-01',ac=command(kind,party,aMonth,3),ap=await preview(ac);
  await left.query('begin');
  await left.query(`select id from ${table} where company_id=$1 and ${period}=$2 for update`,[company,aMonth]);
  const applyFirst=settle(apply(right,ac,ap));
  await waitForRightLock();checks++;
  let finalizeError;
  try {await left.query(finalizeSql,[company,aMonth]);}catch(error){finalizeError=error;}
  assert.equal(finalizeError?.code,'40001');checks++;
  await left.query('rollback');
  const applied=await applyFirst;assert.equal(applied.ok,true);checks++;
  assert.equal((await saved(aMonth)).total,ap.result_total_yen);checks++;
  await left.query(finalizeSql,[company,aMonth]);
  const afterRetry=await saved(aMonth);assert.equal(afterRetry.status,'finalized');checks++;
  assert.equal(afterRetry.total,ap.result_total_yen);checks++;

  // Ordinary refresh wins, then apply resumes against the same unchanged base.
  const rMonth='2027-06-01',rc=command(kind,party,rMonth,4),rp=await preview(rc);
  await left.query('begin');await left.query(`select ${refreshName}($1,$2,$3)`,[company,party,rMonth]);
  const afterRefresh=settle(apply(right,rc,rp));
  await waitForRightLock();checks++;
  await left.query('commit');
  const resumed=await afterRefresh;assert.equal(resumed.ok,true);checks++;
  assert.equal((await saved(rMonth)).total,rp.result_total_yen);checks++;

  // Apply wins, then an ordinary refresh sees committed ledger exactly once.
  const pMonth='2027-07-01',pc=command(kind,party,pMonth,5),pp=await preview(pc);
  await left.query('begin');const committed=await apply(left,pc,pp);
  const normalRefresh=settle(right.query(`select ${refreshName}($1,$2,$3)`,[company,party,pMonth]));
  await waitForRightLock();checks++;
  await left.query('commit');
  const refreshed=await normalRefresh;assert.equal(refreshed.ok,true);checks++;
  assert.equal((await source(pMonth)).total,committed.result_total_yen);checks++;
  assert.equal((await db.query('select count(*)::int n from document_adjustment_private.commands where command_id=$1',[pc.command_id])).rows[0].n,1);checks++;

  if(kind==='invoice') {
   // Real current approval RPC: company FOR UPDATE -> invoice FOR UPDATE ->
   // approval row -> approval_finalized_at -> original scope try-lock trigger.
   const month='2027-08-01',c=command(kind,party,month,6),p=await preview(c),s=await source(month);
   await left.query('begin');
   assert.equal((await left.query('select public.approve_invoice($1) v',[s.id])).rows[0].v,true);checks++;
   const waiting=settle(apply(right,c,p));await waitForRightLock();checks++;
   await left.query('commit');
   const rejected=await waiting;assert.equal(rejected.ok,false);assert.match(rejected.error.message,/確定|承認/);checks++;
   assert.equal((await saved(month)).total,p.base_total_yen);checks++;

   const nextMonth='2027-09-01',nc=command(kind,party,nextMonth,7),np=await preview(nc),ns=await source(nextMonth);
   await left.query('begin');
   await left.query('select id from companies where id=$1 for update',[company]);
   await left.query('select id from invoices where id=$1 for update',[ns.id]);
   const adding=settle(apply(right,nc,np));await waitForRightLock();checks++;
   let approvalError;try{await left.query('select public.approve_invoice($1)',[ns.id]);}catch(error){approvalError=error;}
   assert.equal(approvalError?.code,'40001');checks++;
   await left.query('rollback');
   const added=await adding;assert.equal(added.ok,true);checks++;
   assert.equal((await saved(nextMonth)).total,np.result_total_yen);checks++;
   assert.equal((await left.query('select public.approve_invoice($1) v',[ns.id])).rows[0].v,true);checks++;
  }
 }
 console.log(JSON.stringify({checks,nativeConcurrentSessions:2,productionApplied:false}));
} finally {await left.end();await right.end();await db.client.end();}
