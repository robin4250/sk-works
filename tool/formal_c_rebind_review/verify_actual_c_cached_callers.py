"""Generate one bounded disposable actual-C cached-caller probe. No production interface."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).absolute().parent))
from verify_expected_capture import verify_sources

EXTRA_PINS = {
    'tool/build_trade_document_deployment_review.py': '9df1d1863857fa12967b35d76a65004c02a64001f4b54d64bdddb20119d59f8d',
    'supabase/migrations/20261014124714_monthly_trade_document_attachment.sql': '4ab864259db4e8791078237a9337862dfa90b6ea451b47f07a2b5132da2edc57',
    'docs/candidates/trade_document_initial_settings_20261021.sql.review-only': 'be7f7917b84c1982dcee40c247a266e4ceea93c8d3e60cad8823d3f78e8cb4ab',
}
EXPECTED_SHA = '292a75705dd72d68404181cdd970b0f0526b4aaed275257cfefeb82a25125ec6'

def once(text, old, new):
    if text.count(old) != 1:
        raise ValueError('Frozen fixture anchor is missing or ambiguous')
    return text.replace(old, new)

def private_file(path, data):
    with os.fdopen(os.open(path, os.O_WRONLY|os.O_CREAT|os.O_EXCL, 0o600), 'wb') as f:
        f.write(data)

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source-root', type=Path, required=True)
    p.add_argument('--expected', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    root = a.source_root.resolve()
    verify_sources(root)
    for path, sha in EXTRA_PINS.items():
        if hashlib.sha256((root/path).read_bytes()).hexdigest() != sha:
            raise ValueError('Frozen dependency differs: '+path)
    if a.expected.is_symlink() or not a.expected.is_file() or a.expected.stat().st_size > 8*1024*1024:
        raise ValueError('Regular bounded actual13 artifact required')
    expected = a.expected.read_bytes()
    if hashlib.sha256(expected).hexdigest() != EXPECTED_SHA:
        raise ValueError('Independently reviewed actual13 bytes required')
    out = a.output.absolute()
    if out.exists() or any(p.is_symlink() for p in [out, *out.parents]):
        raise ValueError('A new private output path is required')
    out.mkdir(mode=0o700)
    subprocess.run([sys.executable, '-I', '-B', str(root/'tool/prepare_trade_document_atomic_review_fixture.py'),
                    '--root', str(root), '--output', str(out)], check=True, timeout=15, umask=0o077)
    private_file(out/'expected-after-fixture.json', expected)
    machine = (out/'machine-plan-fixture.mjs').read_text()
    anchor = '// Force a postflight failure after all four modules have executed.'
    if machine.count(anchor) != 1:
        raise ValueError('Frozen atomic fixture boundary changed')
    # Retain its real baseline, full catalog capture and fixed builder invocation.
    # The tail containing old restore rehearsals is deliberately never executed.
    source = machine.split(anchor)[0]
    old_init = 'const {PGlite}=await import(process.argv[2]);const db=new PGlite();let passed=0;'
    prelude = r'''
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
const require=createRequire(new URL('__DEPENDENCY_PACKAGE__'));
const {Client}=require('pg');
const uri=new URL(process.env.PARTNER_BANK_TEST_DATABASE_URL??'');
if(uri.hostname!=='127.0.0.1'||uri.pathname!='/partner_bank_fixture'||uri.username!=='postgres'||uri.password!=='fixture-only')throw Error('Dedicated disposable loopback only');
const clients=[];let opened=0,closed=0;let report;let passed=0;
const connect=async()=>{
 const raw=new Client({connectionString:uri.href,connectionTimeoutMillis:3000,query_timeout:8000});
 clients.push(raw);await raw.connect();opened++;
 await raw.query("set statement_timeout='8s';set lock_timeout='4s'");
 return {query:(sql,args)=>raw.query(sql,args),exec:sql=>raw.query(sql)};
};
let db;
try {
 db=await connect();
'''.replace('__DEPENDENCY_PACKAGE__', (root/'tool/security/fixture_dependencies/package.json').as_uri())
    source = once(source, old_init, prelude)
    source = once(source, '\ntry {\nawait db.exec(', '\nawait db.exec(')
    patch = (root/'docs/candidates/trade_document_initial_settings_20261021.sql.review-only').read_text()
    pairs = re.findall(r'workspace_definition:=replace\(workspace_definition,\$(?:auto_)?old\$([\s\S]*?)\$(?:auto_)?old\$,\$(?:auto_)?new\$([\s\S]*?)\$(?:auto_)?new\$\);', patch)
    if len(pairs) != 2:
        raise ValueError('Exactly two existing public workspace literal transformations required')
    baseline = r'''
// This is a reconstruction from two hash-pinned PUBLIC sources, not a private
// catalog dump. Only workspace is changed; template and Auth helpers are not.
const workspaceOld=(await db.query("select pg_get_functiondef(oid) definition,md5(prosrc) body from pg_proc where oid='private.trade_document_attachment_workspace(text,uuid,text)'::regprocedure")).rows[0];
assert.equal(workspaceOld.body,'c263b374c1279dee5dc685971b2c447d');
let workspaceDefinition=workspaceOld.definition;
for(const [old,next] of __PUBLIC_PAIRS__){assert.equal(workspaceDefinition.split(old).length,2);workspaceDefinition=workspaceDefinition.replace(old,next);}
await db.exec(workspaceDefinition);
const baselineWorkspace=(await db.query("select md5(prosrc) body,prosecdef,pg_get_userbyid(proowner) owner,proacl::text acl from pg_proc where oid='private.trade_document_attachment_workspace(text,uuid,text)'::regprocedure")).rows[0];
assert.deepEqual(baselineWorkspace,{body:'76d24c4ee4de18bed1605f2d4c151020',prosecdef:true,owner:'postgres',acl:'{postgres=X/postgres,authenticated=X/postgres}'});
'''.replace('__PUBLIC_PAIRS__', json.dumps(pairs))
    source = once(source, "const targets=['current_master_feature_flags'", baseline+"\nconst targets=['current_master_feature_flags'")
    probe = r'''
const callerSnapshot=async()=> (await db.query("select n.nspname,p.proname,pg_get_functiondef(p.oid) definition,to_jsonb(p) attributes from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='public' and p.proname in ('save_trade_document_attachment','trade_document_attachment_workspace')) or (n.nspname='private' and p.proname='trade_document_attachment_workspace') order by n.nspname,p.proname")).rows;
const callerBefore=await callerSnapshot();assert.equal(callerBefore.length,3);
const currentPublicSave=callerBefore.find(x=>x.nspname==='public'&&x.proname==='save_trade_document_attachment');
assert.equal(createHash('md5').update(currentPublicSave.attributes.prosrc).digest('hex'),'3121ba766b2be6fa5713e27b2c2d4254');assert.equal(currentPublicSave.attributes.prosecdef,false);
const currentPublicWork=callerBefore.find(x=>x.nspname==='public'&&x.proname==='trade_document_attachment_workspace');
assert.equal(createHash('md5').update(currentPublicWork.attributes.prosrc).digest('hex'),'ae9915f856abf06953c3dc516a2ce86d');assert.equal(currentPublicWork.attributes.prosecdef,false);
const snapshotHash=async()=>createHash('sha256').update(JSON.stringify(await rowSnapshot())).digest('hex');
const rowsBefore=await snapshotHash();
assert.equal((await db.query("show server_version_num")).rows[0].server_version_num,'170006');
const setActor=async(conn,role)=>{
 assert.ok(['authenticated','postgres'].includes(role));
 await conn.exec('set role '+role);
 await conn.query("select set_config('test.uid',$1,false),set_config('request.jwt.claims',$2,false)",[admin,JSON.stringify({sub:admin,session_id:session,role:'authenticated',is_anonymous:false})]);
};
const literal=s=>"'"+String(s).replaceAll("'","''")+"'";
const saveSQL="select public.save_trade_document_attachment('payment_certificate',$1,'1',0,$2::jsonb) v";
const modes=['plain','prepared_custom','prepared_generic'];
const selectPlan=async(conn,mode)=>{
 assert.ok(modes.includes(mode));
 await conn.exec('set plan_cache_mode='+({plain:'auto',prepared_custom:'force_custom_plan',prepared_generic:'force_generic_plan'}[mode]));
};
const save=async(conn,mode,payload)=>{
 await selectPlan(conn,mode);
 return mode==='plain'?(await conn.query(saveSQL,[document,JSON.stringify(payload)])).rows[0].v:
  (await conn.query('execute sko_cached_save('+literal(document)+','+literal(JSON.stringify(payload))+'::jsonb)')).rows[0].v;
};
const work=async(conn,mode)=>{
 await selectPlan(conn,mode);
 return mode==='plain'?(await conn.query("select public.trade_document_attachment_workspace('payment_certificate',$1,'1') v",[document])).rows[0].v:
  (await conn.query('execute sko_cached_workspace('+literal(document)+')')).rows[0].v;
};
const txn=async(conn,action)=>{
 await conn.exec('begin');
 try {return {accepted:true,result:await action()};}
 catch(e){return {accepted:false,code:e.code,message:e.message};}
 finally {await conn.exec('rollback');}
};
const authWarm=await connect();await setActor(authWarm,'authenticated');
const ownerWarm=await connect();await setActor(ownerWarm,'postgres');
for(const conn of [authWarm,ownerWarm]){
 await conn.exec("prepare sko_cached_save(uuid,jsonb) as select public.save_trade_document_attachment('payment_certificate',$1,'1',0,$2) v");
 await conn.exec("prepare sko_cached_workspace(uuid) as select public.trade_document_attachment_workspace('payment_certificate',$1,'1') v");
}
const earlyWork=await work(authWarm,'plain');
const basePayload={...earlyWork.defaults,issue_date:'2026-09-15',work_name:'Cache verification',work_address:'Fixture',intro_text:'Explicit order',payment_conditions:'Explicit payment',notes:''};
const invalids={terms:{...basePayload,contract_terms:{...reference,source_sha256:'0'.repeat(64)},form_fields:fresh()},form:{...basePayload,contract_terms:reference,form_fields:{...fresh(),payment_day:32}}};
const observations=[];
for(const [role,conn] of [['authenticated',authWarm],['postgres',ownerWarm]]){
 for(const mode of modes){
  assert.equal((await work(conn,mode)).form_fields_schema_version,undefined);
  for(const [kind,payload] of Object.entries(invalids)){
   const before=await txn(conn,()=>save(conn,mode,payload));
   assert.equal(before.accepted,true,'Pre-C warm must exercise the real permissive old saver');
   assert.equal(before.result.version,1);
   observations.push({phase:'before_C',role,mode,kind,accepted:true,rolled_back:true});
   assert.equal(await snapshotHash(),rowsBefore);
  }
 }
}
// Installer has its own owner connection. The warmed authenticated connection
// retains the same role, prepared statements and backend throughout this DDL.
const backendBefore=(await authWarm.query('select pg_backend_pid() pid,current_user role')).rows[0];
const execution=await db.exec(forward);const statements=Array.isArray(execution)?execution:[execution];
const receipt=statements.find(r=>r.rows?.length===18&&r.rows.every(x=>x.attributes&&x.source_md5));assert.equal(receipt?.rows.length,18);
// The unchanged atomic SQL already ran its full thirteen-record postflight.
// Independently compare its returned records with the frozen actual13 too,
// rather than interpreting an eighteen-row result shape as that proof.
const expected13=JSON.parse(await fs.readFile(rootOut+'/expected-after-fixture.json','utf8'));
const nonlocal=attrs=>Object.fromEntries(Object.entries(attrs).filter(([key])=>!['oid','pronamespace','proowner','prolang'].includes(key)));
for(const expected of expected13){
 const actual=receipt.rows.filter(x=>x.schema===expected.schema&&x.name===expected.name&&x.identity===expected.arguments);
 assert.equal(actual.length,1);assert.equal(actual[0].source_md5,expected.source_md5);
 assert.deepEqual(nonlocal(actual[0].attributes),nonlocal(expected.attributes));
 assert.equal(actual[0].definition,expected.definition);
}
assert.equal(expected13.length,13);
console.log(JSON.stringify({actual_atomic_full_postflight_completed:true,explicit_expected13_comparisons:13,legacy_restore_executed:false}));
assert.equal(await snapshotHash(),rowsBefore);
assert.deepEqual(await callerSnapshot(),callerBefore,'C must not re-create or alter existing public/workspace callers');
assert.equal((await db.query("select count(*)::int n from private.master_feature_settings where feature_key='site_order_documents' and enabled")).rows[0].n,0);
assert.deepEqual((await authWarm.query('select pg_backend_pid() pid,current_user role')).rows[0],backendBefore);
for(const [role,conn] of [['authenticated',authWarm],['postgres',ownerWarm]]){
 for(const mode of modes){
  assert.equal((await work(conn,mode)).form_fields_schema_version,2);
  for(const [kind,payload] of Object.entries(invalids)){
   const after=await txn(conn,()=>save(conn,mode,payload));
   observations.push({phase:'after_C',role,mode,kind,accepted:after.accepted,code:after.code??null,message:after.message??null,rolled_back:true});
   if(role==='authenticated')assert.equal(after.accepted,false,'Authenticated warmed caller bypassed the actual C validators/ACL');
   if(!after.accepted){
    if(after.code==='22023')assert.equal(after.message,kind==='terms'?'Unknown confirmed terms reference':'Invalid form integer range');
    else {assert.equal(after.code,'42501');assert.match(after.message,/permission denied for function save_trade_document_before_(confirmed_terms|form_fields)/);}
   }
   assert.equal(await snapshotHash(),rowsBefore);
  }
 }
}
const aliases=(await db.query("select proname,md5(prosrc) body,proacl::text acl from pg_proc where oid in (to_regprocedure('private.save_trade_document_before_confirmed_terms(text,uuid,text,integer,jsonb)'),to_regprocedure('private.save_trade_document_before_form_fields(text,uuid,text,integer,jsonb)')) order by proname")).rows;
assert.equal(aliases.length,2);assert.ok(aliases.every(x=>x.acl==='{postgres=X/postgres}'));
for(const alias of aliases){
 const sql='select private.'+alias.proname+"('payment_certificate',$1,'1',0,$2::jsonb) v";
 const denied=await txn(authWarm,()=>authWarm.query(sql,[document,JSON.stringify(invalids.form)]));
 assert.equal(denied.accepted,false);assert.equal(denied.code,'42501');
 const privileged=await txn(ownerWarm,()=>ownerWarm.query(sql,[document,JSON.stringify(invalids.form)]));
 observations.push({phase:'explicit_alias',role:'postgres',alias:alias.proname,accepted:privileged.accepted,code:privileged.code??null,rolled_back:true,ordinary_authenticated_route:false});
 assert.equal(await snapshotHash(),rowsBefore);
}
const freshConnection=await connect();await setActor(freshConnection,'authenticated');
const freshWork=await work(freshConnection,'plain');assert.equal(freshWork.form_fields_schema_version,2);
const good={...freshWork.defaults,issue_date:'2026-09-15',work_name:'Fresh canonical save',work_address:'Fixture',intro_text:'Explicit order',payment_conditions:'Explicit payment',notes:'',contract_terms:reference,form_fields:fresh()};
const saved=await save(freshConnection,'plain',good);assert.equal(saved.version,1);assert.deepEqual(saved.payload.contract_terms,reference);assert.deepEqual(saved.payload.form_fields,fresh());
const finalRows=await rowSnapshot();
assert.equal(finalRows['private.trade_document_attachments'].length,1);
assert.equal(finalRows['private.trade_document_attachment_history'].length,0);
for(const [table,rows] of Object.entries(beforeRows))if(table!=='private.trade_document_attachments')assert.deepEqual(finalRows[table],rows);
const preparedEvidence=(await authWarm.query('select name,generic_plans,custom_plans from pg_prepared_statements where name in (\'sko_cached_save\',\'sko_cached_workspace\') order by name')).rows;
assert.equal(preparedEvidence.length,2);
for(const evidence of preparedEvidence){
 const minimum=evidence.name==='sko_cached_save'?4:2;
 assert.ok(Number(evidence.generic_plans)>=minimum);assert.ok(Number(evidence.custom_plans)>=minimum);
}
report={contract:'sko.actual_C_cached_callers.v1',observations,preparedEvidence,cache_mode_choices:modes,server_version_num:170006,actual_C_receipt_functions:18,explicit_expected13_comparisons:13,after13_contract_unchanged:true,public_callers_unchanged:true,fixture_master_enabled_rows:0,actual_workspace_source_md5:'76d24c4ee4de18bed1605f2d4c151020',public_source_only_baseline:true,native_transport:'bounded direct pg; frozen Auth fixture helpers retained',authenticated_backend_role_unchanged:true,fresh_authenticated_save_succeeded:true,negative_rows_preserved:true,old_restore_executed:false,generic1711_executed:false,fixture_authentication_synthetic:true,real_GoTrue:false,privileged_direct_calls_are_separate_boundary:true,inflight_and_queue_proven:false,production:false,deployable:false};
} finally {
 let cleanupFailures=0;
 for(const client of clients.reverse()){
  try {await Promise.race([client.end(),new Promise((_,reject)=>{const timer=setTimeout(()=>reject(Error('bounded close timeout')),4000);timer.unref();})]);closed++;}
  catch(e){cleanupFailures++;console.error(JSON.stringify({cleanup_error:e.message}));}
 }
 assert.equal(cleanupFailures,0);assert.equal(closed,clients.length);
}
report.connections={allocated:clients.length,opened,closed};
await fs.writeFile('__PROOF__',JSON.stringify(report,null,2),{flag:'wx',mode:0o600});
console.log(JSON.stringify(report));
'''.replace('__PROOF__', (out/'cached-caller-proof.json').as_posix())
    source += probe
    if 'stoppedRestore' in source or 'sko.function_restore_writers_stopped' in source:
        raise ValueError('Old restore rehearsal must not enter the new probe')
    private_file(out/'actual-cached-callers.mjs', source.encode())
    print(json.dumps({'generated':True,'production':False,'deployable':False,'expected13_sha256':EXPECTED_SHA,'workspace_public_literal_patches':2,'old_restore_executed':False}))

if __name__ == '__main__':
    main()
