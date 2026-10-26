import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
import path from 'node:path';
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
 }
 console.log(JSON.stringify({checks,nativeConcurrentSessions:2,productionApplied:false}));
} finally {await left.end();await right.end();await db.client.end();}
