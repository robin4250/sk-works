import fs from 'node:fs';
import assert from 'node:assert/strict';
const {PGlite}=await import(process.argv[2]);
const db=new PGlite();
await db.exec(`create role anon;create role authenticated;create role service_role;create table public.companies(id uuid primary key);
create table public.invoices(id uuid);create table public.payment_certificates(id uuid);`);
await db.exec(fs.readFileSync(new URL('../supabase/review/document_adjustments.sql',import.meta.url),'utf8'));
const pgRound=x=>Math.sign(x)*Math.floor(Math.abs(x)+0.5);
let checks=0;
for (const base of [0,1,5,49,50,51,99,100,1001,10001]) {
 for(const delta of [-101,-50,-1,1,5,50,101]) {
  for(const welfare of [0,5,7.5,10]) {
   const tax=10;
   const total=b=>b+pgRound(b*welfare/100)+pgRound((b+pgRound(b*welfare/100))*tax/100);
   const {rows}=await db.query('select document_adjustment_private.charge_delta($1,$2,$3,$4) v',[base,delta,welfare,tax]);
   assert.equal(rows[0].v.total_delta_yen,total(base+delta)-total(base));checks++;
  }
 }
}
for(const invalid of [[null,1,0,10],[0,1,-1,10],[0,1,0,101]]) {
 await assert.rejects(db.query('select document_adjustment_private.charge_delta($1,$2,$3,$4)',invalid));checks++;
}
const grants=await db.query(`select has_schema_privilege('authenticated','document_adjustment_private','usage') allowed`);
assert.equal(grants.rows[0].allowed,false);checks++;
const rls=await db.query(`select bool_and(relrowsecurity) ok from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='document_adjustment_private' and c.relkind='r'`);
assert.equal(rls.rows[0].ok,true);checks++;
const company='11111111-1111-4111-8111-111111111111',party='22222222-2222-4222-8222-222222222222',actor='33333333-3333-4333-8333-333333333333';
await db.query('insert into companies values($1)',[company]);
await db.query('insert into document_adjustment_private.rollout(company_id) values($1)',[company]);
const template=(await db.query(`insert into document_adjustment_private.templates(company_id,kind,party_id,recurrence,created_by) values($1,'invoice',$2,'monthly',$3) returning id`,[company,party,actor])).rows[0].id;
await db.query(`insert into document_adjustment_private.template_versions(template_id,version,effective_month,title,sign,amount_yen,calculation_mode,actor_id) values($1,1,'2026-10-01','検証項目','plus',100,'settlement_yen',$2)`,[template,actor]);
const items=async(month,kind='invoice',p=party)=>(await db.query('select document_adjustment_private.active_items($1,$2,$3,$4) v',[company,kind,p,month])).rows[0].v;
assert.equal((await items('2026-10-01')).length,0);checks++;
await db.query('update document_adjustment_private.rollout set enabled=true where company_id=$1',[company]);
assert.equal((await items('2026-09-01')).length,0);checks++;
assert.equal((await items('2026-10-01')).length,1);checks++;
assert.equal((await items('2026-11-01')).length,1);checks++;
assert.equal((await items('2026-10-01','payment_certificate')).length,0);checks++;
assert.equal((await items('2026-10-01','invoice',actor)).length,0);checks++;
await db.query(`insert into document_adjustment_private.template_versions(template_id,version,effective_month,title,sign,amount_yen,calculation_mode,actor_id,stopped) values($1,2,'2026-12-01','停止','plus',100,'settlement_yen',$2,true)`,[template,actor]);
assert.equal((await items('2026-11-01')).length,1);checks++;
assert.equal((await items('2026-12-01')).length,0);checks++;
await db.query(`insert into document_adjustment_private.occurrences(template_id,month,template_version,canceled) values($1,'2026-10-01',1,true)`,[template]);
assert.equal((await items('2026-10-01')).length,0);checks++;
assert.equal((await items('2026-11-01')).length,1);checks++;
const site='44444444-4444-4444-8444-444444444444';
const line=(amount,sign='plus',mode='before_charges')=>({title:'項目',site_id:site,amount_yen:amount,sign,calculation_mode:mode});
const snapshot={tax_rate_bps:1000,sites:[{site_id:site,subtotal:105,welfare_rate_bps:500,lines:[{work_content:'（法定福利費）',amount:5}]}]};
const preview=async(kind,snap,old,next)=>(await db.query('select document_adjustment_private.preview_delta($1,$2,$3,$4) v',[kind,JSON.stringify(snap),JSON.stringify(old),JSON.stringify(next)])).rows[0].v;
assert.equal((await preview('invoice',snapshot,[],[line(1)])).total_delta_yen,1);checks++;
assert.equal((await preview('invoice',snapshot,[],[line(50,'minus')])).total_delta_yen,-58);checks++;
assert.equal((await preview('invoice',snapshot,[],[line(50,'minus','settlement_yen')])).total_delta_yen,-50);checks++;
assert.equal((await preview('invoice',snapshot,[line(50,'plus','settlement_yen')],[line(50,'minus','settlement_yen')])).total_delta_yen,-100);checks++;
await assert.rejects(preview('invoice',{...snapshot,sites:[]},[],[line(1)]));checks++;
const ps={welfare_rate:5,tax_rate:10,calculation_rows:[{work_content:'作業',amount_yen:100},{work_content:'福利厚生費',amount_yen:5},{work_content:'消費税',amount_yen:11}]};
assert.equal((await preview('payment_certificate',ps,[],[line(50,'minus')])).total_delta_yen,-58);checks++;
console.log(JSON.stringify({checks,scope:'candidate schema and real-source rounding arithmetic only',refreshIntegration:false,productionApplied:false}));
await db.close();
