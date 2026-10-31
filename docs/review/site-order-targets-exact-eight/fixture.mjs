import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {verifyHttp} from './http.mjs';
export async function verifyTargetsOnEight(db,{q,check,sourceContract}){
 const targetRoot=process.env.SKO_TARGET_SOURCE_ROOT,authRoot=process.env.SKO_ACTUAL_AUTH_SOURCE_ROOT;
 if(!targetRoot||!authRoot||!path.isAbsolute(targetRoot)||!path.isAbsolute(authRoot))throw Error('pinned target and Auth source roots required');
 for(const [file,sha]of Object.entries({'docs/review/site-order-outgoing/registered-targets.sql.review-only':'2ffdbde112c9a83c5327321d7a8ffdbbc9d95733ee35823522d94b5f43e61883','supabase/functions/site-order-workflow/outgoing-handler.mjs':'b2d3b79c142855d4c0950d9e19e15ac09b6a88cef8465d3116610ee0c75adeaf','supabase/functions/site-order-workflow/auth.mjs':'b71378004e878b785836acf6fdc9f616b875e36602d506e91cd1c8b0a4a1f6a8'}))assert.equal(createHash('sha256').update(await fs.readFile(path.join(targetRoot,file))).digest('hex'),sha);
 const authSource=await fs.readFile(path.join(authRoot,'docs/review/atomic-document-evidence/actual-generic-helper-fixture.sql'),'utf8');
 assert.equal(createHash('sha256').update(authSource).digest('hex'),'06a08a6b0d66269780045e8bb5740c9358e8afd5b630cc23a532db8b6d87e594');
 const contractSource=await fs.readFile(path.join(authRoot,'docs/review/atomic-document-evidence/helper-contracts.json'),'utf8');
 assert.equal(createHash('sha256').update(contractSource).digest('hex'),'e8bf4bb4c665078f7f41ceef5a4fb6fe7a044dec67ad73a794b3c923cd810aa2');
 const contracts=JSON.parse(contractSource).filter(c=>['auth.uid()','auth.jwt()'].includes(c.signature));
 check(contracts.length,2);
 // Only these two already-public bodies are extracted. The three private helpers
 // in the same source file are deliberately not executed.
 const end=authSource.indexOf('CREATE OR REPLACE FUNCTION private.account_access_allowed()');
 if(end<0)throw Error('fixed Auth extraction boundary changed');
 const catalog=()=>q(`select jsonb_agg(to_jsonb(p)order by p.oid) v from pg_proc p where p.oid=any($1::regprocedure[])`,[[...sourceContract.functions.map(f=>f.signature),'private.require_standalone_trade_document_access()']]);
 const before=await catalog();
 await db.exec(authSource.slice(0,end));
 for(const c of contracts){
  check(await q('select md5(prosrc) v from pg_proc where oid=to_regprocedure($1)',[c.signature]),c.body_md5);
  await db.exec(`alter function ${c.signature} owner to supabase_auth_admin;revoke all on function ${c.signature} from public,postgres,supabase_auth_admin,dashboard_user,anon,authenticated,service_role;set role supabase_auth_admin`);
  try{for(const a of c.acl){if(!/^(PUBLIC|postgres|supabase_auth_admin|dashboard_user|anon|authenticated|service_role)$/.test(a.grantee)||a.grantor!=='supabase_auth_admin'||a.privilege!=='EXECUTE'||a.grant_option)throw Error('unexpected Auth ACL');await db.exec(`grant execute on function ${c.signature} to ${a.grantee}`);}}
  finally{await db.exec('reset role');}
  const actual=await q(`select jsonb_build_object('owner',pg_get_userbyid(p.proowner),'security_definer',p.prosecdef,'config',p.proconfig,'acl',(select jsonb_agg(jsonb_build_object('grantee',case when a.grantee=0 then 'PUBLIC' else pg_get_userbyid(a.grantee)end,'grantor',pg_get_userbyid(a.grantor),'privilege',a.privilege_type,'grant_option',a.is_grantable))from aclexplode(p.proacl)a))v from pg_proc p where oid=to_regprocedure($1)`,[c.signature]);
  const expected={owner:c.owner,security_definer:c.security_definer,config:c.config,acl:c.acl};
  for(const entry of [actual,expected])entry.acl.sort((a,b)=>a.grantee.localeCompare(b.grantee));check(actual,expected);
 }
 check(await catalog(),before);
 // The frozen fourteen modules intentionally omit this later namespace.
 // Prepare only the exact private owner-only namespace, no outgoing write API.
 await db.exec('create schema site_order_outgoing_private authorization postgres;revoke all on schema site_order_outgoing_private from public,anon,authenticated,service_role');
 await db.exec(await fs.readFile(path.join(targetRoot,'docs/review/site-order-outgoing/registered-targets.sql.review-only'),'utf8'));
 check(await catalog(),before);
 const id=n=>'90000000-0000-4000-8000-'+n.toString(16).padStart(12,'0');
 const A=id(1),B=id(2),UA=id(3),UB=id(4),sid=id(5),sidB=id(6),site=id(7),otherSite=id(8);
 await db.query('insert into auth.users(id)values($1),($2)',[UA,UB]);
 await db.query('insert into auth.sessions(id,user_id)values($1,$2),($3,$4)',[sid,UA,sidB,UB]);
 await db.query("insert into public.companies(id,name)values($1,'Target issuer'),($2,'Target recipient')",[A,B]);
 await db.query("insert into public.company_members(company_id,user_id,role)values($1,$2,'manager'),($3,$4,'manager')",[A,UA,B,UB]);
 await db.query("insert into public.sites(id,company_id,name)values($1,$2,'Own site'),($3,$4,'Foreign site')",[site,A,otherSite,B]);
 await db.query("insert into private.company_connections(parent_company_id,child_company_id,status,requested_by)values($1,$2,'accepted',$3)",[A,B,UA]);
 for(let n=0;n<53;n++)await db.query("insert into public.trade_companies(id,company_id,name,trade_role,linked_company_id,link_status)values($1,$2,'Target recipient','subcontractor',$3,'linked')",[id(100+n),A,B]);
 const previousFeature=await q("select enabled v from private.master_feature_settings where feature_key='site_order_documents'");
 await db.query("insert into private.master_feature_settings(feature_key,enabled)values('site_order_documents',true)on conflict(feature_key)do update set enabled=true");
 const saved=await q("select jsonb_build_object('claims',current_setting('request.jwt.claims',true),'sub',current_setting('request.jwt.claim.sub',true),'claim',current_setting('request.jwt.claim',true)) v");
 const actor=async(uid,session)=>{await db.query("select set_config('request.jwt.claim.sub','',false),set_config('request.jwt.claim','',false),set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:uid,session_id:session,role:'authenticated',is_anonymous:false})]);};
 const list=(s=site,before=null)=>q('select site_order_outgoing_private.registered_targets($1,$2,50) v',[s,before]);
 const deny=async(fn,pattern)=>{let error;try{await fn();}catch(e){error=e;}if(!error||!pattern.test(error.message))throw Error('expected '+pattern+', got '+error?.message);check(true,true);};
 try{
  await actor(UA,sid);const first=await list(),second=await list(site,first.next_cursor);
  check(first.entries.length,50);check(second.entries.length,3);check(first.actor_id,UA);check(first.company_id,A);check(first.session_id,sid);
  for(const e of [...first.entries,...second.entries])check(Object.keys(e).sort(),['id','name']);
  await deny(()=>list(otherSite),/own_site_required/);
  for(const role of ['authenticated','anon','service_role']){await db.exec('set role '+role);try{await deny(()=>list(),/permission denied/);}finally{await db.exec('reset role');}}
  await db.query("update private.master_feature_settings set enabled=false where feature_key='site_order_documents'");await deny(()=>list(),/master_feature_disabled/);
  await db.query("update private.master_feature_settings set enabled=true where feature_key='site_order_documents'");
  await db.query('update auth.sessions set not_after=now()-interval \'1 second\' where id=$1',[sid]);await deny(()=>list(),/^reauthentication_required$/);
  await db.query('update auth.sessions set not_after=null where id=$1',[sid]);
  await db.query("update public.trade_companies set name='changed' where id=$1",[id(100)]);await deny(()=>list(),/source_changed/);
  await db.query("update public.trade_companies set name='Target recipient' where id=$1",[id(100)]);
  const pages=await verifyHttp(db,{q,check,targetRoot,UA,UB,site});check(pages,[first,second]);
  check(await catalog(),before);
  if(process.env.SKO_TARGET_FIXTURE_RECEIPT_PATH){await fs.mkdir(path.dirname(process.env.SKO_TARGET_FIXTURE_RECEIPT_PATH),{recursive:true});await fs.writeFile(process.env.SKO_TARGET_FIXTURE_RECEIPT_PATH,JSON.stringify({actor:UA,company:A,site,session:sid,pages}));}
  console.log(JSON.stringify({targets_on_exact_eight:true,exact_eight_and_c_unchanged:true,actual_uid_jwt_bodies:2,no_private_auth_overwrite:true,synthetic_identity_and_rows:true,production_changed:false}));
 }finally{
  if(previousFeature===undefined)await db.query("delete from private.master_feature_settings where feature_key='site_order_documents'");
  else await db.query("update private.master_feature_settings set enabled=$1 where feature_key='site_order_documents'",[previousFeature]);
  await db.query("select set_config('request.jwt.claims',$1,false),set_config('request.jwt.claim.sub',$2,false),set_config('request.jwt.claim',$3,false)",[saved.claims??'',saved.sub??'',saved.claim??'']);
 }
}
