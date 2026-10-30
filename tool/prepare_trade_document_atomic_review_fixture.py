from pathlib import Path
import re,json,argparse
parser=argparse.ArgumentParser(description='Generate disposable atomic-composition fixtures; never connect to production')
parser.add_argument('--root',default='.');parser.add_argument('--output',required=True);a=parser.parse_args()
main=Path(a.root).resolve();hub=main;out=Path(a.output).resolve();out.mkdir(parents=True,exist_ok=True)
assert not any(c in str(main)+str(out) for c in '`$'), 'Unsupported fixture path'
(out/'restore-eligibility.sql.review-only').write_bytes((main/'docs/review/trade-document-atomic-composition/restore-eligibility.sql.review-only').read_bytes())
original=(main/'tool/trade_document_form_server_fixture.mjs').read_text()
prefix=original.split("try{\n if(branch==='bank'){")[0]
prefix=prefix.replace("const root=new URL('../',import.meta.url);",'const root=new URL('+json.dumps(main.as_uri()+'/')+');')
prefix="import {spawnSync} from 'node:child_process';\n"+prefix
ordered=(hub/'tool/verify_trade_documents_deployment_order.mjs').read_text();setup=re.search(r'const setup=`([\s\S]*?)`;\nconst inject=',ordered)[1]
base=(hub/'docs/review/trade-documents-hub/base-fixture.sql').read_text();functions=base[base.index('CREATE OR REPLACE FUNCTION private.account_access_allowed()'):]
s=prefix+'\ntry {\nawait db.exec('+json.dumps(setup)+');\nawait db.exec('+json.dumps(functions)+');\n'
s+='await db.exec(\"alter default privileges for role postgres in schema public grant execute on functions to anon,authenticated,service_role\");\n'
s+='''
const rootOut='__ATOMIC_FIXTURE_OUTPUT__';
const targets=['current_master_feature_flags','is_current_user_master_admin','require_reauthentication_session','consume_reauthentication_proof','set_master_feature_enabled_with_proof','account_access_allowed','partner_company_profile_value','set_master_feature_enabled','trade_document_source','save_trade_document_attachment'];
const captured=(await db.query(`select n.nspname schema,p.proname name,pg_get_function_identity_arguments(p.oid) identity,pg_get_functiondef(p.oid) definition,md5(p.prosrc) source_md5,to_jsonb(p) attributes from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') and p.proname=any($1::text[]) order by n.nspname,p.proname`,[targets])).rows;
const exactCaptured=captured.filter(r=>r.schema==='private'||['current_master_feature_flags','is_current_user_master_admin','set_master_feature_enabled_with_proof','set_master_feature_enabled'].includes(r.name));
captured.splice(0,captured.length,...exactCaptured);assert.equal(captured.length,10);
const formalBefore=captured.filter(r=>['trade_document_source','save_trade_document_attachment','partner_company_profile_value'].includes(r.name));
const hubBefore={functions:captured.filter(r=>!['trade_document_source','save_trade_document_attachment'].includes(r.name)),table:(await db.query("select to_jsonb(c) attrs from pg_class c where c.oid='private.master_feature_settings'::regclass")).rows[0].attrs,constraints:(await db.query("select to_jsonb(c) attributes,pg_get_constraintdef(c.oid) definition from pg_constraint c where c.conrelid='private.master_feature_settings'::regclass order by c.oid")).rows};
await fs.writeFile(rootOut+'/fixture-before-formal-full.json',JSON.stringify(formalBefore));
await fs.writeFile(rootOut+'/fixture-before-hub-full.json',JSON.stringify([{metadata:hubBefore}]));
const lean=row=>{const copy=JSON.parse(JSON.stringify(row));delete copy.attributes.prosrc;return copy;};
await fs.writeFile(rootOut+'/fixture-before-formal.json',JSON.stringify(formalBefore.map(lean)));
await fs.writeFile(rootOut+'/fixture-before-hub.json',JSON.stringify([{metadata:{...hubBefore,functions:hubBefore.functions.map(lean)}}]));
const rowSnapshot=async()=>{
 const tables=(await db.query("select schemaname,tablename from pg_tables where schemaname in ('public','private','auth') order by schemaname,tablename")).rows;
 const result={};for(const t of tables)result[t.schemaname+'.'+t.tablename]=(await db.query(`select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]'::jsonb) value from ${t.schemaname}.${t.tablename} t`)).rows[0].value;
 return result;
};
const beforeRows=await rowSnapshot();
const args=[rootOut+'/build_review_bundle.py','--formal-catalog',rootOut+'/fixture-before-formal.json','--hub-catalog',rootOut+'/fixture-before-hub.json','--expected-fixture',rootOut+'/expected-after-fixture.json','--formal-root','__ATOMIC_MAIN_ROOT__','--hub-root','__ATOMIC_HUB_ROOT__','--output',rootOut+'/fixture-review-bundle'];
const built=spawnSync('python3',args,{encoding:'utf8'});assert.equal(built.status,0,built.stderr);console.log(built.stdout.trim());
const forward=await fs.readFile(rootOut+'/fixture-review-bundle/atomic-forward.sql.review-only','utf8');
const fullArgs=args.map(x=>x.replace('/fixture-before-formal.json','/fixture-before-formal-full.json').replace('/fixture-before-hub.json','/fixture-before-hub-full.json').replace('/fixture-review-bundle','/fixture-full-shape-review-bundle'));
const fullBuilt=spawnSync('python3',fullArgs,{encoding:'utf8'});assert.equal(fullBuilt.status,0,fullBuilt.stderr);
assert.equal(await fs.readFile(rootOut+'/fixture-full-shape-review-bundle/atomic-forward.sql.review-only','utf8'),forward);passed++;
const bad=formalBefore.map(lean);bad[0].source_md5='0'.repeat(32);await fs.writeFile(rootOut+'/fixture-before-invalid.json',JSON.stringify(bad));
const badArgs=args.map(x=>x.replace('/fixture-before-formal.json','/fixture-before-invalid.json').replace('/fixture-review-bundle','/fixture-invalid-review-bundle'));
const invalid=spawnSync('python3',badArgs,{encoding:'utf8'});assert.notEqual(invalid.status,0);assert.ok(invalid.stderr.includes('Captured definition/source digest differs'));passed++;

// Force a postflight failure after all four modules have executed. It must
// roll the complete transaction back, including every renamed/new function.
let failed;
try{await db.exec(forward.replace('if counted<>13 then','if counted<>12 then'));}catch(error){failed=error;}
assert.equal(failed?.message,'Installed scope count changed');await db.exec('rollback');
for(const old of captured){const now=(await db.query('select to_jsonb(p) attrs,pg_get_functiondef(p.oid) definition from pg_proc p where p.oid=$1',[old.attributes.oid])).rows[0];assert.deepEqual(now.attrs,old.attributes);assert.equal(now.definition,old.definition);}
assert.equal((await db.query("select to_regprocedure('private.validate_trade_document_form_fields(jsonb)') value")).rows[0].value,null);
assert.deepEqual(await rowSnapshot(),beforeRows);passed++;
const execution=await db.exec(forward);const statements=Array.isArray(execution)?execution:[execution];
const receipt=statements.find(result=>result.rows?.length===18&&result.rows.every(row=>row.attributes&&row.source_md5));assert.equal(receipt?.rows.length,18);passed++;
assert.deepEqual(await rowSnapshot(),beforeRows);passed++;
await identity();
const cap=await q("select public.trade_document_attachment_workspace('payment_certificate',$1,'1') v",[document]);assert.equal(cap.form_fields_schema_version,2);passed++;
await deny(()=>q('select public.standalone_trade_document_access() v'),'42501');
await db.exec('reset role');
const hasReceipt=async()=>(await db.query("select exists(select 1 from private.trade_document_attachments where payload ? 'contract_terms' or payload ? 'form_fields') value")).rows[0].value;
assert.equal(await hasReceipt(),false);passed++;
const restoreEligibility=await fs.readFile(rootOut+'/restore-eligibility.sql.review-only','utf8');
await assert.rejects(()=>db.exec(restoreEligibility),error=>error.code==='55000'&&error.message.startsWith('Stopped writers'));passed++;
// This fixture declaration exercises the guard; it does not prove a production
// maintenance window exists.
await db.exec("select set_config('sko.function_restore_writers_stopped','verified-no-inflight',false)");
await db.exec(restoreEligibility);passed++;
// Rehearse the actual source-only restore before any terms/form receipt.
// The newly allocated current saver OID remains; additive delegates and gates
// are retained. Roll back this rehearsal before testing a real V2 save.
await db.exec('reset role');
await db.exec("insert into private.master_feature_settings(feature_key,enabled) values('site_order_documents',false)");
const installed=(await db.query("select n.nspname schema,p.proname name,pg_get_functiondef(p.oid) definition,to_jsonb(p) attributes from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='private' and p.proname in ('trade_document_source','save_trade_document_attachment','save_trade_document_before_confirmed_terms','save_trade_document_before_form_fields','validate_trade_document_form_fields','partner_company_profile_value','require_trade_documents_master_feature','require_standalone_trade_document_access','standalone_trade_document_registration_context')) or (n.nspname='public' and p.proname in ('current_master_feature_flags','set_master_feature_enabled_with_proof','standalone_trade_document_access','standalone_trade_document_registration_context')) order by n.nspname,p.proname")).rows;
assert.equal(installed.length,13);
const restoreTargets=captured.filter(r=>['current_master_feature_flags','set_master_feature_enabled_with_proof','trade_document_source','partner_company_profile_value','save_trade_document_attachment'].includes(r.name));assert.equal(restoreTargets.length,5);
const unchangedAuth=captured.filter(r=>['is_current_user_master_admin','require_reauthentication_session','consume_reauthentication_proof','account_access_allowed','set_master_feature_enabled'].includes(r.name));assert.equal(unchangedAuth.length,5);
const recoveryScope=[...installed,...unchangedAuth];assert.equal(recoveryScope.length,18);
const restoreCatalog=JSON.stringify(recoveryScope);assert.ok(!restoreCatalog.includes('$restore_catalog$'));
const identityGuard="do $restore_identity$ declare e jsonb;p pg_proc;begin for e in select value from jsonb_array_elements($restore_catalog$"+restoreCatalog+"$restore_catalog$::jsonb) loop select q.* into p from pg_proc q where q.oid=(e#>>'{attributes,oid}')::oid;if not found or to_jsonb(p) is distinct from e->'attributes' or pg_get_functiondef(p.oid) is distinct from e->>'definition' then raise exception 'Committed restore identity changed; stop' using errcode='55000';end if;end loop;end $restore_identity$;";
const stoppedRestore=async()=>{await db.exec(restoreEligibility);await db.exec(identityGuard);for(const target of restoreTargets)await db.exec(target.definition);};
const beforeRestoreRows=await rowSnapshot();
const tableBefore=(await db.query("select to_jsonb(c) attrs from pg_class c where c.oid='private.master_feature_settings'::regclass")).rows[0].attrs;
const constraintsBefore=(await db.query("select to_jsonb(c) attrs from pg_constraint c where c.conrelid='private.master_feature_settings'::regclass order by c.oid")).rows;
await db.exec('begin');await stoppedRestore();
for(const old of restoreTargets){const now=(await db.query('select to_jsonb(p) attrs from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname=$1 and p.proname=$2',[old.schema,old.name])).rows[0];const expected={...old.attributes,oid:now.attrs.oid};assert.deepEqual(now.attrs,expected);if(old.name!=='save_trade_document_attachment')assert.equal(now.attrs.oid,old.attributes.oid);}
for(const row of installed.filter(x=>!restoreTargets.some(t=>t.schema===x.schema&&t.name===x.name))){assert.deepEqual((await db.query('select to_jsonb(p) attrs from pg_proc p where p.oid=$1',[row.attributes.oid])).rows[0].attrs,row.attributes);}
assert.deepEqual(await rowSnapshot(),beforeRestoreRows);
assert.deepEqual((await db.query("select to_jsonb(c) attrs from pg_class c where c.oid='private.master_feature_settings'::regclass")).rows[0].attrs,tableBefore);
assert.deepEqual((await db.query("select to_jsonb(c) attrs from pg_constraint c where c.conrelid='private.master_feature_settings'::regclass order by c.oid")).rows,constraintsBefore);
await db.exec('rollback');passed++;
for(const driftTarget of ['private.save_trade_document_attachment(text,uuid,text,integer,jsonb)','private.account_access_allowed()']){
 await db.exec('begin;alter function '+driftTarget+' cost 101');
 await assert.rejects(stoppedRestore,error=>error.code==='55000'&&error.message==='Committed restore identity changed; stop');await db.exec('rollback');passed++;
}
for(const row of recoveryScope)assert.deepEqual((await db.query('select to_jsonb(p) attrs from pg_proc p where p.oid=$1',[row.attributes.oid])).rows[0].attrs,row.attributes);


await identity();const form={...fresh(),schema:2,progress_cutoff_day:'month_end',issuer_representative_title:'',amount_description:'下記「施工単価内訳書」による'};
const payload={...cap.defaults,issue_date:'2026-09-15',work_name:'明示工事',work_address:'東京',intro_text:'工事を発注',payment_conditions:'完了後支払い',notes:'',contract_terms:reference,form_fields:form};
await q("select public.save_trade_document_attachment('payment_certificate',$1,'1',0,$2::jsonb) v",[document,JSON.stringify(payload)]);
await db.exec('reset role');assert.equal(await hasReceipt(),true);passed++;
await assert.rejects(stoppedRestore,error=>error.code==='55000'&&error.message.startsWith('Saved terms/form receipt'));passed++;

let replay;
try{await db.exec(forward);}catch(error){replay=error;}assert.equal(replay?.message,'Fresh full function catalog changed; stop');await db.exec('rollback');passed++;
console.log(JSON.stringify({result:'PASS atomic machine review plan',checks:passed,full_preflight_functions:10,full_postflight_scope:13,atomic_failed_postflight_rollback:true,business_rows_unchanged_by_install:true,master_off:true,receipt_blocks_legacy_restore:true,source_only_restore_rehearsed:true,recovery_receipt_functions:18,committed_receipt_functions:18,actual_public_default_privileges:true,later_identity_drift_refuses_restore:true,auth_dependency_drift_refuses_restore:true,production:false}));
} finally {await db.close();}
'''
s=s.replace('__ATOMIC_FIXTURE_OUTPUT__',out.as_posix()).replace('__ATOMIC_MAIN_ROOT__',main.as_posix()).replace('__ATOMIC_HUB_ROOT__',main.as_posix())
s=s.replace("rootOut+'/build_review_bundle.py'",json.dumps(str(main/'tool/build_trade_document_deployment_review.py')))
s=s.replace("console.log(JSON.stringify({result:'PASS atomic machine review plan'","const summary={result:'PASS atomic machine review plan'")
s=s.replace("receipt_blocks_legacy_restore:true,source_only_restore_rehearsed:true,recovery_receipt_functions:18,committed_receipt_functions:18,actual_public_default_privileges:true,later_identity_drift_refuses_restore:true,auth_dependency_drift_refuses_restore:true,production:false}));","receipt_blocks_legacy_restore:true,source_only_restore_rehearsed:true,recovery_receipt_functions:18,committed_receipt_functions:18,actual_public_default_privileges:true,later_identity_drift_refuses_restore:true,auth_dependency_drift_refuses_restore:true,production:false};await fs.writeFile(rootOut+'/atomic-proof.json',JSON.stringify(summary,null,2));console.log(JSON.stringify(summary));")
(out/'machine-plan-fixture.mjs').write_text(s)
ordered=(main/'tool/verify_trade_documents_deployment_order.mjs').read_text()
point=' assert.deepEqual(await hubPin(),hubBefore);passed++;'
assert ordered.count(point)==1
capture="""
 const atomicExpected=(await db.query(\"select n.nspname schema,p.proname name,pg_get_function_identity_arguments(p.oid) arguments,pg_get_functiondef(p.oid) definition,md5(p.prosrc) source_md5,to_jsonb(p) attributes,pg_get_userbyid(p.proowner) owner from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='private' and p.proname in ('trade_document_source','save_trade_document_attachment','save_trade_document_before_confirmed_terms','save_trade_document_before_form_fields','validate_trade_document_form_fields','partner_company_profile_value','require_trade_documents_master_feature','require_standalone_trade_document_access','standalone_trade_document_registration_context')) or (n.nspname='public' and p.proname in ('current_master_feature_flags','set_master_feature_enabled_with_proof','standalone_trade_document_access','standalone_trade_document_registration_context')) order by n.nspname,p.proname\")).rows;
 await fs.writeFile(OUT_PATH,JSON.stringify(atomicExpected,null,2));
""".replace('OUT_PATH',json.dumps(str(out/'expected-after-fixture.json')))
ordered=ordered.replace(point,point+capture)
(out/'capture-ordered-fixture.mjs').write_text(ordered)
print(json.dumps({'prepared':True,'production':False,'output':str(out)}))
