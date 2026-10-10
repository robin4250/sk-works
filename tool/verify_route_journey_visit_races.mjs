import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
const connectionString=process.env.SKO_ROUTE_RACE_DATABASE_URL;
const url=new URL(connectionString??'postgres://invalid');
if(!['postgres:','postgresql:'].includes(url.protocol)||url.search||url.hash||!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.pathname!=='/sko_route_capture_race_fixture')throw new Error('Only local disposable sko_route_capture_race_fixture database is permitted');
const pg=await import(process.argv[2]);const Client=pg.Client??pg.default?.Client;
const clients=[];
async function connect(name){const c=new Client({connectionString,application_name:name});const p=c.connectionParameters;if(!['127.0.0.1','localhost','::1'].includes(p.host)||p.database!=='sko_route_capture_race_fixture'||Number(p.port)!==Number(url.port||5432))throw new Error('Effective connection escaped disposable fixture');await c.connect();clients.push(c);await c.query("set statement_timeout='20s';set lock_timeout='15s'");return c;}
const id=n=>`20000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const [company,actor,worker,route,stop]=[1,2,3,4,5].map(id);
const payload={capture_contract_version:1,gps_capture_status:'failed',photo_capture_status:'failed',gps_captured_at:null,photo_captured_at:null,photo_observed_at:null,captured_address:null,latitude:null,longitude:null,accuracy_m:null,photo_storage_path:null,attempted_at:'2026-10-01T00:01:00Z'};
let admin,a,b,observer;
const settle=p=>{p.catch(()=>{});return p;};
const save=(c,source,event,kind='start',start=event)=>c.query('select public.save_route_journey_visit($1,$2,$3,$4,$5,$6,$7) v',[event,source,stop,'company',payload,kind,start]);
const close=(c,source,event)=>c.query("insert into attendance_verifications select $1,company_id,worker_id,site_id,route_assignment_id,work_date,'clock_out',id,null,verification_mode,capture_contract_version from attendance_verifications where id=$2",[event,source]);
async function source(n){const value=id(n);await admin.query("insert into attendance_verifications values($1,$2,$3,null,$4,'2026-09-30','clock_in',null,null,'location_photo',1)",[value,company,worker,route]);return value;}
async function barrier(names){const until=Date.now()+8000;while(Date.now()<until){await observer.query('select pg_stat_clear_snapshot()');const r=await observer.query("select count(*)::int n from pg_stat_activity where application_name=any($1) and wait_event_type='Lock'",[names]);if(r.rows[0].n===names.length)return;await new Promise(r=>setTimeout(r,25));}throw new Error('Expected actual Lock barrier: '+names);}
async function hold(s){await admin.query('begin');await admin.query('select id from attendance_verifications where id=$1 for update',[s]);}
try {
 admin=await connect('visit-admin');a=await connect('visit-a');b=await connect('visit-b');observer=await connect('visit-observer');
 const version=(await admin.query('show server_version')).rows[0].server_version;assert.match(version,/^17\./);
 await admin.query('drop schema if exists private cascade;drop schema if exists auth cascade;drop schema if exists storage cascade;drop schema public cascade;create schema public');
 await admin.query("do $$begin if not exists(select 1 from pg_roles where rolname='anon')then create role anon;end if;if not exists(select 1 from pg_roles where rolname='authenticated')then create role authenticated;end if;end$$");
 const schema=await fs.readFile(new URL('./fixtures/route_journey_capture/schema.sql',import.meta.url),'utf8');await admin.query(schema.replace('create role anon; create role authenticated;',''));
 for(const path of ['../supabase/migrations/20261008204012_route_journey_capture_staged.sql','./fixtures/route_journey_visits/visits.sql','./fixtures/route_journey_visits/retention.sql'])await admin.query(await fs.readFile(new URL(path,import.meta.url),'utf8'));
 await admin.query(`insert into companies values('${company}');insert into company_members values('${company}','${actor}','member');insert into workers values('${worker}','${company}','${actor}','本人','active');insert into route_assignments values('${route}','${company}');insert into route_stops values('${stop}','${route}',null,1,'計画住所','現場1');insert into private.route_journey_rollouts values('${company}',true)`);
 for(const c of [admin,a,b])await c.query(`set test.uid='${actor}'`);
 for(const c of [a,b])await c.query('set role authenticated');
 // Two distinct starts must serialize into one open visit, not two.
 let s=await source(10);await hold(s);let left=settle(save(a,s,id(11))),right=settle(save(b,s,id(12)));await barrier(['visit-a','visit-b']);await admin.query('commit');let results=await Promise.allSettled([left,right]);
 assert.equal(results.filter(r=>r.status==='fulfilled').length,1);assert.match(results.find(r=>r.status==='rejected').reason.message,/finish current visit first/);
 assert.equal((await admin.query('select count(*)::int n from private.route_journey_captures where source_clock_in_id=$1',[s])).rows[0].n,1);
 console.log('PASS distinct concurrent starts: exactly one visit/capture');
 // Same fixed command returns the same result to both clients after the lock.
 s=await source(20);await hold(s);left=settle(save(a,s,id(21)));right=settle(save(b,s,id(21)));await barrier(['visit-a','visit-b']);await admin.query('commit');results=await Promise.all([left,right]);assert.deepEqual(results[0].rows[0].v,results[1].rows[0].v);
 console.log('PASS same UUID concurrent retry: identical result, one row');
 // Competing ends may not close a visit twice.
 await hold(s);left=settle(save(a,s,id(22),'end',id(21)));right=settle(save(b,s,id(23),'end',id(21)));await barrier(['visit-a','visit-b']);await admin.query('commit');results=await Promise.allSettled([left,right]);assert.equal(results.filter(r=>r.status==='fulfilled').length,1);assert.match(results.find(r=>r.status==='rejected').reason.message,/selected open visit required/);
 console.log('PASS distinct concurrent ends: exactly one end');
 // Start owns source first: waiting clock-out rechecks committed open visit.
 s=await source(30);await a.query('begin');await save(a,s,id(31));const waitingClose=settle(close(admin,s,id(32)));await barrier(['visit-admin']);await a.query('commit');await assert.rejects(waitingClose,/finish current visit before clock-out/);
 // End owns source first: waiting clock-out succeeds after end commits.
 await a.query('begin');await save(a,s,id(33),'end',id(31));const afterEnd=settle(close(admin,s,id(34)));await barrier(['visit-admin']);await a.query('commit');await afterEnd;
 console.log('PASS start/end-first vs clock-out: no implicit visit closure');
 // Clock-out owns source first: a new visit cannot open a closed shift.
 s=await source(40);await hold(s);const waitingStart=settle(save(a,s,id(41)));await barrier(['visit-a']);await close(admin,s,id(42));await admin.query('commit');await assert.rejects(waitingStart,/closed/);
 console.log('PASS clock-out-first vs start: new visit rejected');
 // Save first, management delete second: archive includes committed capture/event.
 s=await source(60);await a.query('begin');await save(a,s,id(61));const waitingDelete=settle(admin.query('delete from attendance_verifications where id=$1',[s]));await barrier(['visit-admin']);await a.query('commit');await waitingDelete;
 let archived=(await a.query('select public.route_journey_visit_exact($1) v',[id(61)])).rows[0].v;assert.equal(archived.archived,true);assert.equal(archived.start_capture_id,id(61));
 // Delete first, end second: end rolls back and original start remains archived.
 s=await source(70);await save(a,s,id(71));await admin.query('begin');await admin.query('delete from attendance_verifications where id=$1',[s]);const waitingEnd=settle(save(b,s,id(72),'end',id(71)));await barrier(['visit-b']);await admin.query('commit');await assert.rejects(waitingEnd,/source not found/);
 archived=(await a.query('select public.route_journey_visit_exact($1) v',[id(71)])).rows[0].v;assert.equal(archived.archived,true);assert.equal((await a.query('select public.route_journey_visit_exact($1) v',[id(72)])).rows[0].v,null);
 console.log('PASS management delete vs start/end: original capture/event archived; no late write');
 // OFF committed while waiting must be observed; recovery is still read-only.
 s=await source(50);await hold(s);const waitingOff=settle(save(a,s,id(51)));await barrier(['visit-a']);await admin.query('update private.route_journey_rollouts set enabled=false');await admin.query('commit');await assert.rejects(waitingOff,/disabled/);
 assert.equal((await a.query('select public.route_journey_visit_exact($1) v',[id(21)])).rows[0].v.id,id(21));
 console.log(`PASS PostgreSQL ${version}: observed visit Lock schedules; no production access`);
} finally {await Promise.allSettled(clients.map(async c=>{try{await c.query('rollback');}finally{await c.end();}}));}
