// Appended after immutable bootstrap by verify.mjs; not a standalone module.
await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261016120458_personnel_write_permission_guard.sql'),'utf8'));
await db.exec("create table public.worker_private_bank_accounts(worker_id uuid primary key,company_id uuid,bank_name text,account_number text);alter table public.worker_private_bank_accounts enable row level security;revoke all on public.worker_private_bank_accounts from public,anon,authenticated,service_role");
await db.query("insert into worker_private_bank_accounts values($1,$2,'Synthetic bank','SYNTHETIC-ONLY')",[W,C]);
const sqlDir=path.join(stopReadyRoot,'docs/review/personnel-birthday-stop-ready');
const sql=name=>fs.readFileSync(path.join(sqlDir,name+'.sql.review-only'),'utf8');
const quiesce=sql('quiesce-before-first-dob'),ready=sql('install-first-stop-ready'),stop=sql('stop-after-ready');
const native=!!process.env.SKO_PERSONNEL_FIXTURE_URL;
const rows=async()=>{await db.exec('reset role');const c=await capsule();return {rows:c.rows,bank:(await db.query('select to_jsonb(b) b from worker_private_bank_accounts b order by worker_id')).rows};};
const state=async()=>({capsule:await capsule(),bank:(await db.query('select to_jsonb(b) b from worker_private_bank_accounts b order by worker_id')).rows,column:(await db.query("select attname from pg_attribute where attrelid='worker_personnel_profiles'::regclass and attname='birth_date' and not attisdropped")).rows,extraSchemas:(await db.query("select nspname from pg_namespace where nspname='stop_ready_unknown'")).rows,extraRoles:(await db.query("select rolname from pg_roles where rolname='stop_ready_unknown_role'")).rows});
const payload=async()=>{await db.exec('reset role');return (await db.query('select private.worker_personnel_payload($1) p',[W])).rows[0].p;};
const wire=(p,date)=>({birth_date:date,_birth_date_mode:'only',_birth_date_cas:{version:2,worker_id:W,company_id:C,expected_birth_date:p.birth_date,expected_personnel_digest:p.personnel_cas_digest}});
const plain=(p,address)=>{const result={...p,address};delete result.birth_date;delete result._birth_date_cas;delete result._birth_date_mode;return result;};
const save=async(who,data)=>{await actor(who);const r=(await db.query('select public.save_worker_personnel_profile($1,$2) r',[W,data])).rows[0].r;await db.exec('reset role');return r;};
const decide=async(id,yes)=>{await actor(actors.owner);const r=(await db.query('select public.decide_worker_personnel_change($1,$2) r',[id,yes])).rows[0].r;await db.exec('reset role');return r;};
const status=async id=>(await db.query('select status from worker_personnel_change_requests where id=$1',[id])).rows[0].status;
const deny=async(fn,code='42501')=>{await assert.rejects(fn,e=>e.code===code);await db.exec('reset role');};
const fault=async(statement,code,label)=>{await db.exec('reset role');const before=await state();await assert.rejects(db.exec(statement),e=>e.code===code);await db.exec('rollback');assert.deepEqual(await state(),before,label);};
if(stopReadyScenario==='zero-use-reopen'){
 if(native)assert.equal((await db.query("select current_setting('server_version') v")).rows[0].v.split(' ')[0],'17.6');
 const signatures=['private.worker_personnel_payload(uuid)','private.apply_worker_personnel_payload(uuid,jsonb,uuid)','private.employee_personnel_view(uuid)','public.save_worker_personnel_profile(uuid,jsonb)','public.decide_worker_personnel_change(uuid,boolean)'];
 const effectiveAcl=async()=>(await db.query("select p.oid::regprocedure::text signature,pg_get_userbyid(a.grantor) grantor,case when a.grantee=0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end grantee,a.privilege_type,a.is_grantable from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid=any($1::regprocedure[]) order by 1,2,3,4,5",[signatures])).rows;
 const physicalApplyAcl=async()=>(await db.query("select proacl::text acl from pg_proc where oid='private.apply_worker_personnel_payload(uuid,jsonb,uuid)'::regprocedure")).rows[0].acl;
 const withoutPrivateApplyPhysicalAcl=value=>({...value,capsule:{...value.capsule,functions:value.capsule.functions.map(f=>f.nspname==='private'&&f.proname==='apply_worker_personnel_payload'?{...f,proacl:null}:f)}});
 const before=await state(),rights=await effectiveAcl();assert.equal(await physicalApplyAcl(),null);assert.deepEqual(before.column,[]);
 await db.exec(quiesce);await db.exec(sql('reopen-before-dob'));
 assert.deepEqual(await effectiveAcl(),rights,'zero-use reopen restores effective grantor/grantee/privilege/grantoption rights');
 assert.notEqual(await physicalApplyAcl(),null,'private apply NULL default ACL is restored as explicit default ACL');
 assert.deepEqual(withoutPrivateApplyPhysicalAcl(await state()),withoutPrivateApplyPhysicalAcl(before),'original bodies/attributes/rows/bank/table ACLs and absent DOB column are unchanged');
 await fault(quiesce,'55000','strict original NULL ACL guard rejects a subsequent QUIESCE retry');
 assert.equal((await save(actors.owner,plain(await payload(),'synthetic reopened original nonDOB'))).status,'saved');
 assert.deepEqual((await state()).column,[]);
 console.log('PASS zero-use-reopen fresh fixture: effective ACL restored; physical private apply NULL becomes explicit default; original metadata/rows/bank/noDOB preserved; strict retry rejected; old nonDOB RPC usable');
 await db.close();process.exit(0);
}
assert.equal(stopReadyScenario,'stop');
let pg,connect;
if(native){
 pg=(await import(pathToFileURL(path.join(dependenciesRoot,'node_modules/pg/lib/index.js')).href)).default;
 connect=async()=>{const c=new pg.Client({connectionString:process.env.SKO_PERSONNEL_FIXTURE_URL});await c.connect();await c.query("set statement_timeout='15s'");return c;};
 assert.equal((await db.query("select current_setting('server_version') v")).rows[0].v.split(' ')[0],'17.6');
 const old=await connect(),admittedOld=await connect();
 try{
  await old.query('begin');await old.query("select set_config('fixture.actor',$1,false)",[actors.owner]);await old.query('set role authenticated');
  const named={name:'original-save-stop-ready',text:'select public.save_worker_personnel_profile($1,$2) r',values:[W,plain(await payload(),'synthetic old prepared')]};
  await old.query(named);await old.query('rollback');
  await admittedOld.query('begin');await admittedOld.query("select set_config('fixture.actor',$1,false)",[actors.owner]);await admittedOld.query('set role authenticated');
  await admittedOld.query({name:'active-original-save-stop-ready',text:named.text,values:[W,plain(await payload(),'synthetic admitted original')]});
  await db.exec(quiesce);
  await old.query("select set_config('fixture.actor',$1,false)",[actors.owner]);await old.query('set role authenticated');
  await assert.rejects(old.query(named),e=>e.code==='42501');await old.query('reset role');
  // Cached old writer admitted before quiescence: the open transaction is the
  // drain barrier even when no backend is actively executing its old plan.
  await fault(ready,'55000','READY refuses another active transaction without publication');
  await admittedOld.query('commit');
  if(Number((await db.query("show max_prepared_transactions")).rows[0].max_prepared_transactions)<1)throw Error('Native fixture must enable prepared transactions');
  await old.query("begin;select 1;prepare transaction 'sko_stop_ready_synthetic'");
  try{await fault(ready,'55000','READY refuses prepared transaction');}finally{await old.query("rollback prepared 'sko_stop_ready_synthetic'");}
  console.log('PASS Native original named prepared query denies after committed QUIESCE; active and prepared transactions block READY atomically');
 }finally{await old.query('rollback');await old.end();await admittedOld.query('rollback');await admittedOld.end();}
}else{
 await db.exec(quiesce);
 await actor(actors.owner);await deny(()=>db.query('select public.save_worker_personnel_profile($1,$2)',[W,{}]));
 console.log('PASS synthetic QUIESCE denies authenticated write; transaction drain and prepared-plan evidence reserved to Native');
}
await db.exec(ready);
assert.equal((await payload()).birth_date_contract_version,2);
const writerCatalog=async()=>(await db.query("select oid::regprocedure::text signature,md5(prosrc) hash,proacl::text acl,proconfig,prosecdef,provolatile from pg_proc where oid=any($1::regprocedure[]) order by 1",[['public.save_worker_personnel_profile(uuid,jsonb)','public.decide_worker_personnel_change(uuid,boolean)','private.apply_worker_personnel_payload(uuid,jsonb,uuid)']])).rows;
const readyWriters=await writerCatalog();
const original=await rows();
// Normal version 2 retains the original owner reject-all and self supersession.
let p=await payload();const self1=await save(actors.self,wire(p,'1980-01-01'));assert.equal(self1.status,'pending');
const self2=await save(actors.self,wire(p,'1981-01-01'));assert.equal(await status(self1.request_id),'rejected');assert.equal(self2.status,'pending');
assert.equal((await save(actors.owner,wire(p,'1982-01-01'))).status,'saved');assert.equal(await status(self2.request_id),'rejected');
p=await payload();const pending=await save(actors.self,wire(p,'1983-01-01'));assert.equal(pending.status,'pending');
// Persist a synthetic two-approval quorum so a single stopped approval must
// fail before recording its vote, even without reaching the apply endpoint.
await db.query('update worker_personnel_change_requests set required_approvals=2 where id=$1',[pending.request_id]);
const markerRequests=[];
for(const proposed of [{birth_date:'1970-01-01'},{_birth_date_cas:{}},{_birth_date_mode:'only'}])markerRequests.push((await db.query("insert into worker_personnel_change_requests(company_id,worker_id,requested_by,proposed,required_approvals) values($1,$2,$3,$4,1) returning id",[C,W,actors.self,proposed])).rows[0].id);
const preservedMarkers=async()=>{for(const request of markerRequests)assert.equal(await status(request),'pending','any DOB marker preserves pending after STOP');};
const dobPendingIds=[pending.request_id,...markerRequests];
const dobPendingSnapshot=async()=>({
 requests:(await db.query('select to_jsonb(r) value from worker_personnel_change_requests r where id=any($1::uuid[]) order by id',[dobPendingIds])).rows,
 approvals:(await db.query('select to_jsonb(a) value from worker_personnel_change_approvals a where request_id=any($1::uuid[]) order by request_id,approver_user_id',[dobPendingIds])).rows
});
const preservedPendingBefore=await dobPendingSnapshot();
assert.equal(preservedPendingBefore.requests.find(x=>x.value.id===pending.request_id).value.required_approvals,2);
const assertPendingUnchanged=async label=>assert.deepEqual(await dobPendingSnapshot(),preservedPendingBefore,label+' preserves complete DOB request/proposed/quorum and approval rows');
const beforeStop=await rows();const writable=await payload();
const stopMarker='-- STOP_READY_GLOBAL_EXCLUSIVE_ACQUIRED';assert.equal(stop.split(stopMarker).length,2,'STOP split marker exact');
const stopCut=stop.indexOf(stopMarker)+stopMarker.length;
await fault(stop.replace('create or replace function',()=>"do $$begin raise sqlstate 'P0001' using message='synthetic_stop_failure';end$$;\ncreate or replace function"),'P0001','failed STOP leaves ready bodies and all rows');
await fault(stop.replace('begin;',"begin;create schema stop_ready_unknown;create role stop_ready_unknown_role;grant execute on function private.apply_worker_personnel_payload(uuid,jsonb,uuid) to stop_ready_unknown_role;"),'55000','unknown ACL STOP atomically preserves rows and synthetic role/schema');
if(native){
 const clients=[];const make=async()=>{const c=await connect();clients.push(c);return c;};
 const settled=promise=>promise.then(value=>({value}),error=>({error}));
 const beginActor=async(c,who)=>{await c.query('begin');await c.query("select set_config('fixture.actor',$1,false)",[who]);await c.query('set role authenticated');};
 try{
  const queuedActors=[];
  for(const [label,who,text,values,warmValues] of [
   ['noop',actors.owner,'select public.save_worker_personnel_profile($1,$2) r',[W,wire(writable,writable.birth_date)],[W,wire(writable,writable.birth_date)]],
   ['proposal',actors.self,'select public.save_worker_personnel_profile($1,$2) r',[W,wire(writable,'1984-01-01')],[W,wire(writable,writable.birth_date)]],
   ['approval',actors.owner,'select public.decide_worker_personnel_change($1,true) r',[pending.request_id],[pending.request_id]],
   ['nonDOB',actors.owner,'select public.save_worker_personnel_profile($1,$2) r',[W,plain(writable,'synthetic queued nonDOB')],[W,plain(writable,writable.address)]]
  ]){
   const c=await make(),name='cached-ready-'+label;
   await beginActor(c,who);
   const warmed=(await c.query({name,text,values:warmValues})).rows[0].r;
   assert.equal(warmed.status,label==='approval'?'pending':'unchanged','prewarm '+label);
   await c.query('rollback');
   queuedActors.push({label,who,c,command:{name,text,values}});
  }
  assert.deepEqual(await rows(),beforeStop,'four prewarmed READY plans leave business/identity/bank unchanged');
  await assertPendingUnchanged('prewarmed READY approval rollback');
  console.log('PASS Native prewarmed 4 named READY commands/helpers; 3 no-ops plus quorum2 approval rollback preserve all rows');
  const admitted=await make(),stopper=await make();await beginActor(admitted,actors.owner);
  assert.equal((await admitted.query('select public.save_worker_personnel_profile($1,$2) r',[W,wire(writable,writable.birth_date)])).rows[0].r.status,'unchanged');
  const acquiring=settled(stopper.query(stop.slice(0,stopCut)));
  // Do not issue pid queries on a blocked connection: capture it beforehand.
  const stopperPid=stopper.processID;
  for(let i=0;;i++){const r=(await db.query('select wait_event_type,wait_event from pg_stat_activity where pid=$1',[stopperPid])).rows[0];if(r?.wait_event_type==='Lock'&&r.wait_event==='advisory')break;if(i===200)throw Error('STOP did not wait on admitted writer');await new Promise(resolve=>setTimeout(resolve,10));}
  await admitted.query('commit');assert.ok((await acquiring).value,'STOP acquired after writer commit');
  assert.deepEqual(await rows(),beforeStop,'admitted DOB no-op leaves rows unchanged');
  const queued=[];
  for(const {label,who,c,command} of queuedActors){
   await beginActor(c,who);const backend=c.processID;
   const promise=settled(c.query(command));
   for(let i=0;;i++){const r=(await db.query('select wait_event_type,wait_event from pg_stat_activity where pid=$1',[backend])).rows[0];if(r?.wait_event_type==='Lock'&&r.wait_event==='advisory')break;if(i===200)throw Error(label+' did not wait on global shared gate');await new Promise(resolve=>setTimeout(resolve,10));}
   console.log('PASS Native '+label+' reused warmed named READY plan then actual global advisory wait');queued.push({label,c,promise});
  }
  const commitAt=stop.toLowerCase().lastIndexOf('commit;');assert.ok(commitAt>stopCut);
  await stopper.query(stop.slice(stopCut,commitAt));
  const stoppedRows={rows:{},bank:(await stopper.query('select to_jsonb(b) b from worker_private_bank_accounts b order by worker_id')).rows};
  for(const t of [...businessTables,...protectedTables])stoppedRows.rows[t]=(await stopper.query(`select to_jsonb(t) value from ${t} t order by to_jsonb(t)::text`)).rows.map(x=>x.value);
  assert.deepEqual(stoppedRows,beforeStop,'STOP inside transaction preserves all business/identity/approval/proposal/family/bank rows');
  const inTxn=(await stopper.query('select private.worker_personnel_payload($1) p',[W])).rows[0].p;
  assert.equal(inTxn.birth_date_contract_version,1);assert.equal(inTxn.birth_date,writable.birth_date);assert.equal(inTxn.personnel_cas_digest,writable.personnel_cas_digest,'read-only capability change preserves unchanged content digest');
  await stopper.query(stop.slice(commitAt));
  for(const q of queued){const result=await q.promise;if(q.label==='nonDOB'){assert.equal(result.value?.rows[0].r.status,'saved');await q.c.query('commit');}else{assert.equal(result.error?.code,'42501',q.label+' must reject after STOP');await q.c.query('rollback');}}
  await assertPendingUnchanged('queued nonDOB owner after STOP');
  console.log('PASS Native admitted writer drains; STOP exclusive blocks queued READY DOB no-op/proposal/approval; resumed calls see version1; queued nonDOB preserves pending');
 }finally{for(const c of clients){await c.query('rollback');await c.end();}}
}else{
 await db.exec(stop.slice(0,stopCut));await db.exec(stop.slice(stopCut));
 assert.deepEqual(await rows(),beforeStop,'STOP preserves complete business/identity/bank state');
}
assert.deepEqual(await writerCatalog(),readyWriters,'STOP preserves all three ready writer bodies/ACLs/attributes exactly');
await preservedMarkers();
const stopped=await payload();assert.equal(stopped.birth_date_contract_version,1);assert.equal(stopped.birth_date,writable.birth_date);if(!native)assert.equal(stopped.personnel_cas_digest,writable.personnel_cas_digest,'unchanged content retains digest independently of capability');
await actor(actors.owner);await deny(()=>db.query('select public.save_worker_personnel_profile($1,$2)',[W,wire(stopped,stopped.birth_date)]));
await actor(actors.self);await deny(()=>db.query('select public.save_worker_personnel_profile($1,$2)',[W,wire(stopped,'1985-01-01')]));
await actor(actors.owner);await deny(()=>db.query('select public.decide_worker_personnel_change($1,true)',[pending.request_id]));
await assertPendingUnchanged('direct stopped DOB attempts');
const ownerApplyBefore=await rows();
for(const date of [null,'1986-01-01']){
 await db.exec('reset role');await db.query("select set_config('fixture.actor',$1,false)",[actors.owner]);
 // Database owner bypasses EXECUTE ACL: the private body itself must pause DOB.
 await deny(()=>db.query('select private.apply_worker_personnel_payload($1,$2,$3)',[W,wire(stopped,date),actors.owner]));
 assert.deepEqual(await rows(),ownerApplyBefore,'owner-only direct apply denial leaves all rows unchanged');
 await assertPendingUnchanged('owner-only direct private apply '+date);
}
await actor(actors.owner);const readView=(await db.query('select private.employee_personnel_view($1) r',[C])).rows[0].r;await db.exec('reset role');
assert.equal(readView.birth_date_contract_version,1);const readWorker=readView.records.find(r=>r.id===W);assert.equal(readWorker.birthDate,writable.birth_date);assert.equal(readWorker.birthDateContractVersion,1);assert.equal(readWorker.personnelCasDigest,stopped.personnel_cas_digest);
assert.equal((await save(actors.owner,plain(await payload(),'synthetic owner nonDOB after STOP'))).status,'saved');assert.equal(await status(pending.request_id),'pending');await preservedMarkers();await assertPendingUnchanged('standalone owner nonDOB save');
// Legacy saves and their approvals stay usable; birthday markers are preserved.
const non1=await save(actors.self,plain(await payload(),'synthetic nonDOB first'));assert.equal(non1.status,'pending');
const non2=await save(actors.self,plain(await payload(),'synthetic nonDOB replacement'));assert.equal(non2.status,'pending');assert.equal(await status(non1.request_id),'rejected');assert.equal(await status(pending.request_id),'pending');
assert.equal((await decide(non2.request_id,true)).status,'approved');assert.equal(await status(pending.request_id),'pending');
await assertPendingUnchanged('nonDOB self supersession and approval before explicit DOB rejection');
assert.equal((await decide(pending.request_id,false)).status,'rejected');await preservedMarkers();
assert.equal((await payload()).birth_date,writable.birth_date);
const bank=(await rows()).bank;assert.deepEqual(bank,original.bank);
if(fs.existsSync(path.join(sqlDir,'reopen-before-dob.sql.review-only')))await fault(sql('reopen-before-dob'),'55000','preDOB reopen forbidden after READY/STOP');
console.log('PASS STOP version1 retains DOB and independent content digest, pending proposal/approval/family/bank state; DOB writes deny; nonDOB self supersession/approval and explicit DOB rejection work');
await db.close();
console.log('PASS '+(native?'Native17.6 real lock schedules':'PGlite synthetic logic only')+'; no production/auth/device/UI evidence; no deletion or automatic resend');
