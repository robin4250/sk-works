import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {verifyTargetHttpSql} from './site_order_registered_targets_http_fixture.mjs';

export async function verifyRegisteredTargets(db,{id,A,B,UA,UB,actor,q,openNativePeer}) {
 let checks=0;const check=(a,b)=>{assert.deepEqual(a,b);checks++;};
 const deny=async(fn,p)=>{let error;try{await fn();}catch(e){error=e;}if(!error||!p.test(error.message))throw Error('expected '+p+' got '+error?.message);checks++;};
 const signed=async uid=>{await actor(uid);const sid=await q('select id v from auth.sessions where user_id=$1 order by id limit 1',[uid]);
  await db.query("select set_config('test.jwt',$1,false)",[JSON.stringify({sub:uid,role:'authenticated',session_id:sid})]);return sid;};
 const original=()=>q(`select jsonb_agg(to_jsonb(p)order by p.oid) v from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname in('site_order_outgoing_private','site_order_manager_private','site_order_package_private','trade_document_consent_private')
   and p.proname<>'registered_targets'`);
 const before=await original(),site=id(9301),trade=id(2100),sql=await fs.readFile('docs/review/site-order-outgoing/registered-targets.sql.review-only','utf8');
 await db.exec('create role outgoing_targets_untrusted');
 await db.exec('begin');
 try {
  await db.exec('alter default privileges in schema site_order_outgoing_private grant execute on functions to outgoing_targets_untrusted');
  await deny(()=>db.exec(sql),/registered_targets_acl_changed/);
 } finally {await db.exec('rollback');}
 check(await q("select to_regprocedure('site_order_outgoing_private.registered_targets(uuid,uuid,integer)') is null v"),true);
 check(await original(),before);
 await db.exec(sql);check(await original(),before);
 const sid=await signed(UA);
 // Old synthetic directory rows predate the later optional-name fixture column.
 // Materialize their registered formal names; the actual captured table has a
 // NOT NULL name. This is fixture setup, never candidate/business SQL.
 await db.query("update public.trade_companies t set name=c.name from public.companies c where c.id=t.linked_company_id and t.name is null");
 const list=(s=site,cursor=null,limit=50)=>q('select site_order_outgoing_private.registered_targets($1,$2,$3) v',[s,cursor,limit]);
 const first=await list();check(first.actor_id,UA);check(first.session_id,sid);check(first.company_id,A);
 check(first.entries.some(e=>e.id===trade),true);check(first.read_only,true);check(first.can_send,false);
 for(let n=0;n<52;n++) {
  await db.query("insert into public.trade_companies select (jsonb_populate_record(null::public.trade_companies,to_jsonb(t)||jsonb_build_object('id',$1::uuid))).* from public.trade_companies t where id=$2",[id(280000+n),trade]);
 }
 const clone=async(n,patch)=>db.query("insert into public.trade_companies select (jsonb_populate_record(null::public.trade_companies,to_jsonb(t)||$1::jsonb||jsonb_build_object('id',$2::uuid))).* from public.trade_companies t where id=$3",[JSON.stringify(patch),id(n),trade]);
 await clone(281000,{trade_role:'customer'});await clone(281001,{link_status:'local'});
 await clone(281002,{linked_company_id:null});await clone(281003,{company_id:B});await clone(281004,{name:'not formal registered name',trade_role:'customer'});
 const directory=await q('select jsonb_agg(to_jsonb(t)order by id) v from public.trade_companies t');
 const financial=await q(`select jsonb_build_object('invoices',(select jsonb_agg(to_jsonb(i)order by id)from public.invoices i),
  'payments',(select jsonb_agg(to_jsonb(p)order by id)from public.payment_certificates p),
  'documents',(select jsonb_agg(to_jsonb(d)order by id)from trade_document_consent_private.documents d)) v`);
 const page1=await list(),page2=await list(site,page1.next_cursor);
 check(page1.entries.length,50);check(page1.has_more,true);check(page1.next_cursor,page1.entries.at(-1).id);
 check(page2.entries.length,first.entries.length+52-50);check(page2.has_more,false);check(page2.next_cursor,null);
 const ids=[...page1.entries,...page2.entries].map(e=>e.id);check(new Set(ids).size,first.entries.length+52);
 check(ids.includes(trade),true);check(ids.some(x=>[281000,281001,281002,281003,281004].map(id).includes(x)),false);
 for(const entry of [...page1.entries,...page2.entries])check(Object.keys(entry).sort(),['id','name']);
 check(await q('select jsonb_agg(to_jsonb(t)order by id) v from public.trade_companies t'),directory);
 check(await q(`select jsonb_build_object('invoices',(select jsonb_agg(to_jsonb(i)order by id)from public.invoices i),
  'payments',(select jsonb_agg(to_jsonb(p)order by id)from public.payment_certificates p),
  'documents',(select jsonb_agg(to_jsonb(d)order by id)from trade_document_consent_private.documents d)) v`),financial);
 await deny(()=>list(id(9302)),/own_site_required/);await deny(()=>list(site,null,0),/own_site_required/);
 await db.exec('begin');
 try {
  await db.query("update public.trade_companies set name='changed unverified name' where id=$1",[trade]);
  await deny(()=>list(),/registered_targets_source_changed/);
 } finally {await db.exec('rollback');}
 await db.exec('begin');
 try {
  await db.query("insert into private.company_connections select (jsonb_populate_record(null::private.company_connections,to_jsonb(c)||jsonb_build_object('id',$1::uuid,'parent_company_id',$2::uuid,'child_company_id',$3::uuid))).* from private.company_connections c where c.parent_company_id=$3 and c.child_company_id=$2 limit 1",[id(281010),B,A]);
  await deny(()=>list(),/registered_targets_connection_ambiguous/);
 } finally {await db.exec('rollback');}
 await db.query("update private.master_feature_settings set enabled=false where feature_key='site_order_documents'");
 await deny(()=>list(),/master_feature_disabled/);
 await db.query("update private.master_feature_settings set enabled=true where feature_key='site_order_documents'");
 await db.query("update company_members set role='worker' where user_id=$1",[UA]);await deny(()=>list(),/management_required/);
 await db.query("update company_members set role='manager' where user_id=$1",[UA]);
 await db.query('delete from auth.sessions where id=$1',[sid]);await deny(()=>list(),/session/);
 await db.query('insert into auth.sessions(id,user_id)values($1,$2)',[sid,UA]);
 await db.query("update private.company_connections set status='disabled'");check((await list()).entries.length,0);
 await db.query("update private.company_connections set status='accepted'");
 await signed(UB);await deny(()=>list(),/own_site_required/);await signed(UA);
 for(const role of ['authenticated','anon','service_role']) {
  await db.exec('set role '+role);await deny(()=>list(),/permission denied/);await db.exec('reset role');
 }
 const httpPages=await verifyTargetHttpSql(db,{UA,UB,q,check,site,openNativePeer});
 check(httpPages,[page1,page2]);
 check(await original(),before);
 if(process.env.SKO_TARGET_FIXTURE_RECEIPT_PATH) {
  await fs.mkdir(new URL('../build/',import.meta.url),{recursive:true});
  await fs.writeFile(process.env.SKO_TARGET_FIXTURE_RECEIPT_PATH,JSON.stringify({actor:UA,company:A,site,session:sid,pages:httpPages}));
 }
 console.log(JSON.stringify({registered_target_checks:checks,source_tables_unchanged_by_reader:true,
  original_functions_unchanged:true,synthetic_auth:true,production_changed:false}));
}
