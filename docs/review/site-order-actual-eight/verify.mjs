// Disposable only. All eight existing bodies reconstructed from pinned public sources.
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const root=path.resolve(new URL('../../../',import.meta.url).pathname);
import {reconstruct} from './reconstruct.mjs';
const sourceContract=JSON.parse(await fs.readFile(new URL('./source-contract.json',import.meta.url),'utf8'));
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
let checks=0;const check=(a,b)=>{assert.deepEqual(a,b);checks++;};
const q=async(s,a=[])=>(await db.query(s,a)).rows[0]?.v;
const reject=async sql=>{let error;try{await db.exec(sql);}catch(e){error=e;}if(!error||error.code!=='42501')throw Error('expected 42501: '+error?.message);checks++;};
try{
 if(process.argv[3]==='postgres')check(await q("select current_setting('server_version_num') v"),'170006');
 await db.exec(await fs.readFile(path.join(cRoot,'docs/review/trade-documents-hub/base-fixture.sql'),'utf8'));
 await db.exec('alter table private.company_seal_png_versions add column company_name text');
 const exact=await reconstruct(read,sourceContract);
 for(const helper of exact.generic) await db.exec(helper.sql);
 await db.exec(exact.sealBase);
 await db.exec(exact.sealPatch);
 // Fixture roles and ACLs reproduce the public catalog contract, not live Auth.
 await db.exec('create role supabase_auth_admin;create role dashboard_user;grant usage on schema auth to supabase_auth_admin');
 const expectedBodies=new Map(exact.generic.map(f=>[f.signature,f.body]));
 expectedBodies.set('private.document_company_seal_snapshot(jsonb,uuid,boolean)',exact.sealBody);
 for(const f of sourceContract.functions){
  check(await q('select prosrc v from pg_proc where oid=to_regprocedure($1)',[f.signature]),expectedBodies.get(f.signature));
  if(!/^[a-z_]+\.[a-z_]+\([a-z,]*\)$/.test(f.signature))throw Error('unsafe contract signature');
  for(const role of [f.owner,...f.acl.flatMap(a=>[a.grantee,a.grantor])])if(!/^[A-Za-z_]+$/.test(role))throw Error('unsafe contract role');
  await db.exec(`alter function ${f.signature} owner to ${f.owner};revoke all on function ${f.signature} from public,anon,authenticated,service_role,postgres,supabase_auth_admin,dashboard_user;set role ${f.owner}`);
  try{for(const grant of f.acl){assert.equal(grant.grantor,f.owner);assert.equal(grant.privilege,'EXECUTE');assert.equal(grant.grant_option,false);await db.exec(`grant execute on function ${f.signature} to ${grant.grantee}`);}}
  finally{await db.exec('reset role');}
  const actual=await q(`select jsonb_build_object('source_md5',md5(p.prosrc),'security_definer',p.prosecdef,'volatility',p.provolatile,'config',p.proconfig,'owner',pg_get_userbyid(p.proowner),'acl',(select jsonb_agg(jsonb_build_object('grantee',case when a.grantee=0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end,'grantor',pg_get_userbyid(a.grantor),'privilege',a.privilege_type,'grant_option',a.is_grantable) order by case when a.grantee=0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end)from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner)))a)) v from pg_proc p where p.oid=to_regprocedure($1)`,[f.signature]);
  const expected={...f};delete expected.signature;expected.acl.sort((a,b)=>a.grantee.localeCompare(b.grantee,'en',{sensitivity:'variant'}));
  actual.acl.sort((a,b)=>a.grantee.localeCompare(b.grantee,'en',{sensitivity:'variant'}));check(actual,expected);
 }
 await db.exec('alter default privileges for role postgres in schema public grant execute on functions to anon,authenticated,service_role');
 await db.exec(cSql);
 const cBefore=await q("select jsonb_build_object('body',md5(prosrc),'acl',proacl::text,'config',proconfig) v from pg_proc where oid='private.require_standalone_trade_document_access()'::regprocedure");
 const connection=await read('supabase/migrations/20261001213349_add_company_connection_foundation.sql');
 await db.exec(connection.slice(0,connection.indexOf('create or replace function private.company_connection_targets')));
 await db.exec('create table public.sites(id uuid primary key,company_id uuid,name text);alter table public.trade_companies add column link_status text');
 const {composeFull}=await import('file://'+root+'/docs/review/site-order-private-baseline/full_composition.mjs');
 const fullReceipt=await composeFull(db,{read,q,check,manifest});
 if(process.env.SKO_CATALOG_RECEIPT_PATH)await fs.writeFile(process.env.SKO_CATALOG_RECEIPT_PATH,JSON.stringify(fullReceipt,null,2));
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
 await db.exec(`update auth.users set is_anonymous=false where id='${uid}';insert into private.company_seal_png_versions(id,company_id,company_name,png_bytes,sha256) values('44444444-4444-4444-8444-444444444444','${cid}','Fixture company',decode('010203','hex'),repeat('a',64));insert into private.company_seal_png_selection values('${cid}',true,'44444444-4444-4444-8444-444444444444')`);
 check(await q(`select private.document_company_seal_snapshot(null,'${cid}',true)->'company_seal_snapshot'->>'style' v`),'uploaded_png');
 check(await q(`select private.uploaded_company_seal_snapshot('${cid}')->'company_seal_snapshot'->>'name' v`),'Fixture company');
 check(await q(`select private.aoyagi_reisho_name_supported('株式会社') v`),true);
 await db.exec(`update public.companies set name='Changed fixture' where id='${cid}'`);
 let changed=false;try{await db.exec(`select private.document_company_seal_snapshot(null,'${cid}',true)`);}catch(e){changed=e.code==='40001';}check(changed,true);
 await db.exec(`update auth.users set is_anonymous=false where id='${uid}';insert into private.account_deletion_access_restrictions values('${uid}')`);
 await reject('select private.require_standalone_trade_document_access()');
 console.log(JSON.stringify({result:'PASS public-reconstructed exact-eight-body fourteen-module composition',full_modules:fullReceipt.modules_installed,atomic_faults:6,checks,actual_current_helper_bodies:8,seal_snapshot_synthetic:false,seal_bytes_and_company_rows_synthetic:true,private_capture_loaded:false,public_source_reconstruction:true,synthetic_auth_identity_and_rows:true,financial_api_installed:false,production_changed:false}));
}catch(error){console.error(JSON.stringify({error:error.message,code:error.code,where:error.where}));process.exitCode=1;}finally{await db.close();}
