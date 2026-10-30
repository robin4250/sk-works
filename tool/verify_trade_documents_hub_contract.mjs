import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
const engine=process.argv[2]??'pglite';
let db;
if(engine==='pglite') {
  const {PGlite}=await import(pathToFileURL(process.env.SKO_PGLITE_MODULE??resolve('tool/security/fixture_dependencies/node_modules/@electric-sql/pglite/dist/index.js')));
  db=new PGlite();
} else if(engine==='postgres') {
  const url=new URL(process.env.SKO_TRADE_HUB_FIXTURE_URL??'');
  if(!['localhost','127.0.0.1'].includes(url.hostname)||url.pathname!=='/sko_trade_hub_fixture')throw new Error('Dedicated localhost fixture required');
  const module=await import(pathToFileURL(process.env.SKO_PG_MODULE??resolve('tool/security/fixture_dependencies/node_modules/pg/lib/index.js')));
  const Client=module.Client??module.default.Client;
  const client=new Client({connectionString:url.toString()});await client.connect();
  db={exec:q=>client.query(q),query:q=>client.query(q),close:()=>client.end()};
} else {throw new Error('Unknown fixture engine');}
let checks=0;
const assert=(ok,message)=>{if(!ok)throw new Error(message);checks++;};
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const query=async sql=>{
 const scoped=/^select public\./.test(sql);
 if(scoped)await db.exec('set local role authenticated');
 try{return (await db.query(sql)).rows;}finally{if(scoped)await db.exec('reset role');}
};
async function actor(n,s=200+n) {
  await db.exec(`select set_config('request.jwt.claim.sub','${id(n)}',false),set_config('request.jwt.claims','{"sub":"${id(n)}","role":"authenticated","session_id":"${id(s)}","is_anonymous":false}',false)`);
}
async function denied(sql,code='42501') {
  await db.exec('savepoint denied');let error;
  await db.exec('set local role authenticated');
  try{await db.exec(sql);}catch(e){error=e;}
  await db.exec('rollback to savepoint denied;release savepoint denied;reset role');
  assert(error?.code===code,`expected ${code}, got ${error?.code}: ${sql}`);
}
try {
  await db.exec(readFileSync('docs/review/trade-documents-hub/base-fixture.sql','utf8'));
  const recoveryTargets = "n.nspname='public' and p.proname in ('current_master_feature_flags','set_master_feature_enabled_with_proof')";
  const originalPublic = (await db.query(`select p.oid,to_jsonb(p)-'prosrc' attrs,p.prosrc,pg_get_functiondef(p.oid) definition from pg_proc p join pg_namespace n on n.oid=p.pronamespace where ${recoveryTargets} order by p.oid`)).rows;
  assert(originalPublic.length===2,'capture exactly the two original public functions');
  const candidate=readFileSync('docs/review/trade-documents-hub/master-and-standalone-context.sql.review-only','utf8');
  for(const drift of ['grant update on private.master_feature_settings to authenticated','alter table private.master_feature_settings disable row level security']) {
    await db.exec(drift);let blocked;
    try{await db.exec(candidate);}catch(error){blocked=error;}
    await db.exec('rollback');
    assert(blocked?.message==='master feature table security changed','preflight rejects unsafe master table grant/RLS drift');
    await db.exec('revoke update on private.master_feature_settings from authenticated;alter table private.master_feature_settings enable row level security');
  }
  await db.exec(candidate);
  const installedPublic = (await db.query(`select p.oid,to_jsonb(p)-'prosrc' attrs,p.prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace where ${recoveryTargets} order by p.oid`)).rows;
  assert(installedPublic.length===2,'capture exact installed recovery identity');
  const guardedRestore = async () => {
    await db.exec('begin');
    try {
      const observed=(await db.query(`select p.oid,to_jsonb(p)-'prosrc' attrs,p.prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace where ${recoveryTargets} order by p.oid`)).rows;
      if(JSON.stringify(observed)!==JSON.stringify(installedPublic))throw new Error('Recovery identity changed; stop');
      for(const row of originalPublic)await db.exec(row.definition+';');
      await db.exec('commit');
    }catch(error){await db.exec('rollback');throw error;}
  };
  assert((await query("select relrowsecurity and not has_table_privilege('authenticated',oid,'INSERT,UPDATE,DELETE,TRUNCATE') safe from pg_class where oid='private.master_feature_settings'::regclass"))[0].safe,'master table RLS and client no-DML preserved');
  await db.exec('begin');
  await db.exec(`insert into auth.users(id) values('${id(1)}'),('${id(2)}'),('${id(3)}');
   insert into auth.sessions values('${id(201)}','${id(1)}',null),('${id(202)}','${id(2)}',null),('${id(203)}','${id(3)}',null);
   insert into private.master_admins values('${id(3)}',true);
   insert into public.company_members values('${id(101)}','${id(1)}','manager'),('${id(101)}','${id(2)}','employee');
   insert into public.companies(id,name,address,corporate_number,phone,fax,company_seal_style,company_seal_enabled) values('${id(101)}','すみだ建設株式会社','自社住所','123','03-1','03-2','legacy',true),('${id(102)}','別会社','別住所','456','03-3','03-4','legacy',true);
   insert into private.partner_company_profile_extensions values('${id(101)}','齊藤竜一');
   insert into public.trade_companies values('${id(301)}','${id(101)}','登録会社','相手住所','789','相手代表','03-5','both','${id(102)}',null),('${id(302)}','${id(102)}','別の登録会社','秘密住所','999','別代表','秘密電話','both',null,null);
   insert into private.trade_document_templates values('${id(101)}','payment_certificate','{"work_name":"設定工事","notes":"設定備考"}'),('${id(101)}','invoice','{"acceptance_text":"承諾文"}');`);
  await actor(1);
  let flags=(await query('select public.current_master_feature_flags() v'))[0].v;
  assert(flags.site_order_documents===false,'missing flag must default OFF');
  assert(flags.vehicle_management===true&&flags.route_assignment===true,'old absent-row contracts retained');
  assert(flags.trade_documents_master_contract_version===1&&flags.standalone_trade_documents_contract_version===1,'independent capability versions');
  await denied('select public.standalone_trade_document_access()');
  await denied(`select public.standalone_trade_document_registration_context('${id(301)}',false)`);
  await denied(`select public.set_master_feature_enabled_with_proof('site_order_documents',true,'${'a'.repeat(64)}')`);
  await actor(3);
  await db.exec("select set_config('fixture.reauth_required','false',true)");
  await denied("select public.set_master_feature_enabled('site_order_documents',true)",'P0001');
  await db.exec("select set_config('fixture.reauth_required','true',true)");
  await denied(`select public.set_master_feature_enabled_with_proof('site_order_documents',true,null)`);
  await db.exec(`insert into private.reauthentication_proofs values(encode(sha256(convert_to('${'a'.repeat(64)}','UTF8')),'hex'),'${id(3)}','${id(203)}','master.feature.set','{"feature_key":"site_order_documents","enabled":true}',null,null,now()+interval '5 minutes')`);
  flags=(await query(`select public.set_master_feature_enabled_with_proof('site_order_documents',true,'${'a'.repeat(64)}') v`))[0].v;
  assert(flags.site_order_documents===true,'master proof-bound ON');
  await denied(`select public.set_master_feature_enabled_with_proof('site_order_documents',true,'${'a'.repeat(64)}')`);
  await actor(1);
  const access=(await query('select public.standalone_trade_document_access() v'))[0].v;
  assert(access.role==='manager'&&access.company_id===id(101)&&access.actor_id===id(1)&&access.session_id===id(201),'manager access tied to actual sole company/session');
  for(const role of ['owner','admin']) {
    await db.exec(`update public.company_members set role='${role}' where user_id='${id(1)}'`);
    assert((await query('select public.standalone_trade_document_access() v'))[0].v.role===role,'owner/admin keep scoped access');
  }
  await db.exec(`update public.company_members set role='manager' where user_id='${id(1)}'`);
  let context=(await query(`select public.standalone_trade_document_registration_context('${id(301)}',false) v`))[0].v;
  assert(context.issuer.name==='すみだ建設株式会社'&&context.issuer.fax==='03-2'&&context.issuer.representative_name==='齊藤竜一','self company/representative/contacts');
  assert(context.counterparty.name==='登録会社'&&context.counterparty.address==='相手住所','exact registered target');
  assert(context.company_seal_snapshot.company_id===id(101)&&context.company_seal_enabled===true,'self seal identity');
  assert(context.bank_backend_available===false&&!('counterparty_bank' in context),'missing bank backend explicit, no fabricated bank');
  assert(!JSON.stringify(context).includes('秘密'),'no foreign contact leakage');
  context=(await query(`select public.standalone_trade_document_registration_context('${id(301)}',true) v`))[0].v;
  assert(context.acceptance===true&&context.template.work_name==='設定工事'&&context.template.acceptance_text==='承諾文','acceptance uses configured template inheritance');
  await denied(`select public.standalone_trade_document_registration_context('${id(302)}',false)`);
  await db.exec(`update public.trade_companies set linked_company_id='${id(101)}' where id='${id(301)}'`);
  await denied(`select public.standalone_trade_document_registration_context('${id(301)}',false)`);
  await db.exec(`update public.trade_companies set linked_company_id='${id(102)}' where id='${id(301)}';update public.companies set company_seal_enabled=false where id='${id(101)}'`);
  await denied(`select public.standalone_trade_document_registration_context('${id(301)}',false)`);
  await db.exec(`update public.companies set company_seal_enabled=true where id='${id(101)}'`);
  await denied(`select public.standalone_trade_document_registration_context(null,false)`,'22023');
  await db.exec(`update public.trade_companies set trade_role='customer' where id='${id(301)}'`);
  await denied(`select public.standalone_trade_document_registration_context('${id(301)}',false)`);
  await db.exec(`update public.trade_companies set trade_role='both' where id='${id(301)}'`);
  // The optional bank module is not installed in the captured production
  // catalog. This synthetic adapter exercises its acknowledgement boundary.
  await db.exec(`create function public.partner_company_bank_read(uuid,uuid) returns jsonb language sql as $$select current_setting('fixture.bank_receipt')::jsonb$$;
   update public.trade_companies set partner_company_id='${id(401)}' where id='${id(301)}'`);
  const bank={schema:1,company_id:id(101),partner_company_id:id(401),bank_version:2,
    bank_name:'銀行',branch_name:'支店',account_type:'普通',account_number:'1234567',account_holder:'カ）テスト'};
  const receipt={company_id:id(101),partner_company_id:id(401),available:true,version:2,bank};
  const setBank=async value=>db.exec(`select set_config('fixture.bank_receipt','${JSON.stringify(value)}',true)`);
  await setBank(receipt);
  context=(await query(`select public.standalone_trade_document_registration_context('${id(301)}',false) v`))[0].v;
  assert(context.bank_backend_available===true&&context.counterparty_bank.bank_version===2,'bank receipt exact bound version');
  for(const malformed of [{...receipt,version:3},{...receipt,available:false},{...receipt,extra:true},
    {...receipt,company_id:id(102)},{...receipt,partner_company_id:id(402)},
    {...receipt,version:2.5},{...receipt,bank:[]},{...receipt,bank:null}]){
    await setBank(malformed);await denied(`select public.standalone_trade_document_registration_context('${id(301)}',false)`);
  }
  await setBank({...receipt,available:false,version:0,bank:null});
  context=(await query(`select public.standalone_trade_document_registration_context('${id(301)}',false) v`))[0].v;
  assert(context.bank_backend_available===true&&!('counterparty_bank' in context),'available backend without account never fabricates bank');
  await db.exec(`update public.company_members set role=null where user_id='${id(1)}'`);
  await denied('select public.standalone_trade_document_access()');
  await db.exec(`update public.company_members set role='manager' where user_id='${id(1)}';update public.trade_companies set trade_role=null where id='${id(301)}'`);
  await denied(`select public.standalone_trade_document_registration_context('${id(301)}',false)`);
  await db.exec(`update public.trade_companies set trade_role='both' where id='${id(301)}'`);
  await actor(2);await denied('select public.standalone_trade_document_access()');
  await actor(1,202);await denied('select public.standalone_trade_document_access()');
  await actor(1);
  await db.exec(`insert into public.company_members values('${id(102)}','${id(1)}','owner')`);
  await denied('select public.standalone_trade_document_access()');
  await db.exec(`delete from public.company_members where user_id='${id(1)}' and company_id='${id(102)}';update auth.sessions set not_after=now()-interval '1 minute' where id='${id(201)}'`);
  await denied('select public.standalone_trade_document_access()');
  await db.exec(`update auth.sessions set not_after=null where id='${id(201)}';insert into private.account_deletion_access_restrictions values('${id(1)}')`);
  await denied('select public.standalone_trade_document_access()');
  await db.exec(`delete from private.account_deletion_access_restrictions;update private.master_feature_settings set enabled=false where feature_key='site_order_documents'`);
  await denied('select public.standalone_trade_document_access()');
  assert((await query("select count(*)::int n from private.master_feature_settings where feature_key<>'site_order_documents'"))[0].n===0,'no unrelated flag rows changed');
  assert((await query("select count(*)::int n from private.trade_document_templates"))[0].n===2,'templates untouched');
  assert((await query("select count(*)::int n from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.proname like '%standalone_trade_document%' and has_function_privilege('anon',p.oid,'execute')"))[0].n===0,'no anonymous new RPC execution');
  await db.exec('rollback');
  // Recovery is rehearsed only after all fixture writers have stopped. Keep
  // additive constraints/functions and an OFF row; never contract/delete data.
  await db.exec("insert into private.master_feature_settings(feature_key,enabled) values('site_order_documents',false)");
  let recoveryRejected=false;
  await db.exec("create or replace function public.current_master_feature_flags() returns jsonb language sql stable security definer set search_path='' as $$select '{}'::jsonb$$");
  try{await guardedRestore();}catch(error){recoveryRejected=error.message==='Recovery identity changed; stop';}
  assert(recoveryRejected,'later public source change refuses restoration');
  await db.exec(candidate.slice(candidate.indexOf('CREATE OR REPLACE FUNCTION public.current_master_feature_flags()'),candidate.indexOf('CREATE OR REPLACE FUNCTION public.set_master_feature_enabled_with_proof')));
  await guardedRestore();
  const recovered=(await db.query(`select p.oid,to_jsonb(p)-'prosrc' attrs,p.prosrc,pg_get_functiondef(p.oid) definition from pg_proc p join pg_namespace n on n.oid=p.pronamespace where ${recoveryTargets} order by p.oid`)).rows;
  assert(JSON.stringify(recovered)===JSON.stringify(originalPublic),'two original definitions/OIDs/attributes restored exactly');
  assert((await db.query("select enabled from private.master_feature_settings where feature_key='site_order_documents'")).rows[0].enabled===false,'OFF flag row retained without delete or enable');
  assert((await db.query("select count(*)::int n from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='private' and p.proname in ('require_trade_documents_master_feature','require_standalone_trade_document_access','standalone_trade_document_registration_context')) or (n.nspname='public' and p.proname in ('standalone_trade_document_access','standalone_trade_document_registration_context'))")).rows[0].n===5,'additive guarded functions retained');
  assert((await db.query("select pg_get_constraintdef(oid) v from pg_constraint where conrelid='private.master_feature_settings'::regclass and conname='master_feature_settings_feature_key_check'")).rows[0].v.includes('site_order_documents'),'additive key constraint retained');
  assert((await db.query("select relrowsecurity and not has_table_privilege('authenticated',oid,'INSERT,UPDATE,DELETE,TRUNCATE') safe from pg_class where oid='private.master_feature_settings'::regclass")).rows[0].safe,'recovery preserves RLS and no client DML');
  console.log(JSON.stringify({engine,checks,status:'passed',scope:'isolated SQL fixture; actual captured deployed function bodies; synthetic JWT/policy setup, no live GoTrue or production activation'}));
} catch(error) {
  console.error(JSON.stringify({engine,checks,status:'failed',message:error.message,code:error.code,position:error.position}));
  process.exitCode=1;
} finally {await db.close();}
