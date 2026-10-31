// Disposable actual-consumer compatibility fixture. Never connects to production.
import fs from 'node:fs/promises';
const native=process.argv[2]==='postgres';
let db;
if(native){
 const url=new URL(process.env.SKO_COMPAT_FIXTURE_URL);
 if(url.hostname!=='127.0.0.1'||url.pathname!=='/sko_order_compat_fixture')throw Error('isolated localhost fixture only');
 const pg=await import(process.env.SKO_PG_MODULE);const Client=pg.Client??pg.default.Client;
 const client=new Client({connectionString:url.href,application_name:'sko-compat-owner'});await client.connect();
 db={query:(...a)=>client.query(...a),exec:s=>client.query(s),close:()=>client.end(),openPeer:async()=>{const peer=new Client({connectionString:url.href,application_name:'sko-compat-peer',statement_timeout:5000,lock_timeout:3000});await peer.connect();return peer;}};
}else{const {PGlite}=await import(process.env.SKO_PGLITE_MODULE);db=new PGlite();}
let checks=0;
const assert=(v,message)=>{if(!v)throw Error(message);checks++;};
const deny=async(fn,code)=>{let error;try{await fn();}catch(e){error=e;}assert(error?.code===code,`expected ${code}: ${error?.message}`);};
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
try{
const foundation=await fs.readFile('docs/review/site-order-package-flow/foundation.sql.review-only','utf8');
const packageDDL=foundation.slice(foundation.indexOf('create table site_order_package_private.packages('),foundation.indexOf('create table site_order_package_private.notice_intents('));
await db.exec(`create role authenticated;create schema private;create schema auth;create schema site_order_package_private;create schema site_order_artifact_private;create schema trade_document_consent_private;
create function private.account_access_allowed() returns boolean language sql as $$select true$$;
create function auth.uid() returns uuid language sql as $$select '${id(1)}'::uuid$$;
create table companies(id uuid primary key,name text);
create table company_members(company_id uuid,user_id uuid,role text);
create table private.document_deliveries(id uuid primary key,sender_company_id uuid,recipient_company_id uuid,sender_name text,recipient_name text,sent_by uuid,note text,saved_at timestamptz default now());
create table private.company_data_delivery_items(id uuid primary key default gen_random_uuid(),delivery_id uuid references private.document_deliveries(id),payload_kind text not null,payload jsonb not null check(jsonb_typeof(payload)='object'),company_path jsonb not null default '[]',source_item_id uuid,created_at timestamptz default now(),constraint company_data_delivery_items_payload_kind_check check(payload_kind in ('qualification','personnel')));
alter table private.company_data_delivery_items enable row level security;
create table private.document_delivery_items(id uuid primary key default gen_random_uuid(),delivery_id uuid,name text,bucket text,path text,company_path jsonb,source_item_id uuid,expires_at date,photo_order integer);
create table private.company_delivery_saved_items(company_id uuid,item_key text,saved_by uuid,saved_at timestamptz,primary key(company_id,item_key));
create table private.document_receive_codes(code uuid primary key,company_id uuid,created_by uuid,expires_at timestamptz default now()+interval '1 day',used_at timestamptz);
create table public.app_notifications(id uuid primary key default gen_random_uuid(),company_id uuid,recipient_user_id uuid,kind text,title text,body text,action_key text,action_id uuid);
create table site_order_artifact_private.render_jobs(id uuid primary key);
create table site_order_artifact_private.pdf_records(receipt_id uuid primary key);
${packageDDL}
alter table site_order_package_private.packages enable row level security;
create function trade_document_consent_private.immutable() returns trigger language plpgsql set search_path='' as $$begin raise exception 'immutable consent history';end $$;
revoke all on function trade_document_consent_private.immutable() from public;
create trigger immutable_package before update or delete on site_order_package_private.packages for each row execute function trade_document_consent_private.immutable();
create trigger immutable_package_truncate before truncate on site_order_package_private.packages for each statement execute function trade_document_consent_private.immutable();
insert into site_order_artifact_private.render_jobs values('${id(60)}');
insert into site_order_artifact_private.pdf_records values('${id(61)}');
create table private.site_share_inbox(data_item_id uuid primary key,recipient_company_id uuid,status text,created_at timestamptz,accepted_site_id uuid);
create table public.sites(id uuid primary key,company_id uuid,name text);
create table private.company_connections(parent_company_id uuid,child_company_id uuid,status text);
create table private.site_payment_agreement_rollout(company_id uuid,enabled boolean);
insert into companies values('${id(2)}','A'),('${id(3)}','B'),('${id(4)}','C');
insert into company_members values('${id(2)}','${id(1)}','owner');
insert into private.document_deliveries values('${id(10)}','${id(3)}','${id(2)}','B','A','${id(5)}','seed',now());
insert into private.company_data_delivery_items(id,delivery_id,payload_kind,payload) values('${id(11)}','${id(10)}','qualification','{"name":"Q"}'),('${id(12)}','${id(10)}','personnel','{"name":"P"}');
insert into private.document_delivery_items(id,delivery_id,name,bucket,path,company_path) values('${id(14)}','${id(10)}','file','old','preserved','[]');`);
const originals=JSON.parse(await fs.readFile('docs/review/site-order-compatibility/pinned-consumers.json','utf8'));
for(const f of originals)await db.exec(f.definition);
await db.exec('revoke all on function private.company_document_exchange(text,jsonb) from public;grant execute on function private.company_document_exchange(text,jsonb) to authenticated;revoke all on function private.site_payment_pair(uuid,uuid) from public;revoke all on function private.site_payment_agreement_targets(uuid) from public;grant execute on function private.site_payment_agreement_targets(uuid) to authenticated');
await deny(()=>db.exec(`insert into private.company_data_delivery_items(id,delivery_id,payload_kind,payload) values('${id(13)}','${id(10)}','site_share','{}')`),'23514');
const rows=async()=>JSON.stringify((await db.query('select * from private.company_data_delivery_items order by id')).rows);
const initial=await rows();
const attrs=async()=>JSON.stringify((await db.query(`select oid,to_jsonb(p)-'prosrc' metadata from pg_proc p where oid in(${originals.map(f=>`'${f.signature}'::regprocedure`).join(',')}) order by oid`)).rows);
await db.exec(await fs.readFile('tool/fixtures/site_order_legacy_private_respond.fixture.sql','utf8'));
await db.exec(await fs.readFile('tool/fixtures/site_order_legacy_public_respond.fixture.sql','utf8'));
await db.exec(`create temporary table site_order_legacy_expected(signature text primary key,attrs jsonb);
insert into site_order_legacy_expected select p.oid::regprocedure::text,to_jsonb(p)-'prosrc' from pg_proc p
where p.oid in ('private.respond_site_share(uuid,boolean)'::regprocedure,'public.respond_site_share(uuid,boolean)'::regprocedure)`);
// regprocedure renders the public name unqualified under the test search_path.
await db.exec("update site_order_legacy_expected set signature='public.respond_site_share(uuid,boolean)' where signature='respond_site_share(uuid,boolean)'");
await db.exec(await fs.readFile('docs/review/site-order-package-flow/legacy-response-guard.sql.review-only','utf8'));
const before=await attrs();
const patch=await fs.readFile('docs/review/site-order-compatibility/consumer-boundary.sql.review-only','utf8');
for(const change of [
 'alter table site_order_package_private.packages disable trigger immutable_package',
 'alter table site_order_package_private.packages disable row level security',
 'grant select on site_order_package_private.packages to authenticated',
 'create policy unexpected on site_order_package_private.packages using(true)',
 'alter table site_order_package_private.packages drop constraint packages_data_item_id_fkey',
 'alter table site_order_package_private.packages add column unknown_column text',
]){
 await db.exec('begin;'+change);
 await deny(()=>db.exec(patch),'P0001');await db.exec('rollback');
 assert(before===await attrs(),'dependency rejection preserves consumer metadata');
 assert(initial===await rows(),'dependency rejection preserves existing rows');
}
const invalidPatch=patch.replace("check(payload_kind in ('qualification','personnel','site_share'))",'check(false)');
await deny(()=>db.exec(invalidPatch),'23514');await db.exec('rollback');
assert(before===await attrs(),'failed patch all function attributes rolled back');
assert(initial===await rows(),'failed patch all existing rows preserved');
const sourceHashes=async()=>JSON.stringify((await db.query(`select oid,md5(prosrc) hash from pg_proc where oid in(${originals.map(f=>`'${f.signature}'::regprocedure`).join(',')}) order by oid`)).rows);
const hashesBefore=await sourceHashes();
await deny(()=>db.exec(invalidPatch),'23514');await db.exec('rollback');
assert(hashesBefore===await sourceHashes(),'failed patch source bodies rolled back');
if(native){
 const peer=await db.openPeer();
 try{
  await peer.query('begin;lock table private.company_data_delivery_items in access share mode');
  const started=db.exec(patch).then(()=>({ok:true}),error=>({error}));
  let observed=false;
  for(let i=0;i<30;i++){
   const state=await peer.query("select wait_event_type from pg_stat_activity where application_name='sko-compat-owner'");
   if(state.rows.some(r=>r.wait_event_type==='Lock')){observed=true;break;}
   await new Promise(resolve=>setTimeout(resolve,20));
  }
  assert(observed,'actual second-connection lock wait observed');
  const outcome=await started;
  assert(outcome.error?.code==='55P03','bounded deployment lock timeout');
  await db.exec('rollback');
  assert(hashesBefore===await sourceHashes(),'lock failure source unchanged');
  assert(initial===await rows(),'lock failure rows unchanged');
 }finally{await peer.query('rollback');await peer.end();}
}
await db.exec(patch);assert(before===await attrs(),'function OID/ACL/attributes preserved');assert(initial===await rows(),'existing rows unchanged');
await db.exec(`insert into private.company_data_delivery_items(id,delivery_id,payload_kind,payload) values('${id(13)}','${id(10)}','site_share','{}');insert into site_order_package_private.packages values('${id(20)}','${id(3)}','${id(2)}','${id(1)}','${id(70)}','${id(71)}','${id(60)}','${id(61)}','${id(13)}','{}',now());insert into private.site_share_inbox values('${id(13)}','${id(2)}','pending',now(),null)`);
await deny(()=>db.exec(`insert into private.company_data_delivery_items(id,delivery_id,payload_kind,payload) values('${id(99)}','${id(10)}','unknown','{}')`),'23514');
await deny(()=>db.exec(`insert into private.company_data_delivery_items(id,delivery_id,payload_kind,payload) values('${id(99)}','${id(10)}','personnel','[]')`),'23514');
const data=(await db.query("select private.company_document_exchange('data_items',$1::jsonb) v",[JSON.stringify({id:id(10)})])).rows[0].v;
assert(data.length===2&&data.every(x=>['qualification','personnel'].includes(x.payload_kind)),'generic read exact old kinds');
await db.query('select private.save_company_delivery_items($1::text[])',[[`data:${id(11)}`,`data:${id(12)}`,`file:${id(14)}`]]);
assert((await db.query('select count(*)::int n from private.company_delivery_saved_items')).rows[0].n===3,'old files/qualification/personnel saved');
await db.exec('delete from private.company_delivery_saved_items');
await deny(()=>db.query('select private.save_company_delivery_items($1::text[])',[[`data:${id(11)}`,`data:${id(13)}`]]),'22023');
assert((await db.query('select count(*)::int n from private.company_delivery_saved_items')).rows[0].n===0,'mixed batch no partial saves');
for(const bad of [null,'bad',`data:${id(11)}:extra`])await deny(()=>db.query('select private.save_company_delivery_items($1::text[])',[[bad]]),'22023');
await deny(()=>db.exec(`update site_order_package_private.packages set data_item_id='${id(11)}' where id='${id(20)}'`),'P0001');
assert((await db.query('select data_item_id from site_order_package_private.packages where id=$1',[id(20)])).rows[0].data_item_id===id(13),'immutable ownership binding preserved');
await deny(()=>db.query('select private.send_site_share($1,$2::uuid[])',[id(30),[id(3)]]),'22023');
assert((await db.query('select private.site_share_inbox() v')).rows[0].v.length===0,'owned package excluded from legacy inbox');
await deny(()=>db.query('select public.respond_site_share($1,true)',[id(13)]),'0A000');
await deny(()=>db.query('select public.respond_site_share($1,false)',[id(13)]),'0A000');
await deny(()=>db.query('select private.site_payment_pair($1,$2)',[id(13),id(2)]),'22023');
// Retain actual ten caller bodies only in the disposable test; not install sources.
await db.exec(`create table private.site_payment_proposals(id uuid primary key,shared_item_id uuid);
create table private.site_contract_seals(proposal_id uuid,company_id uuid,actor_id uuid,action text);
create table private.site_contract_notification_outbox(id uuid primary key,proposal_id uuid,event text,company_id uuid);
create table private.site_contract_notification_receipts(notification_id uuid,outbox_id uuid,recipient_user_id uuid);
insert into private.site_payment_proposals values('${id(80)}','${id(13)}');
insert into private.site_contract_seals values('${id(80)}','${id(2)}','${id(1)}','approved');
insert into private.site_contract_notification_outbox values('${id(81)}','${id(80)}','terms_approved','${id(2)}');
insert into public.app_notifications(id,company_id,recipient_user_id,action_key,action_id) values('${id(82)}','${id(2)}','${id(1)}','site_payment_agreement','${id(13)}');
insert into private.site_contract_notification_receipts values('${id(82)}','${id(81)}','${id(1)}');`);
const callers=JSON.parse(await fs.readFile('tool/site_order_compatibility/payment-callers.fixture.json','utf8'));
for(const f of callers){
 await db.exec(f.definition);
 assert((await db.query('select md5(prosrc) h from pg_proc where oid=$1::regprocedure',[f.signature])).rows[0].h===f.body_md5,'actual caller body unchanged');
}
await db.exec(`create trigger actual_contract_notice after insert on private.site_contract_notification_outbox for each row execute function private.deliver_site_contract_notification()`);
const callerState=async()=>JSON.stringify((await db.query(`select
 (select jsonb_agg(to_jsonb(p) order by id) from private.site_payment_proposals p) proposals,
 (select jsonb_agg(to_jsonb(n) order by id) from private.site_contract_notification_outbox n) outbox,
 (select jsonb_agg(to_jsonb(n) order by id) from public.app_notifications n) notifications,
 (select jsonb_agg(to_jsonb(s) order by data_item_id) from private.site_share_inbox s) inbox`)).rows);
const callerBefore=await callerState();
const blockedCalls=[
 ['select private.approve_sealed_site_contract($1,$2,1,$3)',[id(80),id(2),'not-used']],
 ['select private.confirm_site_payment_terms($1,$2)',[id(80),id(2)]],
 ['select private.preview_site_contract_seal($1,$2,$3)',[id(13),id(2),id(90)]],
 ["select private.propose_site_payment_terms($1,$2,1,'{}'::jsonb)",[id(13),id(2)]],
 ['select private.saved_site_payment_document($1,$2)',[id(80),id(2)]],
 ["select private.send_sealed_site_contract($1,$2,1,'{}'::jsonb,'not-used')",[id(13),id(2)]],
 ['select private.site_contract_workspace($1,$2)',[id(13),id(2)]],
 ['select private.get_site_contract_notification_target($1)',[id(82)]],
 ['select private.site_payment_agreement_workspace($1,$2)',[id(13),id(2)]],
 ["insert into private.site_contract_notification_outbox values($1,$2,'terms_approved',$3)",[id(83),id(80),id(2)]],
];
for(const [sql,args] of blockedCalls){
 let error;try{await db.query(sql,args);}catch(e){error=e;}
 assert(error?.code==='22023'&&error.message.includes('専用の承認経路'),'actual caller rejected by exact pair boundary');
 assert(callerBefore===await callerState(),'blocked caller preserves proposals/outbox/notifications/inbox');
}

await db.exec(`insert into sites values('${id(31)}','${id(3)}','legacy source'),('${id(32)}','${id(2)}','legacy recipient');
insert into private.company_connections values('${id(3)}','${id(2)}','accepted');
insert into private.site_payment_agreement_rollout values('${id(3)}',true),('${id(2)}',true);
insert into private.company_data_delivery_items(id,delivery_id,payload_kind,payload) values('${id(15)}','${id(10)}','site_share','{"source_site_id":"${id(31)}"}');
insert into private.site_share_inbox values('${id(15)}','${id(2)}','accepted',now(),'${id(32)}');
update private.site_share_inbox set status='accepted',accepted_site_id='${id(32)}' where data_item_id='${id(13)}';
update private.company_data_delivery_items set payload='{"source_site_id":"${id(31)}"}' where id='${id(13)}';`);
assert((await db.query('select private.site_payment_pair($1,$2) v',[id(15),id(2)])).rows[0].v.source_site_id===id(31),'legacy accepted pair preserved');
const targets=(await db.query('select private.site_payment_agreement_targets($1) v',[id(2)])).rows[0].v;
assert(targets.length===1&&targets[0].shared_item_id===id(15),'legacy targets preserved and owned accepted excluded');

await db.exec(`insert into private.document_receive_codes(code,company_id) values('${id(50)}','${id(4)}')`);
const packet={request_id:id(51),code:id(50),items:[{kind:'received_data',id:id(11)},{kind:'received_data',id:id(13)}]};
await deny(()=>db.query("select private.company_document_exchange('send',$1::jsonb)",[JSON.stringify(packet)]),'22023');
assert((await db.query('select used_at from private.document_receive_codes where code=$1',[id(50)])).rows[0].used_at===null,'mixed forward code untouched');
assert((await db.query('select count(*)::int n from private.document_deliveries')).rows[0].n===1,'mixed forward delivery absent');
packet.items=[{kind:'received_data',id:id(11)},{kind:'received_data',id:id(12)},{kind:'received',id:id(14)}];
await db.query("select private.company_document_exchange('send',$1::jsonb)",[JSON.stringify(packet)]);
assert((await db.query('select count(*)::int n from private.company_data_delivery_items where delivery_id=$1',[id(51)])).rows[0].n===2,'old structured retransfers preserved');
assert((await db.query('select path from private.document_delivery_items where delivery_id=$1',[id(51)])).rows[0].path==='preserved','old file attachment retransfer preserved');
console.log(JSON.stringify({checks,production_changed:false,synthetic_surrounding_schema:true,actual_catalog_consumer_definitions:true,actual_private_payment_callers:10,payment_caller_rows_preserved:true,native_lock_wait_checked:native,real_auth:false,full_production_schema:false,native}));
}finally{await db.close();}
