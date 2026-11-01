"""One disposable existing public ACL pause observation. Never a live installer."""
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
    ownership="""let db;
try {"""
    if prefix.count(ownership)!=1:
        raise ValueError('Frozen connection ownership anchor differs')
    # Variables must be visible to finally even when a connection/setup fails.
    replacement='let db,holder,active,observer,aclTask,activeTask;let held=false,paused=false;\ntry {'
    prefix=prefix.replace(ownership,replacement)
    if prefix.replace(replacement,ownership)!=raw_prefix:
        raise ValueError('Only declared resource ownership differs')
    runtime=r'''
const signature='public.save_trade_document_attachment(text,uuid,text,integer,jsonb)';
const publicSQL="select public.save_trade_document_attachment('payment_certificate',$1,'1',0,$2::jsonb) v";
const privateSQL=publicSQL.replace('public.save_','private.save_');
const literal=s=>"'"+String(s).replaceAll("'","''")+"'";
const actor=async(c,role='authenticated')=>{
 assert.ok(['authenticated','postgres'].includes(role));await c.exec('set role '+role);
 await c.query("select set_config('test.uid',$1,false),set_config('request.jwt.claims',$2,false)",[admin,JSON.stringify({sub:admin,session_id:session,role:'authenticated',is_anonymous:false})]);
};
const catalog=async()=> (await db.query("select n.nspname,p.proname,pg_get_functiondef(p.oid) definition,to_jsonb(p) attrs from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') order by p.oid")).rows;
const namespaces=async()=> (await db.query("select to_jsonb(n) attrs from pg_namespace n where nspname in ('public','private','auth') order by oid")).rows;
const baseline=await catalog(),namespaceBefore=await namespaces();
const target=baseline.find(x=>x.nspname==='public'&&x.proname==='save_trade_document_attachment');
assert.equal(createHash('md5').update(target.attrs.prosrc).digest('hex'),'3121ba766b2be6fa5713e27b2c2d4254');
assert.deepEqual(target.attrs.proacl,['postgres=X/postgres','authenticated=X/postgres']);
const usage=(await db.query("select has_schema_privilege('authenticated','public','USAGE') public_usage,has_schema_privilege('authenticated','private','USAGE') private_usage,has_function_privilege('authenticated','private.save_trade_document_attachment(text,uuid,text,integer,jsonb)','EXECUTE') private_execute")).rows[0];
assert.deepEqual(usage,{public_usage:true,private_usage:true,private_execute:true});
assert.equal((await db.query('show server_version_num')).rows[0].server_version_num,'170006');
const auth=await connect();await actor(auth);
const work=(await auth.query("select public.trade_document_attachment_workspace('payment_certificate',$1,'1') v",[document])).rows[0].v;
const payload={...work.defaults,issue_date:'2026-09-15',work_name:'ACL fixture',work_address:'Fixture',intro_text:'Explicit order',payment_conditions:'Explicit payment',notes:'',contract_terms:reference,form_fields:fresh()};
const modes=['plain','custom','generic'];
const plan=async(c,m)=>{assert.ok(modes.includes(m));await c.exec('set plan_cache_mode='+({plain:'auto',custom:'force_custom_plan',generic:'force_generic_plan'}[m]));};
const prepare=async c=>c.exec('prepare acl_pause_save(uuid,jsonb) as '+publicSQL);
const call=async(c,m,sql=publicSQL)=>{
 await plan(c,m);
 return m==='plain'?c.query(sql,[document,JSON.stringify(payload)]):c.query('execute acl_pause_save('+literal(document)+','+literal(JSON.stringify(payload))+'::jsonb)');
};
const attempt=async(c,m,inside=false,sql=publicSQL)=>{
 if(inside)await c.exec('savepoint acl_case');else await c.exec('begin');
 try{const value=await call(c,m,sql);return {accepted:true,version:value.rows[0].v.version};}
 catch(e){return {accepted:false,code:e.code,message:e.message};}
 finally{await c.exec(inside?'rollback to savepoint acl_case':'rollback');if(inside)await c.exec('release savepoint acl_case');}
};
await prepare(auth);
for(const mode of modes)assert.equal((await attempt(auth,mode)).accepted,true);
const idle=[];
for(const isolation of ['read committed','repeatable read']){
 const c=await connect();await actor(c);await prepare(c);await c.exec('begin isolation level '+isolation);
 // Establish the pre-close snapshot and warm each plan, retaining this transaction.
 for(const mode of modes)assert.equal((await attempt(c,mode,true)).accepted,true);
 idle.push({c,isolation,pid:(await c.query('select pg_backend_pid() pid')).rows[0].pid});
}
assert.deepEqual(await rowSnapshot(),beforeRows);
holder=await connect();active=await connect();observer=await connect();await actor(active);
const key='trade-appendix:payment_certificate:'+document;
const holderPID=(await holder.query('select pg_backend_pid() pid')).rows[0].pid;
const activePID=(await active.query('select pg_backend_pid() pid')).rows[0].pid;
const dbPID=(await db.query('select pg_backend_pid() pid')).rows[0].pid;
const watch=p=>{const t={done:false};t.result=p.then(v=>({ok:true,value:v}),e=>({ok:false,code:e.code,message:e.message})).then(v=>{t.done=true;t.value=v;return v;});return t;};
const wait=ms=>new Promise(r=>setTimeout(r,ms));
const state=async pid=>(await observer.query('select state,wait_event_type,pg_blocking_pids(pid) blockers from pg_stat_activity where pid=$1',[pid])).rows[0];
await holder.exec('begin');held=true;await holder.query('select pg_advisory_xact_lock(hashtextextended($1,0))',[key]);
await active.exec('begin');activeTask=watch(active.query(publicSQL,[document,JSON.stringify(payload)]));
let lockProof;
for(let n=0;n<75;n++){
 const s=await state(activePID);
 const p=(await observer.query("select w.classid::text,w.objid::text,w.objsubid from pg_locks w join pg_locks h on h.locktype=w.locktype and h.database is not distinct from w.database and h.classid=w.classid and h.objid=w.objid and h.objsubid=w.objsubid where w.pid=$1 and h.pid=$2 and w.locktype='advisory' and not w.granted and h.granted",[activePID,holderPID])).rows;
 if(s?.wait_event_type==='Lock'&&s.blockers.includes(holderPID)&&p.length===1){lockProof={state:s,identity:p[0]};break;}
 assert.equal(activeTask.done,false);await wait(20);
}
assert.ok(lockProof);
const keyIdentity=(await observer.query("select ((hashtextextended($1,0)>>32)&4294967295)::text classid,(hashtextextended($1,0)&4294967295)::text objid,1 objsubid",[key])).rows[0];
assert.deepEqual(lockProof.identity,keyIdentity);
aclTask=watch(db.exec('revoke execute on function '+signature+' from authenticated'));
let aclOrder='unobserved';
for(let n=0;n<75;n++){
 if(aclTask.done){aclOrder='acl_settled_before_active_release';break;}
 const s=await state(dbPID);if(s?.wait_event_type==='Lock'){aclOrder='acl_waited_before_active_release';break;}
 await wait(20);
}
assert.notEqual(aclOrder,'unobserved');
const activeBeforeRelease=await state(activePID);assert.equal(activeTask.done,false);assert.ok(activeBeforeRelease.blockers.includes(holderPID));
await holder.exec('rollback');held=false;
const activeOutcome=await activeTask.result;await active.exec('rollback');
const aclOutcome=await aclTask.result;
assert.equal(aclOutcome.ok,true,'Unexpected ACL failure must not masquerade as a closed ingress');paused=true;
const closedCatalog=await catalog();
assert.deepEqual(closedCatalog.map(x=>x.attrs.oid===target.attrs.oid?{...x,attrs:{...x.attrs,proacl:target.attrs.proacl}}:x),baseline);
assert.deepEqual(closedCatalog.find(x=>x.attrs.oid===target.attrs.oid).attrs.proacl,['postgres=X/postgres']);
assert.deepEqual(await namespaces(),namespaceBefore);assert.deepEqual(await rowSnapshot(),beforeRows);
const observations=[];
for(const mode of modes)observations.push({connection:'warmed',mode,...await attempt(auth,mode)});
for(const item of idle){
 assert.equal((await item.c.query('select pg_backend_pid() pid')).rows[0].pid,item.pid);
 for(const mode of modes)observations.push({connection:'preclose_idle_transaction',isolation:item.isolation,mode,...await attempt(item.c,mode,true)});
 await item.c.exec('rollback');
}
const freshAuth=await connect();await actor(freshAuth);await prepare(freshAuth);
for(const mode of modes)observations.push({connection:'fresh',mode,...await attempt(freshAuth,mode)});
// Record counterexamples, rather than asserting that REVOKE retroactively cancels entry.
const deniedMessage='permission denied for function save_trade_document_attachment';
for(const x of observations)if(!x.accepted){
 assert.equal(x.code,'42501','Unrelated failure is not ACL closure evidence');
 assert.equal(x.message,deniedMessage,'Another permission failure is not public saver closure evidence');
}
let activeClassification;
if(activeOutcome.ok)activeClassification='entered_call_accepted';
else if(activeOutcome.code==='42501'&&activeOutcome.message===deniedMessage)activeClassification='public_saver_acl_denied';
else if(['55P03','57014'].includes(activeOutcome.code))activeClassification='controlled_wait_timeout_not_closure';
else throw Error('Unclassified entered-call outcome: '+JSON.stringify(activeOutcome));
const privateControl=await attempt(auth,'plain',false,privateSQL);assert.equal(privateControl.accepted,true);
const owner=await connect();await actor(owner,'postgres');const ownerControl=await attempt(owner,'plain');assert.equal(ownerControl.accepted,true);
const planCounters=(await auth.query("select name,generic_plans::text,custom_plans::text from pg_prepared_statements where name='acl_pause_save'")).rows;
assert.equal(planCounters.length,1);assert.ok(Number(planCounters[0].generic_plans)>=1);assert.ok(Number(planCounters[0].custom_plans)>=1);
await db.exec('grant execute on function '+signature+' to authenticated');paused=false;
assert.deepEqual(await catalog(),baseline);assert.deepEqual(await namespaces(),namespaceBefore);assert.deepEqual(await rowSnapshot(),beforeRows);
for(const mode of modes){assert.equal((await attempt(auth,mode)).accepted,true);assert.equal((await attempt(freshAuth,mode)).accepted,true);}
assert.deepEqual(await rowSnapshot(),beforeRows);
report={kind:'existing_public_acl_pause_fixture',public_signature:signature,limited_authenticated_usage_alignment:usage,observations,planCounters,acl_order:aclOrder,active_call_classification:activeClassification,active_call:activeOutcome.ok?{accepted:true,version:activeOutcome.value.rows[0].v.version}:{accepted:false,code:activeOutcome.code,message:activeOutcome.message},
 existing_key_wait_observed:true,acl_exactly_restored:true,all_other_function_attributes_unchanged:true,namespaces_unchanged:true,rows_unchanged:true,
 private_authenticated_control:privateControl,owner_control:ownerControl,fixture_authentication_synthetic:true,fixture_full_production_schema_acl_reproduced:false,
 actual_C_executed:false,prior_warm_tail_executed:false,restore_executed:false,actual_PLpgSQL_writer_proven:false,real_GoTrue:false,C_commit_barrier_proven:false,production:false,deployable:false};
} finally {
 let failures=0;
 if(held&&holder){try{await holder.exec('rollback');}catch(e){failures++;}}
 if(activeTask){try{await activeTask.result;}catch(e){failures++;}}
 if(active){try{await active.exec('rollback');}catch(e){failures++;}}
 if(aclTask){try{await aclTask.result;}catch(e){failures++;}}
 if(paused&&db){try{await db.exec('grant execute on function public.save_trade_document_attachment(text,uuid,text,integer,jsonb) to authenticated');}catch(e){failures++;}}
 for(const client of clients.reverse()){
  let timer;try{await Promise.race([client.end(),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('Close timeout')),4000);})]);closed++;}
  catch(e){failures++;}finally{clearTimeout(timer);}
 }
 assert.equal(failures,0);assert.equal(closed,clients.length);
}
report.connections={allocated:clients.length,opened,closed};
await fs.writeFile('__PROOF__',JSON.stringify(report,null,2),{flag:'wx',mode:0o600});console.log(JSON.stringify(report));
'''.replace('__PROOF__',(out/'acl-pause-proof.json').as_posix())
    content=prefix+runtime
    if any(x in content for x in ['db.exec(forward)','sko_cached_save','stoppedRestore','sko.function_restore_writers_stopped']):
        raise ValueError('Actual C, prior warmed tail, or restore must not execute')
    target=out/'existing-acl-pause.mjs'
    with os.fdopen(os.open(target,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600),'w') as f:
        f.write(content)
    if sha(cached)!=CACHED_SHA or sha(cached.parent/'verify_expected_capture.py')!=HELPER_SHA:
        raise ValueError('Frozen producer drift')
    print(json.dumps({'generated':True,'raw_prefix_sha256':hashlib.sha256(raw_prefix.encode()).hexdigest(),
      'prefix_sha256':hashlib.sha256(prefix.encode()).hexdigest(),'one_controlled_prefix_change':True,
      'C_executed':False,'old_warm_tail_excluded':True,'restore_excluded':True,'production':False,'deployable':False}))

if __name__=='__main__':
    main()
