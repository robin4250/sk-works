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
const source=await readFile(new URL('../supabase/migrations/20261010160154_company_seal_png_designs.sql',import.meta.url),'utf8');
// Use the current official snapshot body, including registered-name/style and
// fixed PNG company-scope validation. Do not construct a replacement seal.
await db.exec(source.slice(source.indexOf('create or replace function private.document_company_seal_snapshot')));
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
const preview=async(c,proposal=null)=>(await db.query('select public.preview_site_contract_seal($1,$2,$3) v',[item,c,proposal])).rows[0].v;
const send=async(revision,t=terms,hash=undefined)=>{if(hash===undefined) hash=(await preview(a)).seal_hash; return (await db.query('select public.send_sealed_site_contract($1,$2,$3,$4,$5) id',[item,a,revision,t,hash])).rows[0].id;};
const initialPreview=await preview(a);
assert.match(initialPreview.seal_hash,/^[a-f0-9]{64}$/);
assert.equal(initialPreview.company_id,a);
assert.equal(initialPreview.shared_item_id,item);
assert.equal(initialPreview.proposal_id,null);
assert.equal(initialPreview.revision,0);
assert.equal(initialPreview.seal_snapshot.name,'株式会社青空');
await assert.rejects(db.query('select public.preview_site_contract_seal($1,$2,null)',[item,b]),/管理者/);
await assert.rejects(db.query('select public.preview_site_contract_seal($1,$2,null)',[a,a]),/共有現場/);
await assert.rejects(send(0,terms,null),/プレビュー/);
await assert.rejects(send(0,terms,'forged'),/プレビュー/);
const counts=async()=>{await db.exec('reset role');const result=(await db.query(`select
 (select count(*)::int from private.site_payment_proposals) proposals,
 (select count(*)::int from private.site_contract_seals) seals,
 (select count(*)::int from private.site_payment_confirmations) confirmations,
 (select count(*)::int from private.site_contract_notification_outbox) notifications`)).rows[0];
 await db.exec('set role authenticated');return result;};
const emptyCounts=await counts();
await db.exec(`reset role; update companies set name='株式会社改名',company_seal_style='aoyagi_reisho' where id='${a}'; set role authenticated;`);
await assert.rejects(send(0,terms,initialPreview.seal_hash),/プレビュー/);
assert.deepEqual(await counts(),emptyCounts);
const changed=await preview(a);
assert.notEqual(changed.seal_hash,initialPreview.seal_hash);
assert.equal(changed.seal_snapshot.name,'株式会社改名');
await db.exec(`reset role; update companies set name='株式会社青空',company_seal_style='legacy' where id='${a}'; set role authenticated;`);
await assert.rejects(send(0,{...terms,final_amount_yen:1}),/最終額/);
const p=await send(0);
await db.exec(`set test.uid='${actorB}'`);
await assert.rejects(db.query('select public.confirm_site_payment_terms($1,$2)',[p,b]),/押印承認/);
const approvalPreview=await preview(b,p);
assert.equal(approvalPreview.proposal_id,p);
assert.equal(approvalPreview.revision,1);
await assert.rejects(preview(b,item),/最新版/);
const beforeApproval=await counts();
await assert.rejects(db.query('select public.approve_sealed_site_contract($1,$2,0,$3)',[p,b,approvalPreview.seal_hash]),/最新版/);
await assert.rejects(db.query('select public.approve_sealed_site_contract($1,$2,1,$3)',[p,b,null]),/プレビュー/);
await db.exec(`reset role; update companies set company_seal_style='aoyagi_reisho' where id='${b}'; set role authenticated;`);
await assert.rejects(db.query('select public.approve_sealed_site_contract($1,$2,1,$3)',[p,b,approvalPreview.seal_hash]),/プレビュー/);
assert.deepEqual(await counts(),beforeApproval);
const approvedPreview=await preview(b,p);
await db.query('select public.approve_sealed_site_contract($1,$2,1,$3)',[p,b,approvedPreview.seal_hash]);
await db.exec('reset role');
const oldSeals=(await db.query('select * from private.site_contract_seals order by company_id')).rows;
await db.exec(`update companies set company_seal_style='legacy' where id='${b}'; set role authenticated;`);
await db.query('select public.approve_sealed_site_contract($1,$2,1,$3)',[p,b,approvedPreview.seal_hash]);
await assert.rejects(db.query('select public.approve_sealed_site_contract($1,$2,1,$3)',[p,b,null]),/保存済み/);
await db.exec('reset role');
assert.deepEqual((await db.query('select * from private.site_contract_seals order by company_id')).rows,oldSeals);
await db.exec('set role authenticated');
const workspace=(await db.query('select public.site_contract_workspace($1,$2) v',[item,b])).rows[0].v;
assert.equal(workspace.proposals[0].seals.length,2);
assert.equal(workspace.proposals[0].seals[0].seal_snapshot.version,1);
const doc=(await db.query('select public.saved_site_payment_document($1,$2) v',[p,b])).rows[0].v;
assert.equal(doc.terms.final_amount_yen,16500);
await db.exec(`set test.uid='${actorA}'`);
await send(1);
await db.exec(`set test.uid='${actorB}'`);
await assert.rejects(preview(b,p),/最新版/);
await assert.rejects(db.query('select public.approve_sealed_site_contract($1,$2,1,$3)',[p,b,approvalPreview.seal_hash]),/最新版/);
await db.exec(`set test.uid='${actorA}'`);
const latest=(await db.query('select public.site_contract_workspace($1,$2) v',[item,a])).rows[0].v;
assert.equal(latest.proposals[0].confirmations.length,1);
assert.equal(latest.proposals[1].confirmations.length,2);
const beforeBoundaryChecks=await counts();
const validHash=(await preview(a)).seal_hash;
await db.exec(`reset role; update private.company_connections set status='revoked'; set role authenticated;`);
await assert.rejects(send(2,terms,validHash),/対応/);
await db.exec(`reset role; update private.company_connections set status='accepted'; update companies set name='' where id='${a}'; set role authenticated;`);
await assert.rejects(preview(a),/name is missing/);
await db.exec(`reset role; update companies set name='株式会社青空' where id='${a}';
 create or replace function private.account_access_allowed() returns boolean language sql as $$select auth.uid() is not null and current_setting('test.restricted',true) is distinct from 'true'$$;
 set role authenticated; set test.restricted='true';`);
await assert.rejects(preview(a),/管理者/);
await assert.rejects(send(2,terms,validHash),/管理者/);
await db.exec(`set test.restricted='false'`);
assert.deepEqual(await counts(),beforeBoundaryChecks);
await db.exec(`reset role; update companies set company_seal_enabled=false where id='${a}'; set role authenticated;`);
await assert.rejects(preview(a),/有効/);
await db.exec(`reset role; update companies set company_seal_enabled=true where id='${a}'; update company_members set role='manager' where user_id='${actorA}'; set role authenticated;`);
await assert.rejects(preview(a),/管理者/);
await db.exec(`reset role; update company_members set role='admin' where user_id='${actorA}'; set role authenticated;`);
await db.exec(`set test.uid=''`);
await assert.rejects(preview(a),/管理者/);
await db.exec(`set test.uid='${actorA}'`);
const acl=(await db.query(`select has_function_privilege('anon','public.preview_site_contract_seal(uuid,uuid,uuid)','execute') anon,
 has_function_privilege('authenticated','public.preview_site_contract_seal(uuid,uuid,uuid)','execute') authenticated,
 to_regprocedure('public.send_sealed_site_contract(uuid,uuid,integer,jsonb)') legacy_send,
 to_regprocedure('public.approve_sealed_site_contract(uuid,uuid)') legacy_approve`)).rows[0];
assert.deepEqual(acl,{anon:false,authenticated:true,legacy_send:null,legacy_approve:null});
await db.exec(`reset role; update private.site_payment_agreement_rollout set enabled=false where company_id='${a}'; set role authenticated;`);
await assert.rejects(send(2),/未有効/);
console.log('PASS SHA256 preview, changed-name/style rollback, expected revision/hash, preview item/company/old-version boundaries, sealed snapshot immutability, disabled seals, roles/anon, no legacy bypass; real agreement amount validation, official seal snapshot, authenticated wrappers, legacy bypass rejection, prior version preservation, rollout stop');
} finally {await db.close();}
