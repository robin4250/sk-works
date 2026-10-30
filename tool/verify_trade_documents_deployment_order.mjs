// Runs the existing V1+V2 form fixture without weakening its assertions, with
// the C master/context module installed first against the captured baseline.
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
const original=await readFile('tool/trade_document_form_server_fixture.mjs','utf8');
const monthEnd=await readFile('tool/verify_trade_document_month_end.mjs','utf8');
const marker='try{\n if(branch===\'bank\'){';
assert.equal(original.split(marker).length,2);
const base=await readFile('docs/review/trade-documents-hub/base-fixture.sql','utf8');
const functions=base.slice(base.indexOf('CREATE OR REPLACE FUNCTION private.account_access_allowed()'));
assert.ok(functions.startsWith('CREATE OR REPLACE FUNCTION'));
const setup=`
 alter table public.companies add column phone text,add column fax text,add column email text;
 alter table public.trade_companies add column id uuid,add column name text,add column phone text,add column linked_company_id uuid;
 create schema extensions;
 create table private.account_deletion_access_restrictions(user_id uuid);
 create table private.master_admins(user_id uuid,enabled boolean);
 create table private.master_feature_settings(feature_key text primary key,enabled boolean not null,updated_at timestamptz,updated_by uuid references auth.users(id),constraint master_feature_settings_feature_key_check check(feature_key in ('vehicle_management','route_assignment','traffic_nearest_station','traffic_train_transfer','traffic_bus_stop')));
 alter table private.master_feature_settings enable row level security;
 revoke all on private.master_feature_settings from public,anon,authenticated;
 create table private.company_seal_png_selection(company_id uuid,enabled boolean,version_id uuid);
 create table private.company_seal_png_versions(id uuid,company_id uuid,png_bytes bytea,sha256 text);
`;
const inject=`
 await db.exec(${JSON.stringify(setup)});
 await db.exec(${JSON.stringify(functions)});
 await db.exec('alter default privileges for role postgres in schema public grant execute on functions to anon,authenticated,service_role');
 await db.exec(await read('docs/review/trade-documents-hub/master-and-standalone-context.sql.review-only'));
 const hubPin=async()=>q("select jsonb_agg(jsonb_build_object('oid',p.oid,'source',md5(p.prosrc),'attrs',to_jsonb(p)-'prosrc') order by p.oid) v from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='public' and p.proname in ('current_master_feature_flags','set_master_feature_enabled_with_proof','standalone_trade_document_access','standalone_trade_document_registration_context')) or (n.nspname='private' and p.proname in ('require_trade_documents_master_feature','require_standalone_trade_document_access','standalone_trade_document_registration_context'))");
 const hubBefore=await hubPin();
 assert.equal((await q('select public.current_master_feature_flags() v')),null);passed++;
`;
const suffix=`
 // C remains intact after the formal V1 prerequisite and V2 upgrade, while
 // the original attachment assertions above still pass with the new flag OFF.
 assert.deepEqual(await hubPin(),hubBefore);passed++;
 await db.exec('reset role');
 await db.query("insert into private.master_feature_settings(feature_key,enabled) values('site_order_documents',true)");
 await db.query('update public.companies set company_seal_enabled=true where id=$1',[company]);
 const selected='90000000-0000-4000-8000-000000000099';
 await db.query("insert into public.trade_companies(id,company_id,name,address,corporate_number,representative_name,phone,trade_role) values($1,$2,'登録会社','相手住所','1234567890123','相手代表','03-0000-0000','both')",[selected,company]);
 await identity(manager,otherSession);
 const context=await q('select public.standalone_trade_document_registration_context($1,false) v',[selected]);
 assert.equal(context.company_id,company);assert.equal(context.actor_id,manager);assert.equal(context.session_id,otherSession);
 assert.equal(context.issuer.fax,'03-3333-4444');assert.equal(context.counterparty.name,'登録会社');passed++;
 await db.exec('reset role');await db.exec("update private.master_feature_settings set enabled=false where feature_key='site_order_documents'");await identity(manager,otherSession);
 await deny(()=>q('select public.standalone_trade_document_access() v'),'42501');
 console.log(JSON.stringify({deployment_order:'C -> formal V1 -> formal V2',hub_attributes_preserved:true,manager_context_after_v2:true,master_off_preserved:true,production_changes:false,real_auth:false}));
`;
// Reuse the existing V2 harness transformation instead of mirroring its
// baseline/schema/negative/financial/signature assertions.
const tmp=await mkdtemp(join(tmpdir(),'trade-module-order-'));
try{
 const fixture=join(tmp,'fixture.mjs');
 let source=original.replace("const root=new URL('../',import.meta.url);","const root=new URL("+JSON.stringify(pathToFileURL(process.cwd()+'/').href)+");")
  .replace(marker,()=> 'try{'+inject+"\n if(branch==='bank'){");
 // The existing V2 harness's unit and extra source strings are exact code
 // constants. Execute its transformer against this augmented fixture in a
 // temporary directory; no repository-owned formal source is changed.
 const unitMatch=monthEnd.match(/const unit=`([\s\S]*?)`;\nconst extra=/);
 const extraMatch=monthEnd.match(/const extra=`([\s\S]*?)`;\n\/\//);
 assert.ok(unitMatch&&extraMatch);
 const metadata=JSON.parse(await readFile('docs/review/trade-document-month-end/deployed-contact-source.json','utf8'));
 let unit=unitMatch[1].replace(/\$\{JSON\.stringify\(metadata\.rows\.find\(r=>r\.proname==='partner_company_profile_value'\)\.definition\.trim\(\)\+';'\)\}/,
  JSON.stringify(metadata.rows.find(r=>r.proname==='partner_company_profile_value').definition.trim()+';'));
 unit=unit.replace('add column phone text,add column fax text,add column email text','add column if not exists phone text,add column if not exists fax text,add column if not exists email text');
 const point=' await identity();\n const w=';
 assert.equal(source.split(point).length,2);source=source.replace(point,()=>unit+point);
 const end=' console.log(JSON.stringify({result:';
 assert.equal(source.split(end).length,2);source=source.replace(end,()=>extraMatch[1]+suffix+end);
 await writeFile(fixture,source);
 const result=spawnSync(process.execPath,[fixture,process.argv[2],'core'],{stdio:'inherit',env:process.env});
 if(result.error)throw result.error;process.exitCode=result.status??1;
}finally{await rm(tmp,{recursive:true,force:true});}
