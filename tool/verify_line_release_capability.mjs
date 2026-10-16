import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
process.on('uncaughtException',e=>{console.error(e.message,e.code,e.where ?? '');process.exit(1);});
let earlyWrappers=[];
let originalGateDefinition;
let originalGateMetadata;
let originalWrapperMetadata;
const testflightLock=process.argv.includes('--testflight-lock');
const {PGlite} = await import(pathToFileURL(process.argv[2]).href);
const db = new PGlite();
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const scalar = async (s,p=[]) => (await db.query(s,p)).rows[0]?.v;
const actor = async n => { await db.exec('reset role'); await db.query("select set_config('test.uid',$1,false)",[id(n)]); };
const role = r => db.exec(`set role ${r}`);
try {
await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;
create schema auth;create schema private;create type app_role as enum('owner','admin','manager','employee','viewer');
create function auth.uid() returns uuid language sql stable as $$select coalesce(nullif(current_setting('test.uid',true),''),nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid$$;
create table auth.users(id uuid primary key);
create table companies(id uuid primary key,name text);
create table company_members(company_id uuid,user_id uuid,role app_role);
create table communication_groups(id uuid primary key,company_id uuid,name text,group_type text,participants_only boolean,archived_at timestamptz);
create table communication_group_members(group_id uuid,user_id uuid);
create table private.account_deletion_access_restrictions(user_id uuid);
create table private.master_admins(user_id uuid primary key,enabled boolean);
create table private.master_admin_audit_log(actor_user_id uuid,action text,details jsonb);
create table private.chat_reports(id uuid primary key default gen_random_uuid(),reporter_id uuid,message_id uuid,company_id uuid,sender_id uuid,sender_name text,body_snapshot text,reason text,created_at timestamptz default now(),status text default 'pending',reviewed_by uuid,reviewed_at timestamptz,unique(reporter_id,message_id));
create table private.chat_hidden_messages(message_id uuid primary key);
create table private.content_reviews(kind text,content_id uuid,company_id uuid,author_id uuid,review_required boolean);
create table chat_attachments(id uuid primary key,message_id uuid,original_filename text,storage_path text);
create table line_group_bindings(id uuid primary key default gen_random_uuid(),company_id uuid,communication_group_id uuid,line_group_id text unique,status text,display_name text,updated_at timestamptz);
create table private.line_joined_groups(id uuid primary key default gen_random_uuid(),line_group_id text,joined boolean,display_name text,observed_at timestamptz);
create table private.line_chat_source_links(group_id uuid,company_id uuid,directory_id uuid,linked_by uuid,unique(group_id,directory_id));
create table private.line_chat_group_origins(group_id uuid,company_id uuid,origin text);
create table line_binding_claims(id uuid primary key default gen_random_uuid(),company_id uuid,communication_group_id uuid,requested_by uuid,claim_code text,expires_at timestamptz,status text default 'pending',cancelled_at timestamptz);
create table line_binding_audit(binding_id uuid,company_id uuid,communication_group_id uuid,line_group_id text,action text,actor_user_id uuid,source text);
create table chat_messages(id uuid primary key default gen_random_uuid(),company_id uuid,communication_group_id uuid,sender_user_id uuid,origin text,body text,sender_display_name text,sent_at timestamptz default now());
create function private.account_access_allowed() returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and not exists(select 1 from private.account_deletion_access_restrictions where user_id=auth.uid())$$;
create function public.is_current_user_master_admin() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from private.master_admins where user_id=auth.uid() and enabled)$$;
create function private.can_access_communication_group(g uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.communication_group_members where group_id=g and user_id=auth.uid())$$;
create function private.can_edit_custom_chat_photo(g uuid) returns boolean language sql stable as $$select private.can_access_communication_group(g)$$;
create function private.has_company_role(c uuid,r app_role[]) returns boolean language sql stable as $$select exists(select 1 from public.company_members where company_id=c and user_id=auth.uid() and role=any(r))$$;
create function private.has_company_feature(c uuid,f text) returns boolean language sql stable as $$select exists(select 1 from public.company_members where company_id=c and user_id=auth.uid() and role in ('owner','admin'))$$;
create function public.can_manage_attendance_corrections(c uuid) returns boolean language sql stable as $$select private.has_company_feature(c,'attendance')$$;
create function private.content_reviewer(c uuid) returns boolean language sql stable as $$select private.has_company_feature(c,'review')$$;
create function private.chat_sender_visible(u uuid) returns boolean language sql stable as $$select true$$;
create function private.chat_message_visible(m uuid,u uuid) returns boolean language sql stable as $$select true$$;
grant usage on schema public,private,auth to authenticated,anon,service_role;
grant select,insert on chat_messages to authenticated,service_role;
grant select on line_group_bindings,line_binding_claims,line_binding_audit to authenticated;
alter table chat_messages enable row level security;
create policy baseline_read on chat_messages for select to authenticated using(private.can_access_communication_group(communication_group_id));
create policy baseline_insert on chat_messages for insert to authenticated with check(origin='sk_works' and sender_user_id=auth.uid() and private.can_access_communication_group(communication_group_id));
alter table line_group_bindings enable row level security;
create policy baseline_read on line_group_bindings for select to authenticated using(private.can_access_communication_group(communication_group_id));
alter table line_binding_claims enable row level security;alter table line_binding_audit enable row level security;
create policy baseline_read on line_binding_claims for select to authenticated using(true);
create policy baseline_read on line_binding_audit for select to authenticated using(true);
insert into auth.users select ('00000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid from generate_series(1,7) n;
insert into companies values('${id(10)}','Fixture A'),('${id(11)}','Fixture B');
insert into company_members values('${id(10)}','${id(1)}','owner'),('${id(10)}','${id(2)}','employee'),('${id(10)}','${id(3)}','admin'),('${id(10)}','${id(4)}','manager'),('${id(10)}','${id(5)}','viewer'),('${id(11)}','${id(6)}','owner');
insert into private.master_admins values('${id(1)}',true),('${id(7)}',false);
insert into communication_groups values('${id(20)}','${id(10)}','Linked','company',true,null),('${id(21)}','${id(11)}','Other company','company',true,null);
insert into communication_group_members select '${id(20)}',id from auth.users where id not in ('${id(6)}','${id(7)}');
insert into communication_group_members values('${id(21)}','${id(6)}');
insert into line_group_bindings(company_id,communication_group_id,line_group_id,status,display_name) values('${id(10)}','${id(20)}','fixture-line','active','Fixture LINE');
insert into private.line_joined_groups(line_group_id,joined,display_name,observed_at) values('fixture-line',true,'Fixture LINE',now());
insert into private.line_chat_source_links select '${id(20)}','${id(10)}',id,'${id(1)}' from private.line_joined_groups;
insert into chat_messages(company_id,communication_group_id,sender_user_id,origin,body) values('${id(10)}','${id(20)}',null,'line','Saved LINE'),('${id(10)}','${id(20)}','${id(2)}','sk_works','Saved SKO'),('${id(11)}','${id(21)}',null,'line','Other company LINE');
`);
await db.exec(readFileSync('supabase/migrations/20261013204634_line_chat_outbound.sql','utf8'));
await db.exec(readFileSync('supabase/migrations/20261014050537_line_sender_native_attribution.sql','utf8'));
await db.exec(readFileSync('tool/fixtures/line_release_before_functions.sql','utf8'));
await db.exec(`create function public.line_joined_group_workspace(p_target_group_id uuid default null,p_new_company_id uuid default null) returns jsonb language sql stable security invoker set search_path='' as $$select private.line_joined_group_workspace(p_target_group_id,p_new_company_id)$$;
create function public.line_shared_chat_groups() returns jsonb language sql stable security invoker set search_path='' as $$select private.line_shared_chat_groups()$$;`);
const retained = async () => (await db.query("select p.oid::regprocedure::text signature,p.proacl::text acl,p.proconfig,p.proowner::regrole::text owner from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('private','public') order by 1")).rows;
const beforeFns = await retained();
const authBody = await scalar("select md5(prosrc) v from pg_proc where oid='private.can_access_communication_group(uuid)'::regprocedure");
const history = await scalar("select md5(jsonb_agg(to_jsonb(m) order by id)::text) v from chat_messages m");
const lineId=await scalar("select id v from chat_messages where body='Saved LINE'");
const skoId=await scalar("select id v from chat_messages where body='Saved SKO'");
await db.exec(`insert into private.chat_reports(reporter_id,message_id,company_id,sender_name,body_snapshot,reason) values('${id(1)}','${lineId}','${id(10)}','Line author','LINE report snapshot','other'),('${id(1)}','${skoId}','${id(10)}','SKO author','SKO report snapshot','other'),('${id(1)}','${id(999)}','${id(10)}','Deleted author','Unknown deleted-source snapshot','other');
insert into private.content_reviews values('message','${lineId}','${id(10)}',null,true),('message','${skoId}','${id(10)}','${id(2)}',true);
insert into chat_attachments values('${id(998)}','${lineId}','LINE file','fixture-only-path');
insert into private.content_reviews values('attachment','${id(998)}','${id(10)}',null,true);`);
if(process.argv.includes('--drift')) {
 await db.exec(`create or replace function private.line_outbound_actor_allowed(p_actor uuid,p_group uuid,p_company uuid) returns boolean language sql stable security definer set search_path='' as $$select false$$`);
 await assert.rejects(db.exec(readFileSync('supabase/migrations/20261014123518_line_general_release_capability.sql','utf8')),/prerequisite changed/);
 await db.exec('rollback');
 assert.equal(await scalar("select to_regclass('private.line_general_release_settings')::text v"),null);
 console.log('Changed baseline aborts and rolls back the entire LINE release preparation migration.');
 process.exit(0);
}
await db.exec(readFileSync('supabase/migrations/20261014123518_line_general_release_capability.sql','utf8'));
const afterFns = await retained();for(const f of beforeFns) assert.deepEqual(afterFns.find(x=>x.signature===f.signature),f);
assert.equal(await scalar("select md5(prosrc) v from pg_proc where oid='private.can_access_communication_group(uuid)'::regprocedure"),authBody);
assert.equal(await scalar('select general_enabled v from private.line_general_release_settings'),true);
await actor(2);await role('authenticated');
assert.equal((await scalar('select public.line_release_capability() v')).available,true);
assert.equal(await scalar('select count(*)::int v from chat_messages'),2);
const message=(await db.query(`insert into chat_messages(company_id,communication_group_id,sender_user_id,origin,body,sender_display_name) values($1,$2,$3,'sk_works','Queued before OFF','Fixture') returning id`,[id(10),id(20),id(2)])).rows[0].id;
const ticket=(await scalar('select public.prepare_line_chat_dispatch($1) v',[message])).ticket;
if(testflightLock) {
 await role('postgres');
 const settingsBefore=(await db.query('select * from private.line_general_release_settings')).rows;
 const gateMetadata=await scalar("select jsonb_build_object('acl',proacl,'config',proconfig,'owner',proowner) v from pg_proc where oid='private.line_actor_release_allowed(uuid)'::regprocedure");
 originalGateDefinition=await scalar("select pg_get_functiondef('private.line_actor_release_allowed(uuid)'::regprocedure) v");
 originalGateMetadata=await scalar("select to_jsonb(x) v from (select proacl::text,proowner,prolang,prosrc,prosecdef,provolatile,proconfig,proargnames from pg_proc where oid='private.line_actor_release_allowed(uuid)'::regprocedure)x");
 await db.exec(readFileSync('docs/security/staged/line_testflight_master_only.sql.review-only','utf8'));
 await assert.rejects(db.exec(readFileSync('docs/security/staged/line_testflight_master_only.sql.review-only','utf8')),/LINE actor gate changed/,'Changed gate is never silently overwritten');
 await db.exec('rollback');
 assert.deepEqual((await db.query('select * from private.line_general_release_settings')).rows,settingsBefore,'Saved release state and audit metadata preserved');
 assert.deepEqual(await scalar("select jsonb_build_object('acl',proacl,'config',proconfig,'owner',proowner) v from pg_proc where oid='private.line_actor_release_allowed(uuid)'::regprocedure"),gateMetadata);
 earlyWrappers=JSON.parse(readFileSync('tool/fixtures/line_testflight_public_wrappers_20261016.json','utf8'));
 await db.exec('set check_function_bodies=off');
 for(const f of earlyWrappers) {
  await db.exec(f.definition);
  const signature=`public.${f.name}(${f.args.split(', ').map(a=>a.split(' ').slice(1).join(' ')).join(',')})`;
  await db.exec(`revoke all on function ${signature} from public,anon,authenticated,service_role;grant execute on function ${signature} to authenticated`);
  if(f.acl.includes('service_role='))await db.exec(`grant execute on function ${signature} to service_role`);
 }
 await db.exec('set check_function_bodies=on');
 const metadata=async()=> (await db.query("select proname,proacl::text,proowner,prosecdef,provolatile,proconfig,proargnames from pg_proc where pronamespace='public'::regnamespace order by oid")).rows;
 const metadataBefore=await metadata();
 originalWrapperMetadata=(await db.query("select proname,proacl::text,proowner,prolang,prosrc,prosecdef,provolatile,proconfig,proargnames from pg_proc where pronamespace='public'::regnamespace order by oid")).rows;
 await db.exec(readFileSync('docs/security/staged/line_testflight_early_rpc_gate.sql.review-only','utf8'));
 assert.deepEqual(await metadata(),metadataBefore,'Early guards retain ACL/owner/invoker/volatility/config/argument names');
 await assert.rejects(db.exec(readFileSync('docs/security/staged/line_testflight_early_rpc_gate.sql.review-only','utf8')),/LINE wrapper changed/);await db.exec('rollback');
 await role('authenticated');
 assert.equal((await scalar('select public.line_release_capability() v')).available,false,'Saved general_enabled=true cannot bypass TestFlight lock');
}
await actor(1);await role('authenticated');await scalar('select public.set_line_general_release_enabled(false) v');
for(const n of [2,3,4,5,6,7]) {
 await actor(n);await role('authenticated');
 assert.equal((await scalar('select public.line_release_capability() v')).available,false);
 assert.equal(await scalar("select count(*)::int v from chat_messages where origin='line'"),0);
 assert.deepEqual(await scalar('select public.line_shared_chat_groups() v'),[]);
 assert.deepEqual(await scalar('select public.line_joined_group_workspace() v'),[]);
 assert.equal(await scalar('select count(*)::int v from line_group_bindings'),0);
 await role('postgres');await assert.rejects(scalar("select private.line_import_access($1,'invoice') v",[id(20)]),/LINE is unavailable/);await role('authenticated');
 for(const query of ["select public.set_line_general_release_enabled(true)","select private.line_linked_talk($1,$2)","select private.line_import_access($1,'invoice')","select public.begin_line_group_claim($1)","select public.disable_line_group_binding($1)","select private.link_line_source_to_chat($1,$2)","select private.create_line_shared_chat_group($2,'Name','sko',$1)"]) {
  await assert.rejects(db.query(query,query.includes('$2')?[id(20),id(30)]:query.includes('$1')?[id(20)]:[]));
 }
}
if(testflightLock)for(const f of earlyWrappers) {
 await actor(2);await role('authenticated');
 const args=f.args.split(', ');
 await assert.rejects(db.query(`select public.${f.name}(${args.map((_,i)=>'$'+(i+1)).join(',')})`,args.map(()=>null)),e=>e.code==='42501',`Early SQL ${f.name}`);
}
await actor(2);await role('authenticated');
assert.equal(await scalar("select count(*)::int v from chat_messages where origin='sk_works'"),2,'Ordinary SKO history remains readable');
await actor(3);await role('authenticated');
const reports=await scalar('select private.chat_report_queue() v');
assert.deepEqual(reports.map(r=>r.body),['SKO report snapshot'],'LINE and unknown deleted-source snapshots stay hidden while OFF');
await assert.rejects(scalar("select private.report_chat_message($1,'other') v",[lineId]),/LINE is unavailable/);
const lineReport=await (async()=>{await role('postgres');const rid=await scalar('select id v from private.chat_reports where message_id=$1',[lineId]);await role('authenticated');return rid;})();
await assert.rejects(db.query('select private.review_chat_report($1,true)',[lineReport]),/LINE is unavailable/);
await role('postgres');assert.equal(await scalar("select private.content_review_payload('message',$1) v",[lineId]),null);assert.equal(await scalar("select private.content_review_payload('attachment',$1) v",[id(998)]),null);
assert.equal((await scalar("select private.content_review_payload('message',$1) v",[skoId])).text,'Saved SKO');
await role('authenticated');assert.ok(await scalar("select private.report_chat_message($1,'other') v",[skoId]));
await actor(2);await role('authenticated');
await assert.rejects(scalar('select public.prepare_line_chat_dispatch($1) v',[message]),testflightLock?e=>e.code==='42501':/access required/);
await role('service_role');await assert.rejects(scalar('select public.claim_line_chat_dispatch($1,$2) v',[ticket,id(2)]),/access required/);
await role('authenticated');
const skOnly=(await db.query(`insert into chat_messages(company_id,communication_group_id,sender_user_id,origin,body,sender_display_name) values($1,$2,$3,'sk_works','SKO only during OFF','Fixture') returning id`,[id(10),id(20),id(2)])).rows[0].id;
await role('postgres');assert.equal(await scalar('select count(*)::int v from private.line_chat_outbox where message_id=$1',[skOnly]),0);
await actor(1);await role('authenticated');
assert.equal((await scalar('select public.line_release_capability() v')).available,true);
assert.ok((await scalar('select private.chat_report_queue() v')).some(r=>r.body==='LINE report snapshot'));
await role('postgres');assert.equal((await scalar("select private.content_review_payload('message',$1) v",[lineId])).text,'Saved LINE');await role('authenticated');
assert.equal(await scalar("select count(*)::int v from chat_messages where origin='line'"),1,'Master retains only existing group access');
await role('postgres');await db.query('insert into private.account_deletion_access_restrictions values($1)',[id(1)]);await role('authenticated');
assert.equal((await scalar('select public.line_release_capability() v')).available,false,'Master exception never bypasses account restriction');
await assert.rejects(scalar('select public.set_line_general_release_enabled(true) v'),/Master access required/);
await role('postgres');await db.query('delete from private.account_deletion_access_restrictions where user_id=$1',[id(1)]);await role('authenticated');
await role('postgres');assert.equal((await scalar('select private.line_import_access($1,\'invoice\') v',[id(20)])).can_edit,true);await role('authenticated');
const directory=await scalar('select public.line_joined_group_workspace() v');assert.equal(directory.length,1);
const linked=await scalar('select private.line_linked_talk($1,$2) v',[id(20),directory[0].id]);assert.equal(linked.length,1);
await assert.rejects(scalar('select private.line_linked_talk($1,$2) v',[id(21),directory[0].id]),/access required/);
// Service-role webhook reception remains possible; no recipient sends or network calls occur.
await role('service_role');await db.query("insert into chat_messages(company_id,communication_group_id,origin,body) values($1,$2,'line','Received while OFF')",[id(10),id(20)]);
await actor(2);await role('authenticated');assert.equal(await scalar("select count(*)::int v from chat_messages where origin='line'"),0);
await actor(1);await role('authenticated');await scalar('select public.set_line_general_release_enabled(true) v');
await actor(2);await role('authenticated');assert.equal(await scalar("select count(*)::int v from chat_messages where origin='line'"),testflightLock?0:2);
if(testflightLock) {
 await assert.rejects(scalar('select public.prepare_line_chat_dispatch($1) v',[message]),testflightLock?e=>e.code==='42501':/access required/);
 await role('postgres');assert.equal(await scalar('select general_enabled v from private.line_general_release_settings'),true,'Master saved setting retained, distribution lock remains authoritative');
} else {
const resumed=(await scalar('select public.prepare_line_chat_dispatch($1) v',[message])).ticket;
await role('service_role');assert.equal((await scalar('select public.claim_line_chat_dispatch($1,$2) v',[resumed,id(2)])).state,'claimed');
}
await role('postgres');assert.equal(await scalar("select count(*)::int v from private.master_admin_audit_log where action='line_general_access_changed'"),2);
// Compare the original rows only: toggle/reception must not mutate them.
assert.equal(await scalar("select md5(jsonb_agg(to_jsonb(m) order by id)::text) v from chat_messages m where body in ('Saved LINE','Saved SKO','Other company LINE')"),history);
for(const r of ['anon','authenticated','service_role']) assert.equal(await scalar("select has_table_privilege($1,'private.line_general_release_settings','select') v",[r]),false);
for(const r of ['anon','service_role']) assert.equal(await scalar("select has_function_privilege($1,'public.line_release_capability()','execute') v",[r]),false);
for(const r of ['anon','authenticated','service_role']) assert.equal(await scalar("select has_function_privilege($1,'private.line_actor_release_allowed(uuid)','execute') v",[r]),false);
// Actual signed-JWT HTTP transport is exercised only against the disposable PG17 fixture.
if(testflightLock && process.env.SKO_LINE_RELEASE_POSTGREST_URL) {
 const base=new URL(process.env.SKO_LINE_RELEASE_POSTGREST_URL);
 if(base.protocol!=='http:' || base.hostname!=='127.0.0.1' || base.port!=='3000' || base.username || base.password || base.search || base.hash || base.pathname!=='/') throw Error('Exact disposable loopback HTTP fixture required');
 await role('postgres');await db.exec("notify pgrst,'reload schema'");
 const token=n=>{
  const enc=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
  const input=`${enc({alg:'HS256',typ:'JWT'})}.${enc({role:'authenticated',sub:id(n),exp:Math.floor(Date.now()/1000)+300})}`;
  return input+'.'+crypto.createHmac('sha256','synthetic-line-fixture-secret-at-least-32-characters').update(input).digest('base64url');
 };
 const http=async(n,path,body)=>fetch(new URL(path,base),{method:body===undefined?'GET':'POST',headers:{...(n===null?{}:{Authorization:`Bearer ${token(n)}`}),...(body===undefined?{}:{'Content-Type':'application/json'})},...(body===undefined?{}:{body:JSON.stringify(body)})});
 for(let n=0;n<40;n++){
  try {const r=await http(1,'/rpc/line_release_capability',{});if(r.ok)break;}catch{}
  if(n===39)throw Error('PostgREST fixture not ready');
  await new Promise(r=>setTimeout(r,250));
 }
 for(const n of [2,3,4,5,6,7]) {
  let r=await http(n,'/rpc/line_release_capability',{});assert.equal(r.status,200);assert.equal((await r.json()).available,false,`HTTP capability denied actor ${n}`);
  r=await http(n,"/chat_messages?origin=eq.line&select=id");assert.equal(r.status,200);assert.deepEqual(await r.json(),[],`Direct REST LINE denied actor ${n}`);
  r=await http(n,'/line_group_bindings?select=id');assert.equal(r.status,200);assert.deepEqual(await r.json(),[]);
  r=await http(n,'/rpc/begin_line_group_claim',{p_communication_group_id:id(20)});assert.equal(r.status,403);assert.equal((await r.json()).code,'42501',`RPC semantic denial actor ${n}`);
  for(const f of earlyWrappers) {
   const body=Object.fromEntries(f.args.split(', ').map(a=>[a.split(' ')[0],null]));
   r=await http(n,`/rpc/${f.name}`,body);assert.equal(r.status,403,`Early HTTP ${n}/${f.name}`);assert.equal((await r.json()).code,'42501',`No lookup/existence error before gate ${f.name}`);
  }
 }
 let r=await http(2,'/chat_messages?body=eq.Saved%20SKO&select=body');assert.equal(r.status,200);assert.deepEqual(await r.json(),[{body:'Saved SKO'}],'Ordinary SKO remains readable');
 r=await http(1,'/rpc/line_release_capability',{});assert.equal(r.status,200);assert.equal((await r.json()).available,true);
 r=await http(1,'/rpc/line_chat_sender_preferences',{p_group_id:id(20),p_mode:null,p_nickname:null});assert.equal(r.status,200);assert.equal((await r.json()).mode,'name','Master delegates to original private sender preferences');
 r=await http(1,`/chat_messages?origin=eq.line&communication_group_id=eq.${id(20)}&select=id`);assert.equal(r.status,200);assert.equal((await r.json()).length,2,'Master own group LINE retained');
 r=await http(1,`/chat_messages?origin=eq.line&communication_group_id=eq.${id(21)}&select=id`);assert.equal(r.status,200);assert.deepEqual(await r.json(),[],'Master exception does not grant foreign group');
 r=await http(null,'/chat_messages?select=id');assert.equal(r.status,401,'Anonymous direct REST denied');
 r=await http(null,'/rpc/line_release_capability',{});assert.equal(r.status,401,'Anonymous capability denied');
 console.log('PASS: real signed-JWT PostgREST general role capability/direct LINE/bindings/RPC403, master own scope, foreign/anonymous rejection and ordinary SKO preservation.');
}
if(testflightLock) {
 await role('postgres');
 const snapshot=async()=>{
  const result={};
  for(const table of ['private.line_general_release_settings','private.master_admins','public.company_members','public.communication_group_members','public.chat_messages','public.line_group_bindings','private.master_admin_audit_log'])result[table]=(await db.query(`select to_jsonb(t) row from ${table} t order by to_jsonb(t)::text`)).rows;
  return result;
 };
 const beforeRestore=await snapshot();
 await db.exec('set check_function_bodies=off');
 await db.exec(originalGateDefinition);
 for(const f of earlyWrappers)await db.exec(f.definition);
 await db.exec('set check_function_bodies=on');
 assert.deepEqual(await scalar("select to_jsonb(x) v from (select proacl::text,proowner,prolang,prosrc,prosecdef,provolatile,proconfig,proargnames from pg_proc where oid='private.line_actor_release_allowed(uuid)'::regprocedure)x"),originalGateMetadata,'Restored original actor definition and ACL/owner/config/language exactly');
 assert.deepEqual((await db.query("select proname,proacl::text,proowner,prolang,prosrc,prosecdef,provolatile,proconfig,proargnames from pg_proc where pronamespace='public'::regnamespace order by oid")).rows,originalWrapperMetadata,'Restored original wrappers exactly');
 assert.deepEqual(await snapshot(),beforeRestore,'Restore never changes synthetic saved settings/admins/roles/members/history/audit');
 await actor(2);await role('authenticated');assert.equal((await scalar('select public.line_release_capability() v')).available,true,'Old general=true restoration reopens general access: explicit emergency risk, not a production instruction');
 console.log('PASS: isolated exact-definition/owner/ACL/config/language restore; synthetic settings, master/admin and company/group memberships/history/audit unchanged. Restoring old general=true reopens access.');
}
await role('anon');await assert.rejects(scalar('select public.line_release_capability() v'));
console.log(testflightLock?'TestFlight master-only lock: retained saved settings, denied general roles despite setting=true, preserved master scope/SKO/history/ACL; optional signed-JWT HTTP fixture runs separately; Realtime not tested.':'LINE release real SQL: default-on, additive RLS, roles, direct reads, definer denial, queued claim recheck, webhook reception, master existing scope, SKO preservation, audit and ON recovery passed. Realtime delivery and external HTTP races require separate integration validation.');
} finally { await db.close(); }

