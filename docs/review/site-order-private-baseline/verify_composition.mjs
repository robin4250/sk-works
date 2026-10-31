// Disposable only. Seven catalog-matching helpers; seal snapshot remains synthetic.
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const root=path.resolve(new URL('../../../',import.meta.url).pathname);
const read=p=>fs.readFile(path.join(root,p),'utf8');
const manifest=JSON.parse(await read('docs/review/site-order-private-baseline/manifest.json'));
const hash=(kind,s)=>createHash(kind).update(s).digest('hex');
const cRoot=process.env.SKO_TRADE_C_SOURCE_ROOT;
if(!cRoot||!path.isAbsolute(cRoot))throw Error('fixed_C_source_root_required');
const cSql=await fs.readFile(path.join(cRoot,'docs/review/trade-documents-hub/master-and-standalone-context.sql.review-only'),'utf8');
assert.equal(hash('sha256',cSql),'7796c2e7bcc7a9eca78f1b79ce8cfc87fcd978c1dc4a4ddb7a5a8ced17b597e5');
let db;
if(process.argv[3]==='postgres'){
 const pg=(await import(process.argv[2])).default,u=new URL(process.env.SKO_CONSENT_FIXTURE_URL??'');
 if(!['127.0.0.1','localhost'].includes(u.hostname)||u.pathname!=='/sko_document_consent_fixture')throw Error('disposable_loopback_required');
 const client=new pg.Client({connectionString:u.href});await client.connect();db={exec:s=>client.query(s),query:(...a)=>client.query(...a),close:()=>client.end()};
}else {const {PGlite}=await import(process.argv[2]);db=new PGlite();}
let nativeVersion=null;let checks=0;const check=(a,b)=>{assert.deepEqual(a,b);checks++;};
const q=async(s,a=[])=>(await db.query(s,a)).rows[0]?.v;
const reject=async sql=>{let error;try{await db.exec(sql);}catch(e){error=e;}if(!error||error.code!=='42501')throw Error('expected 42501: '+error?.message);checks++;};
const escape=s=>s.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
try{
 if(process.argv[3]==='postgres'){nativeVersion=await q("select current_setting('server_version_num') v");check(nativeVersion,'170006');}
 await db.exec(await fs.readFile(path.join(cRoot,'docs/review/trade-documents-hub/base-fixture.sql'),'utf8'));
 await db.exec('alter table private.company_seal_png_versions add column company_name text');
 for(const [sig,file] of Object.entries(manifest.public_fixture_actual_sources)){
  const source=await read(file),name=sig.split('(')[0];
  const re=new RegExp('create\\s+(?:or\\s+replace\\s+)?function\\s+'+escape(name)+'\\s*\\([\\s\\S]*?\\bas\\s+(\\$[\\w]*\\$)([\\s\\S]*?)\\1\\s*;','gi');
  const expected=manifest.existing_function_contracts.find(f=>f.signature===sig).source_md5;
  const matched=[...source.matchAll(re)].filter(m=>hash('md5',m[2])===expected);
  if(matched.length!==1)throw Error('exact_helper_source_required: '+sig);
  await db.exec(matched[0][0].replace(/^create function /i,'create or replace function '));
  check(await q('select md5(prosrc) v from pg_proc where oid=to_regprocedure($1)',[sig]),expected);
 }
 await db.exec("create function private.document_company_seal_snapshot(jsonb,uuid,boolean) returns jsonb language plpgsql set search_path='' as $$begin raise sqlstate '0A000' using message='fixture_seal_snapshot_not_connected';end$$");
 await db.exec('alter default privileges for role postgres in schema public grant execute on functions to anon,authenticated,service_role');
 await db.exec(cSql);
 const cBefore=await q("select jsonb_build_object('body',md5(prosrc),'acl',proacl::text,'config',proconfig) v from pg_proc where oid='private.require_standalone_trade_document_access()'::regprocedure");
 const connection=await read('supabase/migrations/20261001213349_add_company_connection_foundation.sql');
 await db.exec(connection.slice(0,connection.indexOf('create or replace function private.company_connection_targets')));
 await db.exec('create table public.sites(id uuid primary key,company_id uuid,name text);alter table public.trade_companies add column link_status text');
 let fullReceipt;
 if(process.argv.includes('--full')){
  const {composeFull}=await import('./full_composition.mjs');
  fullReceipt=await composeFull(db,{read,q,check,manifest});
  if(process.env.SKO_CATALOG_RECEIPT_PATH)await fs.writeFile(process.env.SKO_CATALOG_RECEIPT_PATH,JSON.stringify(fullReceipt,null,2));
 }else{
 await db.exec(await read('docs/candidates/trade_document_bound_seal_consent_20261021.sql.review-only'));
 const api=await read('docs/candidates/trade_document_confirmation_api_20261022.sql.review-only');
 const actor=api.match(/create function trade_document_confirmation_api_private\.actor\(\)[\s\S]*?end \$\$;/)?.[0];
 assert.equal(hash('sha256',actor),manifest.actor_statement_sha256);
 await db.exec('create schema trade_document_confirmation_api_private;revoke all on schema trade_document_confirmation_api_private from public,anon,authenticated,service_role;'+actor+'revoke all on function trade_document_confirmation_api_private.actor() from public,anon,authenticated,service_role');
 await db.exec(await read('docs/review/site-order-artifact-registration/private-register.sql.review-only'));
 await db.exec(await read('docs/review/site-order-manager-purpose/adapter.sql.review-only'));
 }
 check(await q("select jsonb_build_object('body',md5(prosrc),'acl',proacl::text,'config',proconfig) v from pg_proc where oid='private.require_standalone_trade_document_access()'::regprocedure"),cBefore);
 check(await q("select count(*)::int v from pg_proc where pronamespace='trade_document_confirmation_api_private'::regnamespace"),1);
 check(await q("select count(*)::int v from pg_proc where pronamespace='public'::regnamespace and proname like '%trade_document_confirmation%'"),0);
 check(await q("select md5(prosrc) v from pg_proc where oid='trade_document_consent_private.parent_binding(text,uuid,uuid,uuid)'::regprocedure"),'f7c4647d2e11b0160d5a15ef01eb382e');
 check(await q("select md5(prosrc) v from pg_proc where oid='trade_document_consent_private.linked_view_allowed(text,uuid,uuid,integer,uuid)'::regprocedure"),'9f038cd8f856dc2fad5b866160f26637');
 const uid='11111111-1111-4111-8111-111111111111',sid='22222222-2222-4222-8222-222222222222',cid='33333333-3333-4333-8333-333333333333';
 await db.exec(`insert into auth.users(id) values('${uid}');insert into auth.sessions(id,user_id) values('${sid}','${uid}');insert into public.companies(id,name) values('${cid}','Fixture company');insert into public.company_members values('${cid}','${uid}','manager')`);
 const claims={sub:uid,role:'authenticated',session_id:sid,is_anonymous:false};
 await q("select set_config('request.jwt.claims',$1,false) v",[JSON.stringify(claims)]);
 await q("select set_config('request.jwt.claim.sub',$1,false) v",[uid]);
 // OFF is a real denial before the disposable fixture explicitly enables it.
 await reject('select private.require_standalone_trade_document_access()');
 await db.exec("insert into private.master_feature_settings(feature_key,enabled) values('site_order_documents',true) on conflict(feature_key) do update set enabled=true");
 check(await q("select private.require_standalone_trade_document_access()->>'role' v"),'manager');
 await db.exec(`update auth.sessions set not_after=now()-interval '1 second' where id='${sid}'`);
 await reject('select private.require_standalone_trade_document_access()');
 await db.exec(`update auth.sessions set not_after=null where id='${sid}';update auth.users set banned_until=now()+interval '1 hour' where id='${uid}'`);
 await reject('select private.require_standalone_trade_document_access()');
 await db.exec(`update auth.users set banned_until=null,is_anonymous=true where id='${uid}'`);
 await reject('select private.require_standalone_trade_document_access()');
 await db.exec(`update auth.users set is_anonymous=false where id='${uid}';insert into private.account_deletion_access_restrictions values('${uid}')`);
 await reject('select private.require_standalone_trade_document_access()');
 console.log(JSON.stringify({result:'PASS minimal private site composition',checks,native_server_version_num:nativeVersion,actual_current_generic_helpers:7,seal_snapshot_synthetic:true,private_eight_body_result_separate:true,synthetic_auth_identity_and_rows:true,financial_api_installed:false,full_modules:fullReceipt?.modules_installed??0,atomic_faults:fullReceipt?.faults??0,production_changed:false}));
}catch(error){console.error(JSON.stringify({error:error.message,code:error.code,where:error.where}));process.exitCode=1;}finally{await db.close();}
