import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
const connectionString=process.env.SKO_ROUTE_RACE_DATABASE_URL;
const url=new URL(connectionString??'postgres://invalid');
if(!['postgres:','postgresql:'].includes(url.protocol)||url.search!==''||url.hash!==''||!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.pathname!=='/sko_route_capture_race_fixture')throw new Error('Only local disposable sko_route_capture_race_fixture database is permitted');
const pg=await import(process.argv[2]);const Client=pg.Client??pg.default?.Client;
const clients=[];
async function connect(name){const c=new Client({connectionString,application_name:name});const effective=c.connectionParameters;const expectedPort=Number(url.port||5432);if(!['127.0.0.1','localhost','::1'].includes(effective.host)||effective.database!=='sko_route_capture_race_fixture'||!Number.isInteger(expectedPort)||expectedPort<1||expectedPort>65535||Number(effective.port)!==expectedPort)throw new Error('Effective Postgres connection must remain local and disposable');await c.connect();clients.push(c);await c.query("set statement_timeout='20s';set lock_timeout='15s'");return c;}
const ids=Array.from({length:14},(_,i)=>`00000000-0000-0000-0000-${String(i+1).padStart(12,'0')}`);
const [company,actor,worker,route,stop,source,report,capture,otherCapture,clockOut,thirdCapture,fourthCapture,objectId,fifthCapture]=ids;
const payload={capture_contract_version:1,gps_capture_status:'failed',photo_capture_status:'failed',gps_captured_at:null,photo_captured_at:null,photo_observed_at:null,captured_address:null,latitude:null,longitude:null,accuracy_m:null,photo_storage_path:null,attempted_at:'2026-10-01T00:01:00Z'};
const save=(c,id)=>c.query('select public.save_route_journey_capture($1,$2,$3,$4,$5) v',[id,source,stop,'company',payload]);
let admin,a,b,observer;
async function blocked(names){const end=Date.now()+8000;while(Date.now()<end){await observer.query('select pg_stat_clear_snapshot()');const r=await observer.query("select count(*)::int n from pg_stat_activity where application_name=any($1) and wait_event_type='Lock'",[names]);if(r.rows[0].n===names.length)return;await new Promise(resolve=>setTimeout(resolve,25));}throw new Error(`No observed database Lock barrier: ${names}`);}
const settle=p=>{p.catch(()=>{});return p;};
try{
 admin=await connect('route-admin');a=await connect('route-a');b=await connect('route-b');observer=await connect('route-observer');
 const version=(await admin.query('show server_version')).rows[0].server_version;assert.match(version,/^16\./);console.log(`PostgreSQL ${version}: disposable route fixture`);
 await admin.query('drop schema if exists private cascade;drop schema if exists auth cascade;drop schema if exists storage cascade;drop schema public cascade;create schema public');
 await admin.query("do $$begin if not exists(select 1 from pg_roles where rolname='anon')then create role anon;end if;if not exists(select 1 from pg_roles where rolname='authenticated')then create role authenticated;end if;end$$");
 const schema=await fs.readFile(new URL('./fixtures/route_journey_capture/schema.sql',import.meta.url),'utf8');await admin.query(schema.replace('create role anon; create role authenticated;',''));
 await admin.query(await fs.readFile(new URL('../supabase/migrations/20261008204012_route_journey_capture_staged.sql',import.meta.url),'utf8'));
 await admin.query(`insert into auth.users values('${actor}');insert into companies values('${company}');insert into company_members values('${company}','${actor}','member');insert into workers values('${worker}','${company}','${actor}','本人','active');insert into route_assignments values('${route}','${company}');insert into route_stops values('${stop}','${route}',null,1,'計画住所','現場1');insert into attendance_verifications values('${source}','${company}','${worker}',null,'${route}','2026-09-30','clock_in',null,null,'location_photo',1);insert into daily_reports values('${report}','${company}',null,'${route}','2026-09-30','${actor}','draft');insert into daily_report_workers values('${report}','${worker}');insert into private.route_journey_rollouts values('${company}',true);`);
 for(const c of[a,b])await c.query(`set test.uid='${actor}';set role authenticated`);
 // Both commands enter before the first fixed UUID exists, then serialize on the same actual source.
 await admin.query('begin');await admin.query('select id from attendance_verifications where id=$1 for update',[source]);
 const first=settle(save(a,capture)),second=settle(save(b,capture));await blocked(['route-a','route-b']);await admin.query('commit');
 const outcomes=await Promise.allSettled([first,second]);assert.equal(outcomes.filter(r=>r.status==='fulfilled').length,1);const collision=outcomes.find(r=>r.status==='rejected');assert.equal(collision.reason.code,'23505');
 assert.equal((await admin.query('select count(*)::int n from private.route_journey_captures where id=$1',[capture])).rows[0].n,1);
 for(const c of[a,b]){const found=(await c.query('select public.route_journey_capture_exact($1) v',[capture])).rows[0].v;assert.equal(found.id,capture);assert.deepEqual(found.payload,payload);assert.equal(found.work_date,'2026-09-30');}
 console.log('PASS same UUID race: one raw row; loser 23505 recovers exact own ID/payload');
 // A clock-out that owns the source lock wins: the waiting capture rechecks actual closed state.
 await admin.query('begin');await admin.query('select id from attendance_verifications where id=$1 for update',[source]);
 const waiting=settle(save(a,otherCapture));await blocked(['route-a']);await admin.query(`insert into attendance_verifications select '${clockOut}',company_id,worker_id,site_id,route_assignment_id,work_date,'clock_out',id,null,verification_mode,capture_contract_version from attendance_verifications where id='${source}'`);await admin.query('commit');await assert.rejects(waiting,/closed/);
 assert.equal((await a.query('select public.route_journey_capture_exact($1) v',[capture])).rows[0].v.id,capture);await admin.query('delete from attendance_verifications where id=$1',[clockOut]);
 // A capture holding the source first completes before a waiting clock-out; its raw record remains recoverable.
 await a.query('begin');await save(a,otherCapture);const close=settle(b.query('select public.route_journey_workspace($1) v',[source]));await close; // ordinary reads do not block
 await admin.query('begin');const closeWrite=settle(admin.query('select id from attendance_verifications where id=$1 for update',[source]));await blocked(['route-admin']);await a.query('commit');await closeWrite;await admin.query(`insert into attendance_verifications select '${clockOut}',company_id,worker_id,site_id,route_assignment_id,work_date,'clock_out',id,null,verification_mode,capture_contract_version from attendance_verifications where id='${source}'`);await admin.query('commit');await admin.query('delete from attendance_verifications where id=$1',[clockOut]);
 console.log('PASS clock-out/source ordering in both directions; existing captures survive closure');
 // Link/save holds the saved report, while a new capture can finish independently. Link sees committed evidence.
 await admin.query('update attendance_verifications set daily_report_id=$1 where id=$2',[report,source]);await admin.query('begin');await admin.query('select id from daily_reports where id=$1 for update',[report]);
 const link=settle(a.query('select public.link_route_journey_report($1) n',[report]));await blocked(['route-a']);await save(b,thirdCapture);await admin.query('commit');await link;
 assert.equal((await admin.query('select count(*)::int n from private.route_journey_captures where daily_report_id=$1',[report])).rows[0].n,3);
 // Conversely a link already executed cannot include a later uncommitted row; repeating same saved report converges.
 await a.query('begin');await save(a,fourthCapture);await b.query('select public.link_route_journey_report($1)',[report]);await a.query('commit');assert.equal((await a.query('select public.route_journey_capture_exact($1) v',[fourthCapture])).rows[0].v.daily_report_id,null);await b.query('select public.link_route_journey_report($1)',[report]);assert.equal((await a.query('select public.route_journey_capture_exact($1) v',[fourthCapture])).rows[0].v.daily_report_id,report);
 console.log('PASS report-save/link waiting captures and exact report retry convergence; raw records unchanged');
 // OFF committed while save waits on its parent must reject new INSERT, preserving exact existing recovery.
 await admin.query('begin');await admin.query('select id from attendance_verifications where id=$1 for update',[source]);const offWait=settle(save(a,fifthCapture));await blocked(['route-a']);await admin.query('update private.route_journey_rollouts set enabled=false where company_id=$1',[company]);await admin.query('commit');await assert.rejects(offWait,/disabled/);assert.equal((await a.query('select public.route_journey_capture_exact($1) v',[capture])).rows[0].v.id,capture);
 await assert.rejects(a.query('insert into storage.objects(bucket_id,name) values($1,$2)',['attendance-route-evidence',`${company}/attendance/${route}/${worker}/${source}/after-off.jpg`]),/row-level security/);
 assert.equal((await a.query('select public.link_route_journey_report($1) n',[report])).rows[0].n,0);
 console.log('PASS OFF commits before blocked save: new capture/upload denied, exact history preserved, link returns zero');
 // Upload checks ON before waiting on a fixture storage primary key. Turning OFF does not retroactively erase admitted uploads.
 await admin.query('update private.route_journey_rollouts set enabled=true where company_id=$1',[company]);const path=`${company}/attendance/${route}/${worker}/${source}/in-flight.jpg`;await admin.query('insert into storage.objects(id,bucket_id,name) values($1,$2,$3)',[objectId,'attendance-route-evidence',path]);await admin.query('begin');await admin.query('delete from storage.objects where id=$1',[objectId]);const upload=settle(a.query('insert into storage.objects(id,bucket_id,name) values($1,$2,$3)',[objectId,'attendance-route-evidence',path]));await blocked(['route-a']);await admin.query('update private.route_journey_rollouts set enabled=false where company_id=$1',[company]);await admin.query('commit');await upload;
 assert.equal((await admin.query('select count(*)::int n from storage.objects where id=$1',[objectId])).rows[0].n,1);await assert.rejects(save(b,fifthCapture),/disabled/);
 console.log('OBSERVED admitted ON upload may finish after OFF; subsequent capture is denied; no orphan deletion or production ON permission');
 console.log('PASS actual PostgreSQL route capture targeted races; synthetic prerequisites only, not full history or retention verification');
}finally{await Promise.allSettled(clients.map(async c=>{try{await c.query('rollback');}finally{await c.end();}}));}
