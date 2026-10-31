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
// Synthetic bank preservation projection only; not banking authorization evidence.
await db.exec("create table public.worker_private_bank_accounts(worker_id uuid primary key,company_id uuid not null,bank_name text not null,branch_name text not null,account_type text not null,account_number text not null,account_holder text not null,updated_at timestamptz not null);alter table public.worker_private_bank_accounts enable row level security;revoke all on public.worker_private_bank_accounts from public,anon,authenticated,service_role");
await db.query("insert into public.worker_private_bank_accounts values($1,$2,'Synthetic bank','Synthetic branch','普通','1234567','SYNTHETIC HOLDER','2026-01-01T00:00:00Z')",[W,C]);
const casInstall=fs.readFileSync(${JSON.stringify(path.resolve(dir,'../../../docs/review/personnel-birthday-cas-v2/install.wip.sql.review-only'))},'utf8');
const casState=async()=>({capsule:await capsule(),bank:(await db.query('select to_jsonb(b) b from worker_private_bank_accounts b order by worker_id')).rows,
 column:(await db.query("select attname,atttypid::regtype::text type,attnotnull from pg_attribute where attrelid='public.worker_personnel_profiles'::regclass and attname='birth_date' and not attisdropped")).rows,
 extraSchema:(await db.query("select count(*)::int n from pg_namespace where nspname='cas_unknown'")).rows,
 extraRole:(await db.query("select count(*)::int n from pg_roles where rolname='cas_unknown_role'")).rows});
const casBefore=await casState();
const firstGuard='do $catalog_guard$';
const injectFirst=prefix=>casInstall.replace(firstGuard,()=>prefix+'\\n'+firstGuard);
async function fault(sql,code,label){
 await assert.rejects(db.exec(sql),error=>error.code===code);
 await db.exec('rollback');assert.deepEqual(await casState(),casBefore,label);
}
const middle=casInstall.indexOf('create or replace function private.apply_worker_personnel_payload');assert.ok(middle>0);
const failure="do $$begin raise sqlstate 'P0001' using message='synthetic_midinstall_failure';end$$;";
await fault(casInstall.slice(0,middle)+failure+casInstall.slice(middle),'P0001','column and first function roll back with all original metadata/rows');
const finalGuard=casInstall.lastIndexOf(firstGuard);assert.ok(finalGuard>middle);
await fault(casInstall.slice(0,finalGuard)+"create role cas_unknown_role;grant execute on function private.apply_worker_personnel_payload(uuid,jsonb,uuid) to cas_unknown_role;"+casInstall.slice(finalGuard),'55000','unknown final ACL and role roll back all five functions/column/rows');
await fault(injectFirst('grant execute on function private.apply_worker_personnel_payload(uuid,jsonb,uuid) to authenticated with grant option;'),'55000','unexpected original grant option rejects atomically');
const staticCaller="create schema cas_unknown;create function cas_unknown.call_apply(p_worker uuid,p_data jsonb,p_actor uuid) returns void language plpgsql security invoker set search_path='' as $$begin perform PRIVATE.APPLY_WORKER_PERSONNEL_PAYLOAD(p_worker,p_data,p_actor);end$$;";
await fault(injectFirst(staticCaller),'55000','case-insensitive caller outside public/private rejects atomically');
const parsedCaller="create schema cas_unknown;create function cas_unknown.call_apply(p_worker uuid,p_data jsonb,p_actor uuid) returns void language sql begin atomic select private.apply_worker_personnel_payload(p_worker,p_data,p_actor);end;do $$begin if not exists(select 1 from pg_depend d where d.classid='pg_proc'::regclass and d.objid=to_regprocedure('cas_unknown.call_apply(uuid,jsonb,uuid)') and d.refclassid='pg_proc'::regclass and d.refobjid=to_regprocedure('private.apply_worker_personnel_payload(uuid,jsonb,uuid)')) then raise sqlstate 'P0001' using message='parsed_function_dependency_missing';end if;end$$;";
await fault(injectFirst(parsedCaller),'55000','parsed-body dependency outside canonical callers rejects atomically');
if(process.env.SKO_PERSONNEL_FIXTURE_URL){
 const guardPg=(await import(pathToFileURL(path.join(root,'tool/security/fixture_dependencies/node_modules/pg/lib/index.js')).href)).default;
 const catalogObserver=new guardPg.Client({connectionString:process.env.SKO_PERSONNEL_FIXTURE_URL});await catalogObserver.connect();await catalogObserver.query("set statement_timeout='3s'");
 const catalog=async client=>({functions:(await client.query("select p.oid::regprocedure::text signature,md5(p.prosrc) hash,p.proacl::text acl from pg_proc p where p.oid=any($1::regprocedure[]) order by 1",[['private.worker_personnel_payload(uuid)','private.apply_worker_personnel_payload(uuid,jsonb,uuid)','private.employee_personnel_view(uuid)','public.save_worker_personnel_profile(uuid,jsonb)','public.decide_worker_personnel_change(uuid,boolean)']])).rows,
  column:(await client.query("select attname from pg_attribute where attrelid='public.worker_personnel_profiles'::regclass and attname='birth_date' and not attisdropped")).rows});
 try{
  const before=await catalog(catalogObserver);
  await db.exec(casInstall.slice(0,middle));
  assert.deepEqual(await catalog(catalogObserver),before,'other connection cannot see intermediate column/new reader');
  await assert.rejects(db.exec(failure+casInstall.slice(middle)),error=>error.code==='P0001');await db.exec('rollback');
  assert.deepEqual(await catalog(catalogObserver),before);assert.deepEqual(await casState(),casBefore);
  console.log('PASS Native second observer sees no partial five-function publication');
 }finally{await db.exec('rollback');await catalogObserver.end();}
}
console.log('PASS 5 injected atomic guard faults preserve original catalog/ACL/column/bank/business/identity state');
await db.exec(casInstall);

const payload=async()=> (await db.query('select private.worker_personnel_payload($1) p',[W])).rows[0].p;
const nonDob=async()=>({profile:(await db.query("select to_jsonb(p)-array['birth_date','updated_by','updated_at'] p from worker_personnel_profiles p where worker_id=$1",[W])).rows,family:(await db.query('select to_jsonb(f) f from worker_family_members f where worker_id=$1 order by id',[W])).rows,worker:(await db.query('select to_jsonb(w) w from workers w where id=$1',[W])).rows,bank:(await db.query('select to_jsonb(b) b from worker_private_bank_accounts b where worker_id=$1',[W])).rows});
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


const combinedSnapshot=await payload();
const combined={...combinedSnapshot,address:'synthetic intended address',birth_date:'1983-04-05',_birth_date_mode:'combined',
 _birth_date_cas:{version:2,worker_id:W,company_id:C,expected_birth_date:combinedSnapshot.birth_date,expected_personnel_digest:combinedSnapshot.personnel_cas_digest}};
await db.query("update worker_personnel_profiles set address='synthetic concurrent address' where worker_id=$1",[W]);
const combinedBefore=await nonDob();
await actor(actors.owner);
await assert.rejects(db.query('select public.save_worker_personnel_profile($1,$2)',[W,combined]),e=>e.code==='40001');
await db.exec('reset role');assert.deepEqual(await nonDob(),combinedBefore);
const clearSnapshot=await payload();
const clear={birth_date:null,_birth_date_mode:'only',_birth_date_cas:{version:2,worker_id:W,company_id:C,expected_birth_date:clearSnapshot.birth_date,expected_personnel_digest:clearSnapshot.personnel_cas_digest}};
const clearBefore=await nonDob();await actor(actors.owner);
assert.equal((await db.query('select public.save_worker_personnel_profile($1,$2) r',[W,clear])).rows[0].r.status,'saved');
await db.exec('reset role');assert.equal((await payload()).birth_date,null);assert.deepEqual(await nonDob(),clearBefore);
await actor(actors.owner);await assert.rejects(db.query('select public.save_worker_personnel_profile($1,$2)',[W,clear]),e=>e.code==='40001');await db.exec('reset role');
const oldPending=(await db.query("insert into worker_personnel_change_requests(company_id,worker_id,requested_by,proposed,required_approvals) values($1,$2,$3,$4,1) returning id",[C,W,actors.self,{birth_date:'1970-01-01'}])).rows[0].id;
const pendingBefore=await nonDob();await actor(actors.owner);
await assert.rejects(db.query('select public.decide_worker_personnel_change($1,true)',[oldPending]),e=>e.code==='22023');
await db.exec('reset role');assert.deepEqual(await nonDob(),pendingBefore);
assert.equal((await db.query('select status from worker_personnel_change_requests where id=$1',[oldPending])).rows[0].status,'pending');
assert.equal((await db.query('select count(*)::int n from worker_personnel_change_approvals where request_id=$1',[oldPending])).rows[0].n,0);


for (const proposed of [null,[]]) {
 const badRequest=(await db.query("insert into worker_personnel_change_requests(company_id,worker_id,requested_by,proposed,required_approvals) values($1,$2,$3,$4::jsonb,1) returning id",[C,W,actors.self,JSON.stringify(proposed)])).rows[0].id;
 const beforeMalformed=await nonDob();await actor(actors.owner);
 await assert.rejects(db.query('select public.decide_worker_personnel_change($1,true)',[badRequest]),e=>e.code==='22023');
 await db.exec('reset role');assert.deepEqual(await nonDob(),beforeMalformed);
 assert.equal((await db.query('select status from worker_personnel_change_requests where id=$1',[badRequest])).rows[0].status,'pending');
 assert.equal((await db.query('select count(*)::int n from worker_personnel_change_approvals where request_id=$1',[badRequest])).rows[0].n,0);
}

await db.close();
console.log('PASS 14 synthetic logical cases; bank/profile/family preservation, malformed-pending rollback; Native waits='+(process.env.SKO_PERSONNEL_FIXTURE_URL?'verified above':'not run')+'; real authentication/device unverified');
`;
const folder=fs.mkdtempSync(path.join(tmpdir(),'sko-dob-v2-'));const output=path.join(folder,'smoke.mjs');fs.writeFileSync(output,source);
await import('node:child_process').then(({spawnSync})=>{const r=spawnSync(process.execPath,[output,process.argv[2]],{stdio:'inherit'});process.exitCode=r.status??1;fs.rmSync(folder,{recursive:true,force:true});});
