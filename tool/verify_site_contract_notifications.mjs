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
await db.exec(await readFile(new URL('../supabase/migrations/20261015080425_site_contract_sealed_revision.sql',import.meta.url),'utf8'));
await db.exec('create table auth.users(id uuid primary key);');
await db.exec(await readFile(new URL('../supabase/migrations/20260919213000_add_app_notifications.sql',import.meta.url),'utf8'));
await db.exec(await readFile(new URL('../supabase/migrations/20261015084135_site_contract_notification_delivery.sql',import.meta.url),'utf8'));
const ids=Array.from({length:8},(_,i)=>`00000000-0000-0000-0000-${String(i+1).padStart(12,'0')}`);
const [a,b,actorA,actorB,siteA,siteB,delivery,item]=ids;
await db.exec(`insert into auth.users values('${actorA}'),('${actorB}'); insert into companies(id,name) values('${a}','株式会社青空'),('${b}','株式会社山田');
 insert into company_members values('${a}','${actorA}','admin'),('${a}','${actorA}','admin'),('${b}','${actorB}','admin'),('${a}','${actorB}','member');
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
const notifications=async()=>{await db.exec('reset role'); const rows=(await db.query('select * from public.app_notifications order by recipient_user_id,created_at,id')).rows; await db.exec('set role authenticated'); return rows;};
assert.equal((await notifications()).length,0);
const proposal=await send(0);
let notices=await notifications(); assert.equal(notices.length,2);
assert(notices.every(n=>n.action_key==='site_payment_agreement'&&n.action_id===item));
const mine=notices.find(n=>n.recipient_user_id===actorA), other=notices.find(n=>n.recipient_user_id===actorB);
const target=(await db.query('select public.get_site_contract_notification_target($1) v',[mine.id])).rows[0].v;
assert.deepEqual(target,{company_id:a,shared_item_id:item,proposal_id:proposal,event:'terms_sent'});
await assert.rejects(db.query('select public.get_site_contract_notification_target($1)',[other.id]),/権限/);
await assert.rejects(db.query('select private.deliver_site_contract_notification()'),/permission denied/);
await assert.rejects(db.query('select * from private.site_contract_notification_receipts'),/permission denied/);
await db.exec(`reset role; update public.app_notifications set action_id='${a}' where id='${mine.id}'; set role authenticated;`);
await assert.rejects(db.query('select public.get_site_contract_notification_target($1)',[mine.id]),/対象/);
await db.exec(`reset role; update public.app_notifications set action_id='${item}' where id='${mine.id}';
 insert into public.app_notifications(company_id,recipient_user_id,title,action_key,action_id) values('${a}','${actorA}','偽通知','site_payment_agreement','${item}');
 set role authenticated;`);
await db.exec('reset role');
const forged=(await db.query("select id from public.app_notifications where title='偽通知'")).rows[0];
await db.exec('set role authenticated');
await assert.rejects(db.query('select public.get_site_contract_notification_target($1)',[forged.id]),/権限/);
await db.exec("reset role; delete from public.app_notifications where title='偽通知'; set role authenticated;");
await db.exec(`set test.uid='${actorB}'`);
const approval=await preview(b,proposal);
await db.query('select public.approve_sealed_site_contract($1,$2,1,$3)',[proposal,b,approval.seal_hash]);
assert.equal((await notifications()).length,4);
await db.query('select public.approve_sealed_site_contract($1,$2,1,$3)',[proposal,b,approval.seal_hash]);
assert.equal((await notifications()).length,4);
// A notification write failure must roll back the entire proposal/seal/outbox transaction.
await db.exec(`set test.uid='${actorA}'; reset role;
 alter table public.app_notifications add constraint fixture_delivery_failure check(title not like '%送信%') not valid;
 set role authenticated;`);
await assert.rejects(send(1),/fixture_delivery_failure/);
assert.equal((await notifications()).length,4);
await db.exec('reset role');
assert.equal((await db.query('select count(*)::int n from private.site_payment_proposals')).rows[0].n,1);
assert.equal((await db.query('select count(*)::int n from private.site_contract_notification_outbox')).rows[0].n,4);
await db.exec(`alter table public.app_notifications drop constraint fixture_delivery_failure; set role authenticated; set test.uid='${actorB}';`);
await db.exec(`reset role; update private.site_payment_agreement_rollout set enabled=false where company_id='${a}'; set role authenticated;`);
await assert.rejects(db.query('select public.get_site_contract_notification_target($1)',[other.id]),/未有効/);
await db.exec(`reset role; update private.site_payment_agreement_rollout set enabled=true; update company_members set role='member' where user_id='${actorB}'; set role authenticated;`);
await assert.rejects(db.query('select public.get_site_contract_notification_target($1)',[other.id]),/管理者/);
await db.exec('reset role');
assert.equal((await db.query('select count(*)::int n from private.site_contract_notification_receipts')).rows[0].n,4);
console.log('PASS: actual agreement/seal/helper delivery, two companies, receipt isolation, replay dedupe, OFF and role revocation');
} finally {await db.close();}
