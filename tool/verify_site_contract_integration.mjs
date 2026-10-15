// Isolated PostgreSQL integration of the existing agreement SQL and new sealed layer.
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';
const { PGlite } = await import(pathToFileURL(process.argv[2]).href);
const db=new PGlite();
try {
// Reuse the maintained disposable schema fixture, never its application data.
const fixture=await readFile(new URL('verify_site_payment_agreement.mjs',import.meta.url),'utf8');
const schema=fixture.match(/await db\.exec\(`([\s\S]*?)`\);/)[1];
await db.exec(schema);
for (const file of ['20261008201215_site_payment_agreement_staged.sql',
 '20261008212855_site_payment_company_snapshot.sql']) {
 await db.exec(await readFile(new URL('../supabase/migrations/'+file,import.meta.url),'utf8'));
}
// Official snapshot function, with its real name/style validation dependencies.
await db.exec(`alter table companies add column company_seal_style text default 'legacy';
 create function private.aoyagi_reisho_name_supported(text) returns boolean language sql as $$select true$$;`);
const files=await import('node:fs/promises');
const names=await files.readdir(new URL('../supabase/migrations/',import.meta.url));
const name=names.find(n=>n.includes('company_seal_document_snapshots'));
const source=await readFile(new URL('../supabase/migrations/'+name,import.meta.url),'utf8');
// The helper is unchanged production code; unrelated document-table triggers
// do not belong to this fixture's schema.
await db.exec(source.slice(0,source.indexOf('create function private.preserve_document_company_seal_snapshot')));
await db.exec(await readFile(new URL('staged/site_contract_sealed_revision.sql',import.meta.url),'utf8'));
const ids=Array.from({length:8},(_,i)=>`00000000-0000-0000-0000-${String(i+1).padStart(12,'0')}`);
const [a,b,actorA,actorB,siteA,siteB,delivery,item]=ids;
await db.exec(`insert into companies(id,name) values('${a}','株式会社青空'),('${b}','株式会社山田');
 insert into company_members values('${a}','${actorA}','admin'),('${b}','${actorB}','admin');
 insert into sites values('${siteA}','${a}','現場'),('${siteB}','${b}','現場');
 insert into private.company_connections values('${a}','${b}','accepted');
 insert into private.document_deliveries values('${delivery}','${a}','${b}');
 insert into private.company_data_delivery_items values('${item}','${delivery}','site_share','{"source_site_id":"${siteA}"}');
 insert into private.site_share_inbox values('${item}','${b}','accepted','${siteB}');
 insert into private.site_payment_agreement_rollout values('${a}',true),('${b}',true);
 set test.uid='${actorA}'; set role authenticated;`);
const terms={period_start:'2026-10-01',period_end:'2026-10-31',effective_from:'2026-10-15',
 mode:'square_meter',unit_price_yen:1200,area:12.5,base_amount_yen:15000,adjustments:[],
 tax_included:false,tax_amount_yen:1500,tax_rate:10,taxable_amount_yen:15000,
 rounding_rule:'floor',final_amount_yen:16500};
const send=async(revision,t=terms)=>(await db.query('select public.send_sealed_site_contract($1,$2,$3,$4) id',[item,a,revision,t])).rows[0].id;
await assert.rejects(send(0,{...terms,final_amount_yen:1}),/最終額/);
const p=await send(0);
await db.exec(`set test.uid='${actorB}'`);
await assert.rejects(db.query('select public.confirm_site_payment_terms($1,$2)',[p,b]),/押印承認/);
await db.query('select public.approve_sealed_site_contract($1,$2)',[p,b]);
const workspace=(await db.query('select public.site_contract_workspace($1,$2) v',[item,b])).rows[0].v;
assert.equal(workspace.proposals[0].seals.length,2);
assert.equal(workspace.proposals[0].seals[0].seal_snapshot.version,1);
const doc=(await db.query('select public.saved_site_payment_document($1,$2) v',[p,b])).rows[0].v;
assert.equal(doc.terms.final_amount_yen,16500);
await db.exec(`set test.uid='${actorA}'`);
await send(1);
const latest=(await db.query('select public.site_contract_workspace($1,$2) v',[item,a])).rows[0].v;
assert.equal(latest.proposals[0].confirmations.length,1);
assert.equal(latest.proposals[1].confirmations.length,2);
await db.exec(`reset role; update private.site_payment_agreement_rollout set enabled=false where company_id='${a}'; set role authenticated;`);
await assert.rejects(send(2),/未有効/);
console.log('PASS real agreement amount validation, official seal snapshot, authenticated wrappers, legacy bypass rejection, prior version preservation, rollout stop');
} finally {await db.close();}
