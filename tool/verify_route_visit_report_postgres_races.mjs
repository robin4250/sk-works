import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
const connectionString=process.env.SKO_VISIT_REPORT_RACE_DATABASE_URL;
const url=new URL(connectionString??'postgres://invalid');
const database='sko_visit_report_race_fixture';
if(!['postgres:','postgresql:'].includes(url.protocol)||url.search||url.hash||!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.pathname!==`/${database}`)throw new Error('Only local disposable visit report fixture permitted');
const pg=await import(process.argv[2]);const Client=pg.Client??pg.default?.Client;const clients=[];
async function connect(name){const c=new Client({connectionString,application_name:name});const p=c.connectionParameters;if(!['127.0.0.1','localhost','::1'].includes(p.host)||p.database!==database||Number(p.port)!==Number(url.port||5432))throw new Error('Effective connection must remain local disposable fixture');await c.connect();clients.push(c);await c.query("set statement_timeout='20s';set lock_timeout='15s'");return c;}
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const [company,user,source,route,stop,worker]=[1,2,3,4,5,6].map(id);
const params=(start,end)=>[source,route,stop,start,end];
const settle=p=>{p.catch(()=>{});return p;};
let admin,a,b,observer;
async function blocked(){const deadline=Date.now()+8000;while(Date.now()<deadline){await observer.query('select pg_stat_clear_snapshot()');const r=await observer.query("select count(*)::int n from pg_stat_activity where application_name in ('visit-a','visit-b') and wait_event_type='Lock'");if(r.rows[0].n===2)return;await new Promise(resolve=>setTimeout(resolve,25));}throw new Error('Two actual blocked connections not observed');}
const signature={strokes:[[{x:0.1,y:0.1},{x:0.8,y:0.8}]]};
try{
 admin=await connect('visit-admin');a=await connect('visit-a');b=await connect('visit-b');observer=await connect('visit-observer');
 assert.match((await admin.query('show server_version')).rows[0].server_version,/^17\./);
 assert.equal((await admin.query("select count(*)::int n from pg_namespace where nspname in ('private','auth')")).rows[0].n,0,'fixture must be fresh; never delete existing schemas');
 const verifier=await fs.readFile(new URL('./verify_route_visit_reports.mjs',import.meta.url),'utf8');
 const fixture=verifier.match(/await db\.exec\(`([\s\S]*?)`\);/)[1];
 assert.ok(!fixture.includes('${'),'fixture must remain literal SQL');
 await admin.query(fixture);
 await admin.query(await fs.readFile(new URL('../supabase/migrations/20261011121738_route_visit_report_documents.sql',import.meta.url),'utf8'));
 await admin.query('insert into company_members values($1,$2);',[company,user]);
 await admin.query('insert into workers values($1,$2,$3)',[worker,company,'本人']);
 await admin.query('insert into route_stops values($1,$2,null)',[stop,route]);
 await admin.query('insert into daily_reports values($1)',[id(90)]);await admin.query('insert into attendance_entries values($1)',[id(91)]);
 const canonical=async()=> (await admin.query("select jsonb_build_object('reports',(select jsonb_agg(to_jsonb(d)) from daily_reports d),'attendance',(select jsonb_agg(to_jsonb(a)) from attendance_entries a),'verification',(select jsonb_agg(to_jsonb(v)) from attendance_verifications v)) v")).rows[0].v;
 const before=await canonical();
 for(const c of[a,b])await c.query(`set test.uid='${user}';set role authenticated`);
 const choose=(c,start,end,create)=>c.query('select public.choose_route_visit_report($1,$2,$3,$4,$5,$6) v',[...params(start,end),create]);
 for(const [offset,firstChoice] of [[10,true],[20,false]]){
  const start=id(offset),end=id(offset+1);
  const capture=(key,kind)=>({id:key,company_id:company,created_by:user,source_clock_in_id:source,route_assignment_id:route,route_stop_id:stop,worker_id:worker,visit_kind:kind,start_capture_id:start,stop_label:'現場',work_date:'2026-10-11'});
  await admin.query('insert into private.test_captures values($1,$2),($3,$4)',[start,capture(start,'start'),end,capture(end,'end')]);
  await admin.query('begin');await admin.query('select pg_advisory_xact_lock(hashtextextended($1,0))',[start]);
  const p=settle(choose(a,start,end,firstChoice)),q=settle(choose(b,start,end,!firstChoice));await blocked();await admin.query('commit');
  const [one,two]=await Promise.all([p,q]);assert.equal(one.rows[0].v.id,two.rows[0].v.id);
  const rows=(await admin.query('select * from private.route_visit_reports where start_capture_id=$1',[start])).rows;assert.equal(rows.length,1);assert.equal(rows[0].status,'skipped');
  assert.equal((await choose(a,start,end,true)).rows[0].v.status,'skipped','skip terminal across retries');
 }
 // A separate visit demonstrates concurrent signature idempotence on an existing draft.
 const start=id(30),end=id(31);const raw={company_id:company,created_by:user,source_clock_in_id:source,route_assignment_id:route,route_stop_id:stop,worker_id:worker,start_capture_id:start,stop_label:'署名現場',work_date:'2026-10-11'};
 await admin.query('insert into private.test_captures values($1,$2),($3,$4)',[start,{...raw,id:start,visit_kind:'start'},end,{...raw,id:end,visit_kind:'end'}]);
 const report=(await choose(a,start,end,true)).rows[0].v;
 for(const role of ['reporter','responsible']){
  await admin.query('begin');await admin.query('select id from private.route_visit_reports where id=$1 for update',[report.id]);
  const sign=c=>c.query('select public.save_route_visit_report_signature($1,$2,$3,$4) v',[report.id,role,role==='reporter'?'報告者':'責任者',signature]);
  const p=settle(sign(a)),q=settle(sign(b));await blocked();await admin.query('commit');
  const [one,two]=await Promise.all([p,q]);for(const key of ['id','status','representative_signer_name','representative_signature_json','supervisor_signer_name','supervisor_signature_json','signed_at'])assert.deepEqual(one.rows[0].v[key],two.rows[0].v[key]);
 }
 const completed=(await a.query('select public.read_route_visit_report($1,$2,$3,$4,$5) v',params(start,end))).rows[0].v;assert.equal(completed.status,'completed');assert.deepEqual(completed.representative_signature_json,signature);assert.deepEqual(completed.supervisor_signature_json,signature);
 assert.deepEqual(await canonical(),before,'canonical attendance/payroll-connected tables unchanged');
 console.log('PASS PostgreSQL 17 actual dual-connection create/skip ordering, fixed visit identity, reporter/responsible signature retries, unchanged canonical tables');
}finally{await Promise.allSettled(clients.map(async c=>{try{await c.query('rollback');}finally{await c.end();}}));}
