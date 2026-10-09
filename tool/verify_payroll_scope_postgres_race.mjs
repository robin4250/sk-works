import assert from 'node:assert/strict';
import {validatePayrollScopeFixtureUrl} from './payroll_scope_pg17_database_guard.mjs';
const connectionString=validatePayrollScopeFixtureUrl(process.env.SKO_PAYROLL_SCOPE_FIXTURE_URL);
const pg=await import(process.argv[2]);const Client=pg.Client??pg.default.Client;
const a=new Client({connectionString}),b=new Client({connectionString}),observer=new Client({connectionString});
const cid='10000000-0000-0000-0000-000000000001',owner='00000000-0000-0000-0000-000000000001',w1='40000000-0000-0000-0000-000000000001',w2='40000000-0000-0000-0000-000000000002',site='70000000-0000-0000-0000-000000000001';
async function begin(c){await c.query('begin');await c.query("select set_config('request.jwt.claim.sub',$1,true)",[owner]);await c.query('set local role authenticated');}
async function blocked(pid){for(let i=0;i<100;i++){const r=await observer.query("select wait_event_type from pg_stat_activity where pid=$1",[pid]);if(r.rows[0]?.wait_event_type==='Lock')return;await new Promise(r=>setTimeout(r,20));}assert.fail('Expected actual PostgreSQL lock wait');}
async function signature(c,id){return c.query("select public.save_daily_report_signature($1,'representative','Representative',$2::jsonb)",[id,JSON.stringify({strokes:[[1,2]]})]);}
try{
 await Promise.all([a.connect(),b.connect(),observer.connect()]);assert.equal(Math.floor(Number((await observer.query('show server_version_num')).rows[0].server_version_num)/10000),17);
 for(const c of[a,b])await c.query("set statement_timeout='15s';set lock_timeout='10s'");
 const day=(await observer.query("select (now() at time zone 'Asia/Tokyo')::date::text day")).rows[0].day;
 const r1='a0000000-0000-0000-0000-000000000011',r2='a0000000-0000-0000-0000-000000000012';
 await observer.query('insert into public.daily_reports(id,company_id,site_id,report_date) values($1,$3,$4,$5),($2,$3,$4,$5)',[r1,r2,cid,site,day]);
 await observer.query('insert into public.daily_report_workers(report_id,worker_id) values($1,$3),($1,$4),($2,$4),($2,$3)',[r1,r2,w1,w2]);
 await begin(a);await signature(a,r1);await begin(b);const pid=(await b.query('select pg_backend_pid() pid')).rows[0].pid;
 const pending=signature(b,r2);await blocked(pid);assert.ok((await observer.query("select count(*)::int n from pg_locks where pid=$1 and locktype='advisory' and granted",[(await a.query('select pg_backend_pid() pid')).rows[0].pid])).rows[0].n>=2);
 await a.query('commit');await pending;await b.query('commit');
 assert.equal((await observer.query('select count(*)::int n from public.daily_reports where id=any($1::uuid[]) and representative_signer_name=$2',[[r1,r2],'Representative'])).rows[0].n,2);
 // Actual vehicle RPC and signature RPC now both take scope/parent before child.
 for(const vehicleFirst of [true,false]){
   await begin(a);if(vehicleFirst)await a.query('select public.save_daily_report_vehicle_usage($1,$2,null,null,null)',[r1,w1]);else await signature(a,r1);
   await begin(b);const race=vehicleFirst?signature(b,r1):b.query('select public.save_daily_report_vehicle_usage($1,$2,null,null,null)',[r1,w1]);
   await blocked(pid);await a.query('commit');await race;await b.query('commit');
 }
 // A source change while waiting fails closed rather than acquiring a new tuple late.
 const r3='a0000000-0000-0000-0000-000000000013';
 await observer.query('insert into public.daily_reports(id,company_id,site_id,report_date) values($1,$2,$3,$4)',[r3,cid,site,day]);
 await observer.query('insert into public.daily_report_workers(report_id,worker_id) values($1,$2)',[r3,w2]);
 await a.query('begin');await a.query('select 1 from public.workers where id=$1 for update',[w2]);
 await begin(b);const drift=signature(b,r3).then(()=>({ok:true}),error=>({error}));await blocked(pid);
 await a.query('delete from public.daily_report_workers where report_id=$1',[r3]);await a.query('commit');
 const rejected=await drift;assert.equal(rejected.error?.code,'40001');await b.query('rollback');
 assert.equal((await observer.query('select representative_signer_name from public.daily_reports where id=$1',[r3])).rows[0].representative_signer_name,null);
 // Parent SHARE is compatible with the KEY SHARE acquired by an HR child FK.
 await observer.query('create table public.scope_test_family(worker_id uuid references public.workers(id),company_id uuid references public.companies(id))');
 await a.query('begin');await a.query('select 1 from public.workers where id=$1 for update',[w1]);
 await b.query('begin');await b.query('select 1 from public.companies where id=$1 for share',[cid]);const wait=b.query('select 1 from public.workers where id=$1 for share',[w1]);await blocked(pid);
 await a.query('insert into public.scope_test_family values($1,$2)',[w1,cid]);await a.query('commit');await wait;await b.query('commit');
 console.log('PASS native PG17 reversed worker signature RPCs serialize; company SHARE permits HR FK KEY SHARE while worker snapshot waits');
}finally{for(const c of[a,b]){try{await c.query('rollback');}catch{}}await Promise.all([a.end(),b.end(),observer.end()]);}
