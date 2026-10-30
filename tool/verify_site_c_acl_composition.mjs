// Actual unchanged C SQL + standalone private consent/actor + actual site
// adapter. Only the surrounding tables/Auth claims are disposable fixtures.
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const sha=b=>createHash('sha256').update(b).digest('hex');
const cRoot=process.env.SKO_TRADE_C_SOURCE_ROOT;
if(!cRoot||!path.isAbsolute(cRoot))throw Error('fixed_C_source_root_required');
const cSql=await fs.readFile(path.join(cRoot,'docs/review/trade-documents-hub/master-and-standalone-context.sql.review-only'),'utf8');
assert.equal(sha(cSql),'7796c2e7bcc7a9eca78f1b79ce8cfc87fcd978c1dc4a4ddb7a5a8ced17b597e5');
const cBase=await fs.readFile(path.join(cRoot,'docs/review/trade-documents-hub/base-fixture.sql'),'utf8');
const read=p=>fs.readFile(new URL('../'+p,import.meta.url),'utf8');
let db;
if(process.argv[3]==='postgres'){
 const pg=(await import(process.argv[2])).default,url=new URL(process.env.SKO_CONSENT_FIXTURE_URL??'');
 if(!['127.0.0.1','localhost'].includes(url.hostname)||url.pathname!=='/sko_document_consent_fixture')throw Error('disposable_loopback_required');
 const client=new pg.Client({connectionString:url.href});await client.connect();db={exec:s=>client.query(s),query:(...x)=>client.query(...x),close:()=>client.end()};
}else{const {PGlite}=await import(process.argv[2]);db=new PGlite();}
let checks=0;const check=(a,b)=>{assert.deepEqual(a,b);checks++;};
const q=async(s,a=[])=>(await db.query(s,a)).rows[0]?.v;
const normalized=()=>q(`select jsonb_agg(jsonb_build_array(pg_get_userbyid(a.grantor),pg_get_userbyid(a.grantee),a.privilege_type,a.is_grantable)
 order by pg_get_userbyid(a.grantee),a.privilege_type) v from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner)))a
 where p.oid='private.require_standalone_trade_document_access()'::regprocedure`);
const exactAcl=[['postgres','authenticated','EXECUTE',false],['postgres','postgres','EXECUTE',false]];
const denyInstall=async(candidate,pattern)=>{let error;try{await db.exec(candidate);}catch(e){error=e;}finally{await db.exec('rollback');}
 if(!error||!pattern.test(error.message))throw Error('expected installer rejection: '+error?.message);checks++;
 check(await q("select to_regnamespace('site_order_manager_private')::text v"),null);
};
try{
 await db.exec(cBase);
 // This is the actual observed default scope. Do not turn it into a global or
 // private-schema grant: those are separate negative controls below.
 await db.exec('alter default privileges for role postgres in schema public grant execute on functions to anon,authenticated,service_role');
 await db.exec(cSql);
 check(await normalized(),exactAcl);
 check(await q("select count(*)::int v from private.master_feature_settings where feature_key='site_order_documents' and enabled"),0);
 const captured=await q("select to_jsonb(p) v from pg_proc p where oid='private.require_standalone_trade_document_access()'::regprocedure");
 const connection=await read('supabase/migrations/20261001213349_add_company_connection_foundation.sql');
 await db.exec(connection.slice(0,connection.indexOf('create or replace function private.company_connection_targets')));
 await db.exec("create table public.sites(id uuid primary key,company_id uuid,name text);alter table public.trade_companies add column link_status text");
 // Verbatim private standalone consent source. Its financial parent helpers
 // still fail closed; the fixture's permissive parent replacements are absent.
 await db.exec(await read('docs/candidates/trade_document_bound_seal_consent_20261021.sql.review-only'));
 const api=await read('docs/candidates/trade_document_confirmation_api_20261022.sql.review-only');
 const actor=api.match(/create function trade_document_confirmation_api_private\.actor\(\)[\s\S]*?end \$\$;/)?.[0];
 if(!actor)throw Error('actor_source_anchor_changed');
 await db.exec('create schema trade_document_confirmation_api_private;revoke all on schema trade_document_confirmation_api_private from public,anon,authenticated,service_role');
 await db.exec(actor);
 await db.exec('revoke all on function trade_document_confirmation_api_private.actor() from public,anon,authenticated,service_role');
 check(await q("select count(*)::int v from pg_proc p where pronamespace='trade_document_confirmation_api_private'::regnamespace"),1);
 check(await q("select count(*)::int v from pg_proc p where pronamespace='public'::regnamespace and proname like '%trade_document_confirmation%'"),0);
 await db.exec(await read('docs/review/site-order-artifact-registration/private-register.sql.review-only'));
 const candidate=await read('docs/review/site-order-manager-purpose/adapter.sql.review-only');
 const exception=/\(case when e\.signature='private\.require_standalone_trade_document_access\(\)' then[\s\S]*?else has_function_privilege\('authenticated',p\.oid,'EXECUTE'\) end\)/;
 const old=candidate.replace(exception,"has_function_privilege('authenticated',p.oid,'EXECUTE')");
 assert.equal(sha(old),'2e6c0ab477dbb4b903a742006370d07a1f6fa540aae76b370a2326e666f956b1');
 await denyInstall(old,/site_manager_source_changed: private.require_standalone_trade_document_access/);
 await db.exec('create role fixture_unexpected_role');
 for(const statement of [
  'grant execute on function private.require_standalone_trade_document_access() to public',
  'grant execute on function private.require_standalone_trade_document_access() to anon',
  'grant execute on function private.require_standalone_trade_document_access() to service_role',
  'grant execute on function private.require_standalone_trade_document_access() to fixture_unexpected_role',
  'grant execute on function private.require_standalone_trade_document_access() to authenticated with grant option',
  'revoke execute on function private.require_standalone_trade_document_access() from authenticated',
 ]){
  await db.exec('begin;'+statement);let error;
  try{await db.exec(candidate.replace(/^([\s\S]*?)begin;/,'$1'));}catch(e){error=e;}finally{await db.exec('rollback');}
  if(!error||!/site_manager_source_changed/.test(error.message))throw Error('ACL drift not rejected: '+error?.message);checks++;
  check(await normalized(),exactAcl);
 }
 await db.exec(candidate);
 check(await normalized(),exactAcl);
 check(await q("select to_jsonb(p) v from pg_proc p where oid='private.require_standalone_trade_document_access()'::regprocedure"),captured);
 check(await q("select count(*)::int v from pg_proc p where pronamespace='site_order_manager_private'::regnamespace and has_function_privilege('authenticated',p.oid,'execute')"),0);
 check(await q("select md5(prosrc) v from pg_proc where oid='trade_document_consent_private.parent_binding(text,uuid,uuid,uuid)'::regprocedure"),'f7c4647d2e11b0160d5a15ef01eb382e');
 check(await q("select md5(prosrc) v from pg_proc where oid='trade_document_consent_private.linked_view_allowed(text,uuid,uuid,integer,uuid)'::regprocedure"),'9f038cd8f856dc2fad5b866160f26637');
 console.log(JSON.stringify({result:'PASS actual C plus site adapter ACL composition',checks,old_guard_red:true,limited_guard_green:true,
  actual_public_only_defaults:true,original_C_catalog_unchanged:true,no_financial_API_installed:true,
  raw_parent_helpers_not_replaced:true,synthetic_surrounding_tables_and_auth:true,production_changed:false}));
}finally{await db.close();}
