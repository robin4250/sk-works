import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {preflightStatement} from './capture_full_preflight.mjs';
import {transactionBody} from './sql_transaction.mjs';
import {catalogSql as inlineCatalogSql,equalityGuard,loadReplyRecovery,legacyCaptureSql} from './prepare_atomic_review.mjs';
const modules=['foundation','legacy-response-guard','approval','approval-consent','archive-read','delivery','read-surfaces','archive-payload','approval-operation','refusal'];
const coreSchemas=['trade_document_consent_private','trade_document_confirmation_api_private'];
const allSchemas=[...coreSchemas,'site_order_artifact_private','site_order_manager_private','site_order_package_private'];
const expectedReferenceFks=[
 ['public.companies','trade_document_consent_private.documents','documents_issuer_company_id_fkey','issuer_company_id'],
 ['public.companies','trade_document_consent_private.documents','documents_counterparty_company_id_fkey','counterparty_company_id'],
 ['public.companies','site_order_manager_private.document_scopes','document_scopes_company_id_fkey','company_id'],
 ['public.companies','site_order_manager_private.document_scopes','document_scopes_counterparty_company_id_fkey','counterparty_company_id'],
 ['public.trade_companies','site_order_manager_private.document_scopes','document_scopes_trade_company_id_fkey','trade_company_id'],
 ['public.sites','site_order_manager_private.document_scopes','document_scopes_site_id_fkey','site_id'],
 ['private.company_data_delivery_items','site_order_package_private.packages','packages_data_item_id_fkey','data_item_id'],
 ['public.sites','site_order_package_private.approvals','approvals_accepted_site_id_fkey','accepted_site_id'],
 ['public.sites','site_order_package_private.reply_intents','reply_intents_site_id_fkey','site_id'],
];
const relationNames=['auth.users','auth.sessions','public.companies','public.company_members','public.trade_companies','private.account_deletion_access_restrictions','private.company_connections','private.company_seal_png_selection','private.company_seal_png_versions','private.master_feature_settings','private.document_deliveries','private.company_data_delivery_items','private.site_share_inbox','public.sites','public.app_notifications'];
export async function composeFull(db,{read,q,check,manifest}){
 const fullContract=JSON.parse(await read('docs/review/site-order-private-baseline/full-existing-contract.json'));
 const helperNames=[...manifest.existing_function_contracts.map(f=>f.signature.split('(')[0]),...fullContract.additional_function_names];
 await db.exec(`alter table public.sites alter column id set default gen_random_uuid();
 alter table public.sites add column customer_id uuid,add column formal_name text,add column address text,
 add column nearest_station text,add column representative_name text,add column representative_phone text,
 add column notes text,add column status text not null default 'preparation',add column latitude double precision,
 add column longitude double precision,add column starts_at date,add column ends_at date,add column created_by uuid,add column updated_at timestamptz default now();
 create table private.document_deliveries(id uuid primary key,sender_company_id uuid not null,recipient_company_id uuid not null,sender_name text not null,recipient_name text not null,sent_by uuid,note text not null);
 create table private.company_data_delivery_items(id uuid primary key,delivery_id uuid not null references private.document_deliveries(id),payload_kind text not null,payload jsonb not null,company_path jsonb not null default '[]');
 create table private.site_share_inbox(data_item_id uuid primary key references private.company_data_delivery_items(id),recipient_company_id uuid not null,status text not null default 'pending',responded_by uuid,responded_at timestamptz,accepted_site_id uuid);
 create table public.app_notifications(id uuid primary key default gen_random_uuid(),company_id uuid not null,recipient_user_id uuid not null,kind text not null,title text not null,body text,action_key text,action_id uuid,read_at timestamptz,created_at timestamptz not null default now());
 alter table public.app_notifications enable row level security;`);
 await db.exec(await read('tool/fixtures/site_order_legacy_private_respond.fixture.sql'));
 await db.exec(await read('tool/fixtures/site_order_legacy_public_respond.fixture.sql'));
 await db.exec('revoke all on function public.respond_site_share(uuid,boolean) from public,anon;grant execute on function public.respond_site_share(uuid,boolean) to authenticated,service_role');
 await db.exec("set search_path=''");
 const existingCatalogSql=await read('docs/review/site-order-private-baseline/existing_catalog_normalized.sql');
 const existingBefore=await q(existingCatalogSql,[['auth','private','public']]);
 check(Object.keys(existingBefore.functions).length,13);check(Object.keys(existingBefore.relations).length,15);
 const catalogSql=await read('docs/review/site-order-private-baseline/catalog_normalized.sql');
 const catalog=async schemas=>q(catalogSql,[schemas]);
 let allowedReferenceTriggers=[];
 const protectedCatalog=async()=>{
  const c=await catalog(['auth','private','public']);
  const functions=Object.fromEntries(Object.entries(c.functions).filter(([name])=>helperNames.includes(name.split('(')[0])));
  for(const [name,f]of Object.entries(functions))if(name.split('(')[0]===fullContract.intended_legacy_change.function_name&&f.source_md5===fullContract.intended_legacy_change.after_md5)f.source_md5=fullContract.intended_legacy_change.before_md5;
  const relations=Object.fromEntries(Object.entries(c.relations).filter(([name])=>relationNames.includes(name)));
  const additions=await db.query(`select t.tgname name,np.nspname||'.'||parent.relname parent,nc.nspname||'.'||child.relname child,k.conname constraint_name,
    pg_get_constraintdef(k.oid,true) constraint_definition,
    (select jsonb_agg(a.attname::text order by x.ord)from unnest(k.conkey)with ordinality x(num,ord)join pg_attribute a on a.attrelid=k.conrelid and a.attnum=x.num) child_columns,
    (select jsonb_agg(a.attname::text order by x.ord)from unnest(k.confkey)with ordinality x(num,ord)join pg_attribute a on a.attrelid=k.confrelid and a.attnum=x.num) parent_columns,
    k.confupdtype,k.confdeltype,k.confmatchtype,k.condeferrable,k.condeferred,k.convalidated,t.tgfoid::regprocedure::text function,t.tgtype,t.tgenabled,t.tgisinternal,t.tgnargs,t.tgdeferrable,t.tginitdeferred,
    t.tgqual is null qualification_absent,encode(t.tgargs,'hex') args_hex,t.tgattr::text attributes_text,
    t.tgparentid=0 not_cloned,t.tgoldtable is null and t.tgnewtable is null transition_tables_absent,
    case t.tgtype when 9 then t.tgfoid='pg_catalog."RI_FKey_noaction_del"()'::regprocedure when 17 then t.tgfoid='pg_catalog."RI_FKey_noaction_upd"()'::regprocedure else false end exact_event_function,
    t.tgconstrrelid=k.conrelid child_binding,t.tgconstrindid=k.conindid index_binding,
    exists(select 1 from pg_depend d where d.classid='pg_trigger'::regclass and d.objid=t.oid and d.refclassid='pg_constraint'::regclass and d.refobjid=k.oid and d.deptype='i') internal_dependency
    from pg_trigger t join pg_constraint k on k.oid=t.tgconstraint join pg_class child on child.oid=k.conrelid join pg_namespace nc on nc.oid=child.relnamespace
    join pg_class parent on parent.oid=t.tgrelid join pg_namespace np on np.oid=parent.relnamespace
    where k.contype='f' and nc.nspname=any($1::text[]) and np.nspname||'.'||parent.relname=any($2::text[]) and t.tgrelid=k.confrelid order by parent,child,k.conname,t.tgtype`,[allSchemas,relationNames]);
  allowedReferenceTriggers=additions.rows;
  if(additions.rows.length){
   const actual=additions.rows.map(t=>[t.parent,t.child,t.constraint_name,t.child_columns,t.parent_columns,t.tgtype]).sort();
   const expected=expectedReferenceFks.flatMap(([parent,child,name,column])=>[9,17].map(type=>[parent,child,name,[column],['id'],type])).sort();
   assert.deepEqual(actual,expected,'only exact canonical reference FK triggers may be added');
  }
  for(const t of additions.rows){
   assert.equal(t.qualification_absent,true);assert.equal(t.args_hex,'');assert.equal(t.attributes_text,'');assert.equal(t.not_cloned,true);assert.equal(t.transition_tables_absent,true);assert.equal(t.exact_event_function,true);assert.equal(t.confupdtype,'a');assert.equal(t.confdeltype,'a');assert.equal(t.confmatchtype,'s');assert.equal(t.condeferrable,false);assert.equal(t.condeferred,false);assert.equal(t.convalidated,true);assert.equal(t.child_binding,true);assert.equal(t.index_binding,true);assert.equal(t.internal_dependency,true);
   assert.equal(t.tgdeferrable,false);assert.equal(t.tginitdeferred,false);assert.equal(t.tgisinternal,true);assert.equal(t.tgenabled,'O');assert.equal(t.tgnargs,0);
   assert.ok(['\"RI_FKey_noaction_del\"()','\"RI_FKey_noaction_upd\"()'].includes(t.function));
   const table=relations[t.parent];table.triggers=table.triggers.filter(x=>x.name!=='internal:'+t.child.split('.')[0]+'.'+t.constraint_name+':'+t.tgtype);
  }
  for(const [name,table]of Object.entries(relations)){
   if(table.triggers?.length===0)table.triggers=null;
   // relhastriggers includes exactly the newly validated FK reference triggers.
   if(additions.rows.some(t=>t.parent===name)&&!table.triggers)table.relhastriggers=false;
  }
  return {functions,relations,namespaces:c.namespaces,defaults:await q("select jsonb_agg((to_jsonb(d)-array['oid','defaclrole','defaclnamespace'])||jsonb_build_object('owner',pg_get_userbyid(defaclrole),'namespace',case when defaclnamespace=0 then null else defaclnamespace::regnamespace::text end)order by pg_get_userbyid(defaclrole),defaclnamespace::regnamespace::text,defaclobjtype) v from pg_default_acl d")};
 };
 const before=await protectedCatalog();check(Object.keys(before.functions).length,13);check(Object.keys(before.relations).length,15);
 const paths=['docs/candidates/trade_document_bound_seal_consent_20261021.sql.review-only','docs/review/site-order-artifact-registration/private-register.sql.review-only','docs/review/site-order-manager-purpose/adapter.sql.review-only',...modules.map(n=>'docs/review/site-order-package-flow/'+n+'.sql.review-only')];
 const texts=await Promise.all(paths.map(read));
 const api=await read('docs/candidates/trade_document_confirmation_api_20261022.sql.review-only');
 const actor=api.match(/create function trade_document_confirmation_api_private\.actor\(\)[\s\S]*?end \$\$;/)[0];
 check(Object.fromEntries(paths.map((name,i)=>[name,createHash('sha256').update(texts[i]).digest('hex')])),JSON.parse(await read('docs/review/site-order-private-baseline/full-source-contract.json')));
 check(createHash('sha256').update(actor).digest('hex'),manifest.actor_statement_sha256);
 const recovery=await loadReplyRecovery(process.env.SKO_SITE_REPLY_RECOVERY_SOURCE_ROOT);
 if(recovery){texts.push(recovery.sql);paths.push('external/'+recovery.head+'/'+recovery.path);check(recovery.sha256,'991281df5f789e1e6a3d469dd854609a065d2a6d56db33b85a08d3cf57fd9979');}
 const bodies=texts.map(transactionBody);
 async function install(){
  await db.exec('begin');
  await db.exec(legacyCaptureSql());
  await db.exec(bodies[0]);
  await db.exec('create schema trade_document_confirmation_api_private;revoke all on schema trade_document_confirmation_api_private from public,anon,authenticated,service_role;'+actor+'revoke all on function trade_document_confirmation_api_private.actor() from public,anon,authenticated,service_role');
  for(const body of bodies.slice(1))await db.exec(body);
 }
 const newCatalog=()=>catalog(allSchemas);
 const faults=[
  "alter function site_order_package_private.read_actor() cost 123456",
  "alter table trade_document_consent_private.documents add constraint unknown_company_ref foreign key(transaction_id) references public.companies(id)",
  "create function private.injected_trigger() returns trigger language plpgsql as $$begin return new;end$$;create trigger injected_user_trigger before insert on public.companies for each row execute function private.injected_trigger()",
  "grant execute on function site_order_package_private.read_actor() to authenticated",
  "alter table trade_document_consent_private.events disable trigger all",
  "create policy injected_permit on trade_document_consent_private.documents for select to authenticated using(true)",
 ];
 for(const fault of faults){
  let detected=false;
  try{
   await install();const expected=await newCatalog();check(await protectedCatalog(),before);
   await db.exec(fault);const actual=await newCatalog();
   try{assert.deepEqual(actual,expected);assert.deepEqual(await protectedCatalog(),before);}catch{detected=true;throw Error('expected_catalog_drift');}
   throw Error('fault_not_detected');
  }catch(e){if(e.message!=='expected_catalog_drift')throw e;}finally{await db.exec('rollback');}
  check(detected,true);check(await protectedCatalog(),before);
  check(await q("select count(*)::int v from pg_namespace where nspname=any($1::text[])",[allSchemas]),0);
 }
 await install();const result=await newCatalog();check(await protectedCatalog(),before);
 for(const schema of coreSchemas){
  const ns=result.namespaces.find(n=>n.name===schema);check(ns.acl.some(a=>['PUBLIC','anon','authenticated','service_role'].includes(a[1])),false);
 }
 const funcs=Object.entries(result.functions);
 check(funcs.filter(([n])=>n.startsWith('trade_document_confirmation_api_private.')).length,1);
 for(const [,f]of funcs.filter(([n])=>coreSchemas.some(s=>n.startsWith(s+'.'))))check(f.acl.some(a=>['PUBLIC','anon','authenticated','service_role'].includes(a[1])),false);
 for(const [name,table]of Object.entries(result.relations).filter(([n])=>coreSchemas.some(s=>n.startsWith(s+'.'))&&nNotIndex(n,result))){
  if(table.relkind==='r')check(table.relrowsecurity,true);
 }
 await db.exec('commit');check(await protectedCatalog(),before);
 const existingAfter=await q(existingCatalogSql,[['auth','private','public']]);
 const expectedFunctions=structuredClone(existingBefore.functions);
 for(const [name,f]of Object.entries(expectedFunctions))if(name.split('(')[0]===fullContract.intended_legacy_change.function_name){check(f.source_md5,fullContract.intended_legacy_change.before_md5);f.source_md5=fullContract.intended_legacy_change.after_md5;}
 check(existingAfter.functions,expectedFunctions);check(existingAfter.default_acls,existingBefore.default_acls);check(existingAfter.namespaces,existingBefore.namespaces);
 const sqlGuard=equalityGuard(inlineCatalogSql(catalogSql,allSchemas),result,'site_new_catalog_changed');
 const oldGuard=equalityGuard(inlineCatalogSql(existingCatalogSql,['auth','private','public']),existingAfter,'site_existing_catalog_changed');
 await db.exec('begin');
 try{
  await db.exec("set local log_min_error_statement='fatal'");
  await db.exec(sqlGuard);await db.exec(oldGuard);check(true,true);
  await db.exec('alter function site_order_package_private.read_actor() cost 987654');
  let denied=false;try{await db.exec(sqlGuard);}catch(e){denied=e.code==='55000';}check(denied,true);
 }finally{await db.exec('rollback');}
 check(await newCatalog(),result);
 const boundedQuery=preflightStatement(existingCatalogSql).replace(/^begin read only;set local search_path='';/,'').replace(/;commit;\n$/,'');
 const captured=await q(boundedQuery);check(captured.production_mutation,false);check(Object.keys(captured.snapshot.functions).length,13);check(Object.keys(captured.snapshot.relations).length,15);
 return {modules_installed:12+(recovery?1:0),reply_recovery_source:recovery?{head:recovery.head,sha256:recovery.sha256}:null,core_namespaces:2,native_contract_capture:{before:existingBefore,after:existingAfter},catalog:result,protected_catalog:before,allowed_new_fk_reference_triggers:allowedReferenceTriggers,faults:faults.length,atomic_rollback:true,source_paths:paths};
}
function nNotIndex(name,catalog){return ['r','S'].includes(catalog.relations[name].relkind);}
