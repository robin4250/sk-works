// Synthetic bootstrap only. This is not Native concurrency or SDK/UI evidence.
import fs from 'node:fs';
import path from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
const dir=path.dirname(fileURLToPath(import.meta.url));
if(process.env.SKO_PERSONNEL_FIXTURE_URL){const u=new URL(process.env.SKO_PERSONNEL_FIXTURE_URL);if(!['127.0.0.1','localhost'].includes(u.hostname)||u.port!=='5432'||u.pathname!=='/sko_personnel_fixture'||u.username!=='postgres'||u.password!=='fixture-only'||u.search||u.hash)throw Error('Dedicated disposable Native17 fixture only');}
const foundation=path.resolve(dir,'../personnel_write/verify.mjs');
const original=fs.readFileSync(foundation,'utf8');
if(createHash('sha256').update(original).digest('hex')!=='ca2b9dce79a4f54ae6066d9aeae4b41b63f8342fde6e1b64a05ad8229e54d426')throw Error('Personnel foundation drift');
if(original.split('const baseline=await capsule();').length!==2)throw Error('Bootstrap cutoff drift');
let source=original.split('const baseline=await capsule();')[0];
source=source.replace('const here=path.dirname(fileURLToPath(import.meta.url));','const here='+JSON.stringify(path.dirname(foundation))+';');
source += `
await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261016120458_personnel_write_permission_guard.sql'),'utf8'));
await db.exec(fs.readFileSync(${JSON.stringify(path.resolve(dir,'../../../docs/review/personnel-birthday-cas-v2/install.wip.sql.review-only'))},'utf8'));
const payload=async()=> (await db.query('select private.worker_personnel_payload($1) p',[W])).rows[0].p;
const nonDob=async()=>({profile:(await db.query("select to_jsonb(p)-array['birth_date','updated_by','updated_at'] p from worker_personnel_profiles p where worker_id=$1",[W])).rows,family:(await db.query('select to_jsonb(f) f from worker_family_members f where worker_id=$1 order by id',[W])).rows,worker:(await db.query('select to_jsonb(w) w from workers w where id=$1',[W])).rows});
const p=await payload();
assert.equal(p.birth_date_contract_version,2);
const envelope={version:2,worker_id:W,company_id:C,expected_birth_date:p.birth_date,expected_personnel_digest:p.personnel_cas_digest};
const narrow={birth_date:'1980-01-02',_birth_date_mode:'only',_birth_date_cas:envelope};
const before=await nonDob();
await actor(actors.owner);
assert.equal((await db.query('select public.save_worker_personnel_profile($1,$2) r',[W,narrow])).rows[0].r.status,'saved');
await db.exec('reset role');
assert.deepEqual(await nonDob(),before,'narrow birthday preserves family IDs and all nonDOB fields');
assert.equal((await payload()).birth_date,'1980-01-02');
await actor(actors.owner);
await assert.rejects(db.query('select public.save_worker_personnel_profile($1,$2)',[W,narrow]),e=>e.code==='40001');
await assert.rejects(db.query('select public.save_worker_personnel_profile($1,$2)',[W,{birth_date:'1970-01-01'}]),e=>e.code==='22023');
await assert.rejects(db.query('select private.apply_worker_personnel_payload($1,$2,$3)',[W,narrow,actors.owner]),e=>e.code==='42501');
await db.exec('reset role');
assert.deepEqual(await nonDob(),before);
const current=await payload();
const legacyPayload={...current,address:'legitimate legacy nonDOB'};delete legacyPayload.birth_date;
await actor(actors.owner);
assert.equal((await db.query('select public.save_worker_personnel_profile($1,$2) r',[W,legacyPayload])).rows[0].r.status,'saved');
await db.exec('reset role');
assert.equal((await payload()).birth_date,'1980-01-02','legacy omitted date preserves DOB');
const afterLegacy=await payload();
const pendingPayload={birth_date:'1981-02-03',_birth_date_mode:'only',_birth_date_cas:{version:2,worker_id:W,company_id:C,expected_birth_date:afterLegacy.birth_date,expected_personnel_digest:afterLegacy.personnel_cas_digest}};
await actor(actors.self);
const pending=(await db.query('select public.save_worker_personnel_profile($1,$2) r',[W,pendingPayload])).rows[0].r;
assert.equal(pending.status,'pending');
await db.exec('reset role');
await db.query("update worker_personnel_profiles set birth_date='1982-03-04' where worker_id=$1",[W]);
await actor(actors.owner);
await assert.rejects(db.query('select public.decide_worker_personnel_change($1,true)',[pending.request_id]),e=>e.code==='40001');
await db.exec('reset role');
assert.equal((await db.query('select status from worker_personnel_change_requests where id=$1',[pending.request_id])).rows[0].status,'pending');
assert.equal((await db.query('select count(*)::int n from worker_personnel_change_approvals where request_id=$1',[pending.request_id])).rows[0].n,0);
if(process.env.SKO_PERSONNEL_FIXTURE_URL){
 const pg=(await import(pathToFileURL(path.join(root,'tool/security/fixture_dependencies/node_modules/pg/lib/index.js')).href)).default;
 const second=new pg.Client({connectionString:process.env.SKO_PERSONNEL_FIXTURE_URL});
 const third=new pg.Client({connectionString:process.env.SKO_PERSONNEL_FIXTURE_URL});
 await second.connect();await third.connect();
 for(const c of [second,third])await c.query("set statement_timeout='8s';set deadlock_timeout='200ms'");
 const pid=async c=>(await c.query('select pg_backend_pid() p')).rows[0].p;
 const pidB=await pid(second),pidC=await pid(third);
 const beginActor=async(c,who)=>{await c.query('begin');await c.query("select set_config('fixture.actor',$1,false)",[who]);await c.query('set role authenticated');};
 const settled=p=>p.then(value=>({value}),error=>({error}));
 const waitAdvisory=async backend=>{for(let i=0;i<40;i++){
   const row=(await db.query('select wait_event_type,wait_event from pg_stat_activity where pid=$1',[backend])).rows[0];
   if(row?.wait_event_type==='Lock'&&row?.wait_event==='advisory')return;
   await new Promise(resolve=>setTimeout(resolve,25));
 }throw Error('Expected actual second-connection advisory wait');};
 const wire=(snapshot,date)=>({birth_date:date,_birth_date_mode:'only',_birth_date_cas:{version:2,worker_id:W,company_id:C,expected_birth_date:snapshot.birth_date,expected_personnel_digest:snapshot.personnel_cas_digest}});
 try{
  // Same original read; second operation is an old-value no-op without CAS.
  const snapshot=await payload();const preserved=await nonDob();
  await db.exec('begin');await actor(actors.owner);
  await db.query('select public.save_worker_personnel_profile($1,$2)',[W,wire(snapshot,'1990-01-01')]);
  await db.exec('reset role');
  await beginActor(second,actors.owner);
  const stale=settled(second.query('select public.save_worker_personnel_profile($1,$2)',[W,wire(snapshot,snapshot.birth_date)]));
  await waitAdvisory(pidB);await db.exec('commit');
  assert.equal((await stale).error?.code,'40001');await second.query('rollback');
  assert.deepEqual(await nonDob(),preserved);

  // Phantom schedule: pending insert owns gate; another save waits before
  // scanning/rejecting requests; approval then waits on the same gate, not a
  // request row. This cannot form the former request->worker cycle.
  const phase=await payload();
  await db.exec('begin');await actor(actors.self);
  const request=(await db.query('select public.save_worker_personnel_profile($1,$2) r',[W,wire(phase,'1991-01-01')])).rows[0].r;
  assert.equal(request.status,'pending');await db.exec('reset role');
  await beginActor(second,actors.owner);
  const replacing=settled(second.query('select public.save_worker_personnel_profile($1,$2) r',[W,wire(phase,'1992-01-01')]));
  await waitAdvisory(pidB);await db.exec('commit');
  assert.equal((await replacing).value.rows[0].r.status,'saved');
  await beginActor(third,actors.owner);
  const approval=settled(third.query('select public.decide_worker_personnel_change($1,true)',[request.request_id]));
  await waitAdvisory(pidC);await second.query('commit');
  assert.equal((await approval).error?.code,'P0001');await third.query('rollback');
  assert.equal((await db.query('select status from worker_personnel_change_requests where id=$1',[request.request_id])).rows[0].status,'rejected');

  // Authority was valid before waiting; revocation while blocked must win.
  const revocation=await payload(),preRevocation=await nonDob();
  await db.exec('begin');
  await db.query("select pg_advisory_xact_lock(hashtextextended('sko:personnel-dob-v2:' || $1::text,0))",[W]);
  await beginActor(second,actors.managerOn);
  const revoked=settled(second.query('select public.save_worker_personnel_profile($1,$2)',[W,wire(revocation,'1993-01-01')]));
  await waitAdvisory(pidB);
  await db.query('update member_feature_permissions set can_manage_people=false where company_id=$1 and user_id=$2',[C,actors.managerOn]);
  await db.exec('commit');assert.equal((await revoked).error?.code,'42501');await second.query('rollback');
  assert.deepEqual(await nonDob(),preRevocation);
  await db.query('update member_feature_permissions set can_manage_people=true where company_id=$1 and user_id=$2',[C,actors.managerOn]);
  console.log('PASS Native17 actual advisory waits: stale no-op CAS, phantom pending/save/approval cycle, and authority revocation after wait');
 }finally{
  await db.exec('rollback');for(const c of [second,third]){await c.query('rollback');await c.end();}
 }
}

await db.close();
console.log('PASS 9 synthetic compiler/narrow/conflict/legacy/ACL/preservation/pending/approval-CAS/rollback cases; Native concurrency and UI remain unverified');
`;
const folder=fs.mkdtempSync(path.join(tmpdir(),'sko-dob-v2-'));const output=path.join(folder,'smoke.mjs');fs.writeFileSync(output,source);
await import('node:child_process').then(({spawnSync})=>{const r=spawnSync(process.execPath,[output,process.argv[2]],{stdio:'inherit'});process.exitCode=r.status??1;fs.rmSync(folder,{recursive:true,force:true});});
