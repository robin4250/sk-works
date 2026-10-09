import assert from 'node:assert/strict';import{validateNormalPayrollFixtureUrl}from'./payroll_normal_api_pg17_database_guard.mjs';
const connectionString=validateNormalPayrollFixtureUrl(process.env.SKO_PAYROLL_NORMAL_API_FIXTURE_URL);const pg=await import(process.argv[2]);const Client=pg.Client??pg.default.Client;
const a=new Client({connectionString}),b=new Client({connectionString}),o=new Client({connectionString});
const cid='10000000-0000-0000-0000-000000000001',owner='00000000-0000-0000-0000-000000000001',w1='40000000-0000-0000-0000-000000000001',w2='40000000-0000-0000-0000-000000000002',site='70000000-0000-0000-0000-000000000001';
async function begin(c,id=owner){await c.query('begin');await c.query("select set_config('request.jwt.claim.sub',$1,true)",[id]);await c.query('set local role authenticated');}
async function wait(pid){for(let i=0;i<100;i++){if((await o.query('select wait_event_type from pg_stat_activity where pid=$1',[pid])).rows[0]?.wait_event_type==='Lock')return;await new Promise(r=>setTimeout(r,20));}assert.fail('Expected actual lock wait');}
const caught=p=>p.then(result=>({result}),error=>({error}));
try{
 await Promise.all([a.connect(),b.connect(),o.connect()]);assert.equal(Math.floor(Number((await o.query('show server_version_num')).rows[0].server_version_num)/10000),17);for(const c of[a,b])await c.query("set statement_timeout='15s';set lock_timeout='10s'");const pid=(await b.query('select pg_backend_pid() as pid')).rows[0].pid;
 // Reverse worker/month application input locks the same full collection first.
 const items=[{worker_id:w2,date:'2020-03-01',site_id:site,mode:'work'},{worker_id:w1,date:'2020-02-01',site_id:site,mode:'work'}];
 await begin(a);await a.query("select public.force_manage_attendance('upsert',$1::jsonb)",[JSON.stringify(items)]);await begin(b);const competing=caught(b.query("select public.force_manage_attendance('upsert',$1::jsonb)",[JSON.stringify([...items].reverse())]));await wait(pid);await a.query('commit');const stale=await competing;assert.equal(stale.error?.code,'40001');await b.query('rollback');
 await begin(b);assert.equal((await b.query("select public.force_manage_attendance('upsert',$1::jsonb) as n",[JSON.stringify([...items].reverse())])).rows[0].n,2);await b.query('commit');
 // Actual cancellation preview and signature share prelock order.
 await begin(a);const report=(await a.query('select public.save_daily_report_destination_draft(null,$1,null,$2,null,$3::jsonb) as id',[site,'2020-04-01',JSON.stringify([{worker_id:w2}])])).rows[0].id;await a.query('commit');
 await begin(a);await a.query('select public.cancel_daily_report($1::jsonb)',[JSON.stringify({report_id:report,action:'preview'})]);await begin(b);const signature=caught(b.query("select public.save_daily_report_signature($1,'representative','Rep',$2::jsonb)",[report,JSON.stringify({strokes:[[1,2]]})]));await wait(pid);await a.query('commit');assert.equal((await signature).error,undefined);await b.query('commit');
 // An uncommitted real adjustment changes revision before finalization can commit.
 const ps=(await o.query("select * from public.payroll_statements where company_id=$1 and worker_id=$2 and period_start='2020-02-01'",[cid,w1])).rows[0];assert.ok(ps);const type='c0000000-0000-0000-0000-000000000001';
 await o.query("insert into public.payroll_adjustment_types values($1,$2,'Race addition','addition',true)",[type,cid]);
 await o.query('insert into public.payroll_confirmers(company_id,user_id,position) values($1,$2,1)',[cid,owner]);await o.query('insert into public.payroll_statement_reviews values($1,$2,$3,$3,now(),now())',[ps.id,owner,ps.revision]);
 await begin(a);await a.query('select public.create_payroll_adjustment($1,$2,100,$3,null)',[w1,type,'2020-02-01']);await begin(b);const final=caught(b.query('select public.finalize_payroll_statement($1,$2,true)',[ps.id,ps.revision]));await wait(pid);await a.query('commit');assert.equal((await final).error?.code,'40001');await b.query('rollback');
 assert.equal((await o.query('select count(*)::int as n from payroll_final_private.documents where statement_id=$1',[ps.id])).rows[0].n,0);
 // Current review company UPDATE precedes a normal raw single-row settings save.
 await begin(a);await a.query("select public.cancel_payroll_review_month('2020-02-01')");await begin(b);const settings=caught(b.query('update public.worker_payroll_settings set day_daily=day_daily+1 where company_id=$1 and worker_id=$2',[cid,w1]));await wait(pid);await a.query('commit');assert.equal((await settings).error,undefined);await b.query('commit');
 // Preserve the existing approved non-member professional writer; align UPDATE and UPSERT.
 const professional='00000000-0000-0000-0000-000000000009';
 for(const portalFirst of [true,false]){
  await begin(a,portalFirst?professional:owner);
  if(portalFirst)await a.query("select private.professional_portal('save_payroll',$1::jsonb)",[JSON.stringify({worker_id:w2,values:{day_daily:17444}})]);
  else await a.query('update public.worker_payroll_settings set day_daily=day_daily+1 where worker_id=$1',[w2]);
  await begin(b,portalFirst?owner:professional);
  const mutation=caught(portalFirst?b.query('update public.worker_payroll_settings set day_daily=day_daily+1 where worker_id=$1',[w2]):b.query("select private.professional_portal('save_payroll',$1::jsonb)",[JSON.stringify({worker_id:w2,values:{day_daily:17444}})]));
  await wait(pid);await a.query('commit');assert.equal((await mutation).error,undefined);await b.query('commit');
 }
 const w3='40000000-0000-0000-0000-000000000003';
 await o.query("insert into public.workers(id,company_id,name,status,affiliation) values($1,$2,'New worker','active','employee')",[w3,cid]);
 await begin(a);await a.query('insert into public.worker_payroll_settings(worker_id,company_id,day_daily) values($1,$2,100)',[w3,cid]);
 await begin(b,professional);const inserted=caught(b.query("select private.professional_portal('save_payroll',$1::jsonb)",[JSON.stringify({worker_id:w3,values:{day_daily:222}})]));await wait(pid);await a.query('commit');assert.equal((await inserted).error?.code,'40001');await b.query('rollback');
 await begin(b,professional);await b.query("select private.professional_portal('save_payroll',$1::jsonb)",[JSON.stringify({worker_id:w3,values:{day_daily:222}})]);await b.query('commit');
 assert.equal(Number((await o.query('select day_daily from public.worker_payroll_settings where worker_id=$1',[w3])).rows[0].day_daily),222);
 console.log('PASS native normal APIs: reverse tuple force requests/stale retry; cancellation/signature; adjustment/finalize revision refusal; review/single-row settings serialization');
}finally{for(const c of[a,b])try{await c.query('rollback');}catch{}await Promise.all([a.end(),b.end(),o.end()]);}
