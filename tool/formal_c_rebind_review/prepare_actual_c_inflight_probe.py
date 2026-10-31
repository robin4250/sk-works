"""One disposable old-saver/actual-C in-flight observation. Never a live installer."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

CACHED_SHA='7d0bab22246d59a717117ac5ed3ce6a8ddc749070462b144a0c795795b225ba2'
HELPER_SHA='a4711104d17791190f4bfbb39495261ead4947b4df9cd23aaa819bc8440695e2'
BOUNDARY='const callerSnapshot=async()=>'

def sha(path):
    if path.is_symlink() or not path.is_file() or path.stat().st_size>8*1024*1024:
        raise ValueError('Regular bounded frozen source required')
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source-root',type=Path,required=True)
    p.add_argument('--expected',type=Path,required=True)
    p.add_argument('--frozen-cached-generator',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args()
    cached=a.frozen_cached_generator.absolute()
    if sha(cached)!=CACHED_SHA or sha(cached.parent/'verify_expected_capture.py')!=HELPER_SHA:
        raise ValueError('Exact 3bb generator and its reviewed sibling required')
    out=a.output.absolute()
    if out.exists() or any(x.is_symlink() for x in [out,*out.parents]):
        raise ValueError('New private output only')
    out.mkdir(mode=0o700)
    generated=out/'frozen-generated'
    subprocess.run([sys.executable,'-I','-B',str(cached),'--source-root',str(a.source_root.absolute()),
      '--expected',str(a.expected.absolute()),'--output',str(generated)],check=True,timeout=30,umask=0o077)
    complete=(generated/'actual-cached-callers.mjs').read_text()
    if complete.count(BOUNDARY)!=1:
        raise ValueError('Exact frozen extraction boundary required')
    prefix,tail=complete.split(BOUNDARY)
    raw_prefix=prefix
    if not all(x in tail for x in ['preparedEvidence','force_generic_plan','fresh_authenticated_save_succeeded']):
        raise ValueError('Frozen tail identity differs')
    if any(x in prefix for x in ['sko_cached_save','stoppedRestore','sko.function_restore_writers_stopped']):
        raise ValueError('Warm/restore runtime leaked into the new prefix')
    old='let db;\ntry {'
    if prefix.count(old)!=1:
        raise ValueError('Frozen connection ownership anchor differs')
    ownership=r'''let db,holder,oldCaller,observer,oldTask,installTask;let holderHeld=false,oldTx=false;
const bounded=async promise=>{
 let timer;try{return await Promise.race([promise,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('Probe settlement not observed')),10000);})]);}
 finally{clearTimeout(timer);}
};
try {'''
    prefix=prefix.replace(old,ownership)
    if prefix.count(ownership)!=1 or prefix.replace(ownership,old)!=raw_prefix:
        raise ValueError('Only the declared connection-ownership prefix change is permitted')
    runtime=r'''
const expected13=JSON.parse(await fs.readFile(rootOut+'/expected-after-fixture.json','utf8'));
const shape=attrs=>Object.fromEntries(Object.entries(attrs).filter(([k])=>!['oid','pronamespace','proowner','prolang'].includes(k)));
const readCatalog=async()=> (await observer.query("select n.nspname schema,p.proname name,pg_get_function_identity_arguments(p.oid) identity,pg_get_functiondef(p.oid) definition,md5(p.prosrc) source_md5,to_jsonb(p) attributes from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') order by n.nspname,p.proname,p.oid")).rows;
const signature=x=>x.schema+'.'+x.name+'('+(x.identity??x.arguments)+')';
const beforeMatches=rows=>captured.every(want=>rows.some(x=>signature(x)===signature(want)&&x.definition===want.definition&&JSON.stringify(x.attributes)===JSON.stringify(want.attributes)));
const afterMatches=rows=>expected13.length===13&&expected13.every(want=>rows.some(x=>signature(x)===signature(want)&&x.definition===want.definition&&x.source_md5===want.source_md5&&JSON.stringify(shape(x.attributes))===JSON.stringify(shape(want.attributes))));
const catalogClass=rows=>afterMatches(rows)?'exact_after13':beforeMatches(rows)?'exact_before10':'unresolved';
const monitor=async pid=>(await observer.query("select state,wait_event_type,wait_event,pg_blocking_pids(pid) blockers from pg_stat_activity where pid=$1",[pid])).rows[0]??null;
const watch=promise=>{
 const task={done:false,value:null};
 task.result=promise.then(value=>({ok:true,value}),error=>({ok:false,code:error.code??null,message:error.message})).then(value=>{task.done=true;task.value=value;return value;});
 return task;
};
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
holder=await connect();oldCaller=await connect();observer=await connect();
assert.equal((await observer.query('show server_version_num')).rows[0].server_version_num,'170006');
const installerPid=(await db.query('select pg_backend_pid() pid')).rows[0].pid;
const holderPid=(await holder.query('select pg_backend_pid() pid')).rows[0].pid;
await oldCaller.exec('set role authenticated');
await oldCaller.query("select set_config('test.uid',$1,false),set_config('request.jwt.claims',$2,false)",[admin,JSON.stringify({sub:admin,session_id:session,role:'authenticated',is_anonymous:false})]);
const oldIdentity=(await oldCaller.query('select pg_backend_pid() pid,current_user role')).rows[0];assert.equal(oldIdentity.role,'authenticated');
const oldWorkspace=(await oldCaller.query("select public.trade_document_attachment_workspace('payment_certificate',$1,'1') v",[document])).rows[0].v;
const oldPayload={...oldWorkspace.defaults,issue_date:'2026-09-15',work_name:'In-flight fixture',work_address:'Fixture',intro_text:'Explicit order',payment_conditions:'Explicit payment',notes:'',contract_terms:reference,form_fields:{...fresh(),payment_day:32}};
const key='trade-appendix:payment_certificate:'+document;
const rowBefore=await rowSnapshot();assert.deepEqual(rowBefore,beforeRows);
const callers=async()=> (await observer.query("select n.nspname,p.proname,pg_get_functiondef(p.oid) definition,to_jsonb(p) attributes from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='public' and p.proname in ('save_trade_document_attachment','trade_document_attachment_workspace')) or (n.nspname='private' and p.proname='trade_document_attachment_workspace') order by n.nspname,p.proname")).rows;
const callersBefore=await callers();assert.equal(callersBefore.length,3);
const baselineCatalog=await readCatalog();assert.equal(catalogClass(baselineCatalog),'exact_before10');
const masterShape=async()=>({
 table:(await observer.query("select to_jsonb(c) attrs from pg_class c where c.oid='private.master_feature_settings'::regclass")).rows[0].attrs,
 columns:(await observer.query("select to_jsonb(a) attrs from pg_attribute a where attrelid='private.master_feature_settings'::regclass order by attnum")).rows,
 defaults:(await observer.query("select to_jsonb(d) attrs,pg_get_expr(adbin,adrelid) expression from pg_attrdef d where adrelid='private.master_feature_settings'::regclass order by adnum")).rows,
 constraints:(await observer.query("select to_jsonb(c) attributes,pg_get_constraintdef(c.oid) definition from pg_constraint c where c.conrelid='private.master_feature_settings'::regclass order by c.oid")).rows,
});
const masterBefore=await masterShape();
const predecessor=captured.find(x=>x.schema==='private'&&x.name==='save_trade_document_attachment');
assert.equal(predecessor.source_md5,'82fa37936aea1e0199e1b359e1379d65');
assert.ok(predecessor.attributes.prosrc.indexOf('perform pg_advisory_xact_lock')>=0);
assert.ok(predecessor.attributes.prosrc.indexOf('perform pg_advisory_xact_lock')<predecessor.attributes.prosrc.indexOf('source:=private.trade_document_source'));
await holder.exec('begin');holderHeld=true;
await holder.query('select pg_advisory_xact_lock(hashtextextended($1,0))',[key]);
await oldCaller.exec('begin');oldTx=true;
oldTask=watch(oldCaller.query("select public.save_trade_document_attachment('payment_certificate',$1,'1',0,$2::jsonb) v",[document,JSON.stringify(oldPayload)]));
let lockProof;
for(let n=0;n<50;n++){
 const status=await monitor(oldIdentity.pid);
 const pairs=(await observer.query("select w.classid::text,w.objid::text,w.objsubid,w.mode from pg_locks w join pg_locks h on h.locktype=w.locktype and h.database is not distinct from w.database and h.classid=w.classid and h.objid=w.objid and h.objsubid=w.objsubid where w.pid=$1 and h.pid=$2 and w.locktype='advisory' and not w.granted and h.granted",[oldIdentity.pid,holderPid])).rows;
 if(status?.wait_event_type==='Lock'&&status.blockers.includes(holderPid)&&pairs.length===1){lockProof={status,pairs};break;}
 if(oldTask.done)throw Error('Old caller did not enter the expected held predecessor lock');
 await delay(20);
}
assert.ok(lockProof,'Actual predecessor advisory wait was not observed');
// Match the observed lock to PostgreSQL's actual encoding of the existing key.
const keyIdentity=(await observer.query("select ((hashtextextended($1,0)>>32)&4294967295)::text classid,(hashtextextended($1,0)&4294967295)::text objid,1 objsubid",[key])).rows[0];
assert.equal(lockProof.pairs[0].classid,keyIdentity.classid);assert.equal(lockProof.pairs[0].objid,keyIdentity.objid);assert.equal(lockProof.pairs[0].objsubid,keyIdentity.objsubid);
const attempt=db.exec(forward).catch(async error=>{await db.exec('rollback');throw error;});
installTask=watch(attempt);
let installerObserved=null;
for(let n=0;n<50;n++){
 const state=await monitor(installerPid);
 if(installTask.done){installerObserved={type:'completed',state};break;}
 if(state?.wait_event_type==='Lock'){installerObserved={type:'lock_wait',state};break;}
 await delay(20);
}
const beforeReleaseCatalog=await readCatalog();const catalogBeforeRelease=catalogClass(beforeReleaseCatalog);
assert.notEqual(catalogBeforeRelease,'unresolved','No success inference from an unresolved catalog');
const oldStillBlocked=await monitor(oldIdentity.pid);
assert.equal(oldTask.done,false);assert.equal(oldStillBlocked.wait_event_type,'Lock');assert.ok(oldStillBlocked.blockers.includes(holderPid));
const installedBeforeOldRelease=catalogBeforeRelease==='exact_after13';
await holder.exec('rollback');holderHeld=false;
const oldOutcome=await bounded(oldTask.result);
let oldCommitAck=false;
const catalogBeforeOldCommit=catalogClass(await readCatalog());
const installerBeforeOldCommit=await monitor(installerPid);
const installerHeldByOldTransaction=installerBeforeOldCommit?.wait_event_type==='Lock'&&installerBeforeOldCommit.blockers.includes(oldIdentity.pid);
if(oldOutcome.ok){await oldCaller.exec('commit');oldTx=false;oldCommitAck=true;}
else {await oldCaller.exec('rollback');oldTx=false;assert.ok(['40P01','55P03','57014'].includes(oldOutcome.code));}
const installOutcome=await bounded(installTask.result);
if(!installOutcome.ok)assert.ok(['40P01','55P03','57014'].includes(installOutcome.code),'Unexpected installer failure');
const finalCatalog=await readCatalog();const finalCatalogClass=catalogClass(finalCatalog);
if(installOutcome.ok){
 assert.equal(finalCatalogClass,'exact_after13');
 const results=Array.isArray(installOutcome.value)?installOutcome.value:[installOutcome.value];
 assert.ok(results.some(r=>r.rows?.length===18&&r.rows.every(x=>x.attributes&&x.source_md5)));
 for(const want of captured.filter(x=>['is_current_user_master_admin','require_reauthentication_session','consume_reauthentication_proof','account_access_allowed','set_master_feature_enabled'].includes(x.name))){
  const actual=finalCatalog.find(x=>signature(x)===signature(want));assert.deepEqual(actual.attributes,want.attributes);assert.equal(actual.definition,want.definition);
 }
}else{
 assert.equal(finalCatalogClass,'exact_before10');
 assert.deepEqual(finalCatalog,baselineCatalog,'Controlled installer failure must roll back the complete public/private function catalog');
 assert.equal(finalCatalog.some(x=>x.schema==='private'&&['save_trade_document_before_confirmed_terms','save_trade_document_before_form_fields','validate_trade_document_form_fields'].includes(x.name)),false);
 const table=(await observer.query("select to_jsonb(c) attrs from pg_class c where c.oid='private.master_feature_settings'::regclass")).rows[0].attrs;
 const constraints=(await observer.query("select to_jsonb(c) attributes,pg_get_constraintdef(c.oid) definition from pg_constraint c where c.conrelid='private.master_feature_settings'::regclass order by c.oid")).rows;
 assert.deepEqual(table,hubBefore.table);assert.deepEqual(constraints,hubBefore.constraints);
 assert.deepEqual(await masterShape(),masterBefore);
}
assert.deepEqual(await callers(),callersBefore);
assert.deepEqual((await oldCaller.query('select pg_backend_pid() pid,current_user role')).rows[0],oldIdentity);
const rowsAfter=await rowSnapshot();
for(const [table,rows] of Object.entries(rowBefore))if(table!=='private.trade_document_attachments')assert.deepEqual(rowsAfter[table],rows);
const stored=rowsAfter['private.trade_document_attachments'];
if(oldCommitAck){assert.equal(stored.length,1);assert.equal(stored[0].version,1);assert.equal(stored[0].payload.form_fields.payment_day,32);assert.deepEqual(stored[0].payload.contract_terms,reference);}
else assert.deepEqual(stored,rowBefore['private.trade_document_attachments']);
let classification;
if(!installOutcome.ok)classification='C_attempt_failed_and_rolled_back';
else if(installedBeforeOldRelease)classification=oldCommitAck?'C_committed_while_old_statement_waited_then_old_committed':'C_committed_while_old_statement_waited_then_old_failed';
else if(catalogBeforeOldCommit==='exact_after13')classification=oldCommitAck?'C_committed_before_old_transaction_commit':'C_committed_before_old_transaction_rollback';
else if(installerHeldByOldTransaction)classification=oldCommitAck?'C_waited_until_old_transaction_commit':'C_waited_until_old_transaction_rollback';
else throw Error('Exact commit ordering remains unresolved; no successful observation receipt');
report={contract:'sko.actual_C_old_inflight.v1',classification,installer_observation_before_holder_release:installerObserved,
 catalog_before_holder_release:catalogBeforeRelease,final_catalog:finalCatalogClass,
 catalog_before_old_transaction_end:catalogBeforeOldCommit,installer_blocked_by_old_transaction_after_statement:installerHeldByOldTransaction,
 existing_predecessor_advisory_wait:{observed:true,key_identity:keyIdentity,blocker_verified:true},
 source_asserted_old_lock_precedes_company_guard:true,old_saver_source_md5:predecessor.source_md5,old_statement:{ok:oldOutcome.ok,code:oldOutcome.code??null,message:oldOutcome.message??null},
 old_commit_ack_observed:oldCommitAck,old_invalid_form_commit_observed:oldCommitAck,
 installer:{ok:installOutcome.ok,code:installOutcome.code??null,message:installOutcome.message??null},
 server_version_num:170006,explicit_after13_comparisons:installOutcome.ok?13:0,expected_catalog_contract_and_unrelated_rows_preserved:true,old_caller_backend_role_unchanged:true,
 admitted_old_transaction_commit_after_C_observed:(installedBeforeOldRelease||catalogBeforeOldCommit==='exact_after13')&&oldCommitAck,
 unknown_intermediate_result_is_success:false,old_restore_executed:false,warmed1722_reexecuted:false,generic1711_executed:false,
 fixture_authentication_synthetic:true,real_GoTrue:false,actual_production_drain_proven:false,production:false,deployable:false};
} finally {
 let cleanupFailures=0;
 if(holderHeld&&holder){try{await holder.exec('rollback');holderHeld=false;}catch(e){cleanupFailures++;}}
 if(oldTask){try{await bounded(oldTask.result);}catch(e){cleanupFailures++;}}
 if(oldTx&&oldCaller){try{await oldCaller.exec('rollback');oldTx=false;}catch(e){cleanupFailures++;}}
 if(installTask){try{await bounded(installTask.result);}catch(e){cleanupFailures++;}}
 if(db){try{await db.exec('rollback');}catch(e){cleanupFailures++;}}
 for(const client of clients.reverse()){
  let timer;try{await Promise.race([client.end(),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('bounded close timeout')),4000);})]);closed++;}
  catch(e){cleanupFailures++;}finally{clearTimeout(timer);}
 }
 assert.equal(cleanupFailures,0);assert.equal(closed,clients.length);
}
report.connections={allocated:clients.length,opened,closed};
await fs.writeFile('__PROOF__',JSON.stringify(report,null,2),{flag:'wx',mode:0o600});
console.log(JSON.stringify(report));
'''.replace('__PROOF__',(out/'inflight-proof.json').as_posix())
    content=prefix+runtime
    if any(x in content for x in ['sko_cached_save','stoppedRestore','sko.function_restore_writers_stopped']):
        raise ValueError('Frozen warmed/restore schedule must not execute')
    target=out/'actual-inflight.mjs'
    with os.fdopen(os.open(target,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600),'w') as f:
        f.write(content)
    if sha(cached)!=CACHED_SHA or sha(cached.parent/'verify_expected_capture.py')!=HELPER_SHA:
        raise ValueError('Frozen generator changed during preparation')
    print(json.dumps({'generated':True,'frozen_cached_generator_sha256':CACHED_SHA,
      'prefix_boundary':BOUNDARY,'prefix_sha256':hashlib.sha256(prefix.encode()).hexdigest(),
      'raw_frozen_prefix_sha256':hashlib.sha256(raw_prefix.encode()).hexdigest(),'one_controlled_prefix_change':True,
      'warm_tail_excluded':True,'restore_excluded':True,'source_only':True,'production':False,'deployable':False}))

if __name__=='__main__':
    main()
