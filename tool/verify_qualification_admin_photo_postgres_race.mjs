// Native PG17 synthetic-only. Reuses original SQL/fixture; no real Auth/Storage.
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
import path from 'node:path';
const database='sko_qualification_photo_race_fixture';
const raw=process.env.SKO_QUALIFICATION_PHOTO_RACE_URL;
const url=new URL(raw||'postgres://invalid');
if(!['postgres:','postgresql:'].includes(url.protocol)||url.hostname!=='127.0.0.1'||url.pathname!==`/${database}`||url.search||url.hash)throw new Error('Only dedicated 127.0.0.1 qualification fixture permitted');
const read=p=>fs.readFile(new URL('../'+p,import.meta.url),'utf8');
// Reuse the saved PGlite fixture's literal setup, not a second fixture copy.
const verifier=await read('tool/verify_qualification_admin_saved_photos.mjs');
const bootstrap=verifier.match(/await db\.exec\(`(alter table workers add column status[\s\S]*?)`\);/);
assert.ok(bootstrap&&!bootstrap[1].includes('${'),'existing fixture setup must remain one literal SQL block');
const candidate=await read('docs/candidates/qualification_admin_saved_photos_20261019.sql.review-only');
const pg=await import(pathToFileURL(path.resolve(process.argv[2])).href);
const Client=pg.Client??pg.default?.Client;
const clients=[];
async function connect(name){
 const c=new Client({connectionString:raw,application_name:name});const p=c.connectionParameters;
 if(p.host!=='127.0.0.1'||p.database!==database||Number(p.port)!==Number(url.port||5432))throw new Error('Effective connection escaped dedicated fixture');
 await c.connect();clients.push(c);await c.query("set statement_timeout='20s';set lock_timeout='10s';set deadlock_timeout='100ms'");return c;
}
const id=n=>`10000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const [company,admin,reviewer,user,worker,master,target]=[1,2,3,4,5,6,7].map(id),request=id(20);
const front=`${company}/${worker}/${master}/legacy/front.jpg`,back=`${company}/${worker}/${master}/legacy/back.jpg`;
const prepareData={company_id:company,target_id:target,request_id:request,photo_slots:[{existing_path:back},{existing_path:front}]};
const rpc=(c,action,data)=>c.query('select private.personal_qualification_submission($1,$2::jsonb) v',[action,JSON.stringify(data)]);
const actor=async(c,uid)=>{await c.query('reset role');await c.query("select set_config('test.uid',$1,false)",[uid]);await c.query('set role authenticated');};
let setup,a,b;
try{
 setup=await connect('qualification-race-setup');a=await connect('qualification-race-prepare');b=await connect('qualification-race-approve');
 assert.match((await setup.query('show server_version')).rows[0].server_version,/^17\./);
 assert.equal((await setup.query("select count(*)::int n from pg_namespace where nspname in ('private','auth','storage')")).rows[0].n,0,'fresh fixture required; never drop existing schemas');
 assert.equal((await setup.query("select count(*)::int n from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f')")).rows[0].n,0,'empty public relations required');
 assert.equal((await setup.query("select count(*)::int n from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'")).rows[0].n,0,'empty public functions required');
 assert.equal((await setup.query("select count(*)::int n from pg_namespace where nspname not in ('public','information_schema') and nspname !~ '^pg_'")).rows[0].n,0,'no other application schemas permitted');
 await setup.query("do $$begin if not exists(select 1 from pg_roles where rolname='anon')then create role anon;end if;if not exists(select 1 from pg_roles where rolname='authenticated')then create role authenticated;end if;if not exists(select 1 from pg_roles where rolname='service_role')then create role service_role;end if;end$$");
 for(const p of ['tool/fixtures/qualification_photo_submission/schema.sql','tool/fixtures/qualification_photo_submission/live_functions.sql','supabase/migrations/20261010222157_add_qualification_certificate_extra_photos.sql','supabase/migrations/20261010222753_protect_qualification_photo_snapshots.sql','supabase/migrations/20261010233011_personal_qualification_photo_submission.sql']){
  await setup.query((await read(p)).replace('create role anon;create role authenticated;create role service_role;',''));
 }
 await setup.query(bootstrap[1]);await setup.query(candidate);
 await setup.query('insert into companies values($1)',[company]);
 await setup.query("insert into company_members values($1,$2,'admin'),($1,$3,'admin'),($1,$4,'member')",[company,admin,reviewer,user]);
 await setup.query('insert into workers(id,company_id,user_id)values($1,$2,$3)',[worker,company,user]);
 await setup.query("insert into qualification_master values($1,$2,'Synthetic qualification',false)",[master,company]);
 await setup.query("insert into storage.objects(bucket_id,name)values('qualification-certificates',$1),('qualification-certificates',$2)",[front,back]);
 await setup.query("insert into worker_qualifications(id,company_id,worker_id,qualification_master_id,certificate_number,issuer,notes,attachment_path,attachment_back_path)values($1,$2,$3,$4,'original','issuer','original notes',$5,$6)",[target,company,worker,master,front,back]);
 const before=(await setup.query('select * from worker_qualifications where id=$1',[target])).rows[0];
 await actor(a,admin);await rpc(a,'prepare_admin_saved_photos',prepareData);assert.equal((await rpc(a,'submit',{id:request})).rows[0].v.status,'pending');
 const pendingBefore=(await setup.query('select * from private.qualification_submissions where id=$1',[request])).rows[0];
 const installed=(await setup.query("select pg_get_functiondef('private.admin_qualification_saved_photos(text,jsonb)'::regprocedure) definition")).rows[0].definition;
 const early='select * into req from private.qualification_submissions where id=request_id for update;';
 const late='select * into req from private.qualification_submissions where id=request_id;';
 assert.equal(installed.split(early).length,2);assert.equal(installed.split(late).length,2);
 // Negative control ONLY inside this synthetic database: restore the old late-lock
 // ordering, preserving the full original function and every authorization guard.
 const oldOrder=installed.replace(early,'-- negative-control early request lock omitted').replace(late,early);
 const pidA=(await a.query('select pg_backend_pid() p')).rows[0].p;
 const pidB=(await b.query('select pg_backend_pid() p')).rows[0].p;
 async function waitingOnB(){
  const deadline=Date.now()+8000;
  while(Date.now()<deadline){
   await setup.query('select pg_stat_clear_snapshot()');
   const r=(await setup.query("select wait_event_type,wait_event,pg_blocking_pids(pid) blockers from pg_stat_activity where pid=$1",[pidA])).rows[0];
   if(r?.wait_event_type==='Lock'&&r.blockers.includes(pidB)){
    console.log(`OBSERVED prepare waiting on approve request transaction: ${r.wait_event_type}/${r.wait_event}`);return;
   }
   await new Promise(resolve=>setTimeout(resolve,10)); // polling only, not a schedule barrier
  }
  throw new Error('prepare row-lock wait on B was not observed');
 }
 async function schedule(negative){
  await setup.query(negative?oldOrder:installed);
  await actor(a,admin);await actor(b,reviewer);
  await a.query('begin');await b.query('begin');
  // Fixture owner holds the exact private request, then runs the real approve
  // as the independent authenticated reviewer; no direct-row approve substitute.
  await b.query('reset role');await b.query('select id from private.qualification_submissions where id=$1 for update',[request]);await b.query('set role authenticated');
  const preparing=rpc(a,'prepare_admin_saved_photos',prepareData);preparing.catch(()=>{});
  await waitingOnB();
  const approving=rpc(b,'approve',{id:request});approving.catch(()=>{});
  if(negative){
   const results=await Promise.allSettled([preparing,approving]);
   const errors=results.filter(r=>r.status==='rejected').map(r=>r.reason);
   assert.ok(errors.some(e=>e.code==='40P01'),'old order must produce an actual 40P01 deadlock');
   assert.ok(errors.every(e=>e.code==='40P01'),'timeouts/setup/auth errors are not a negative-control success');
   await a.query('rollback');await b.query('rollback');
   assert.deepEqual((await setup.query('select * from private.qualification_submissions where id=$1',[request])).rows[0],pendingBefore);
   assert.deepEqual((await setup.query('select * from worker_qualifications where id=$1',[target])).rows[0],before);
   console.log('PASS negative control: observed real lock wait and SQLSTATE 40P01; rolled back to exact pending/original row');
  }else{
   const approved=(await approving).rows[0].v;assert.equal(approved.status,'approved');await b.query('commit');
   const prepared=(await preparing).rows[0].v;assert.equal(prepared.status,'approved');assert.equal(prepared.id,request);await a.query('commit');
   const actual=(await setup.query('select * from worker_qualifications where id=$1',[target])).rows[0];
   assert.equal(actual.attachment_path,back);assert.equal(actual.attachment_back_path,front);assert.deepEqual(actual.attachment_extra_paths,[]);
   const retained={...actual,attachment_path:before.attachment_path,attachment_back_path:before.attachment_back_path,attachment_extra_paths:before.attachment_extra_paths,updated_at:before.updated_at};assert.deepEqual(retained,before,'all other official fields unchanged');
   const row=(await setup.query('select * from private.qualification_submissions where id=$1',[request])).rows[0];
   assert.equal((await setup.query('select count(*)::int n from private.qualification_submissions where id=$1',[request])).rows[0].n,1);
   assert.ok(row.reviewed_at);assert.equal(row.status,'approved');assert.equal(row.requested_by,admin);assert.equal(row.reviewed_by,reviewer);assert.equal(row.admin_saved_photos,true);assert.deepEqual(row.photo_paths,[back,front]);
   assert.equal((await setup.query('select count(*)::int n from private.qualification_approved_write_permits')).rows[0].n,0);
   assert.equal((await setup.query('select count(*)::int n from storage.objects')).rows[0].n,2);
   console.log('PASS corrected order: observed prepare row wait, independent approve committed, prepare returned approved; exact official fields/request/photo metadata retained, no permit leak');
  }
 }
 await schedule(true);await schedule(false);
 console.log('Synthetic PG17 only; no real Auth/JWT, Storage bytes/API, hosted environment or production deployment proven');
}finally{await Promise.allSettled(clients.map(async c=>{try{await c.query('rollback');}finally{await c.end();}}));}
