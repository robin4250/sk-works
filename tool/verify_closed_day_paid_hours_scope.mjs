// Native PostgreSQL17 isolated server-evidence scope proof.
// The shift/route BEFORE guards are exact observed sources; identity/access and
// route-end storage surroundings are explicitly synthetic. No real Auth claim.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
let client,phase='guarded-local-fixture',checks=0;
const eq=(a,b,n)=>{assert.deepEqual(a,b,n);checks++;};
const reject=async(fn,re)=>{await assert.rejects(fn,re);checks++;};
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const body=s=>{const m=/\bAS\s+(\$[A-Za-z_0-9]*\$)([\s\S]*)\1\s*;?\s*$/i.exec(s);assert.ok(m);return m[2];};
try{
 assert.equal(process.env.CI,'true');assert.equal(process.platform,'linux');
 assert.ok(!Object.keys(process.env).some(k=>/^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(k)));
 const url=new URL(process.env.SKO_PAID_HOURS_SCOPE_FIXTURE_URL);
 eq([url.protocol,url.hostname,url.port,url.username,url.password,url.pathname],
 ['postgresql:','127.0.0.1','5432','postgres','fixture-only','/sko_paid_hours_scope_fixture'],'Disposable destination only');
 const pg=(await import(process.argv[2])).default;client=new pg.Client({connectionString:url.href,connectionTimeoutMillis:5000});await client.connect();
 const q=async(sql,args=[])=>(await client.query(sql,args)).rows[0]?.v;
 const exec=sql=>client.query(sql);
 eq(Number(await q("select current_setting('server_version_num') v"))>=170000,true,'Native PostgreSQL17');
 eq(await q("select count(*)::int v from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname not in('pg_catalog','information_schema') and n.nspname not like 'pg_toast%' and c.relkind in('r','p','v','m','S','f')"),0,'Empty fixture database');
 await exec(`create role anon;create role authenticated;create role service_role;
 create schema auth;create schema private;
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('fixture.actor',true),'')::uuid$$;
 create function private.account_access_allowed() returns boolean language sql stable as $$select auth.uid() is not null$$;
 create function private.has_company_feature(uuid,text) returns boolean language sql stable as $$select true$$;
 create table public.companies(id uuid primary key);
 create table public.company_members(company_id uuid,user_id uuid);
 create table public.workers(id uuid primary key,company_id uuid,user_id uuid,status text);
 create table public.vehicles(id uuid primary key,company_id uuid);
 create table public.daily_reports(id uuid primary key,company_id uuid,site_id uuid,route_assignment_id uuid,report_date date,status text default 'draft');
 create table public.daily_report_workers(report_id uuid,worker_id uuid,primary key(report_id,worker_id));
 create table public.attendance_verifications(id uuid primary key,company_id uuid,worker_id uuid,site_id uuid,route_assignment_id uuid,vehicle_id uuid,event_type text,confirmed_at timestamptz,source_clock_in_id uuid,work_date date,daily_report_id uuid);
 create unique index one_end_per_source on public.attendance_verifications(source_clock_in_id) where source_clock_in_id is not null;
 create table public.route_stops(id uuid primary key,route_assignment_id uuid);
 create table private.route_journey_captures(id uuid primary key,company_id uuid,source_clock_in_id uuid,worker_id uuid,route_assignment_id uuid,route_stop_id uuid,work_date date,origin_kind text,payload jsonb,daily_report_id uuid);
 create table private.route_journey_visit_events(capture_id uuid primary key,source_clock_in_id uuid,route_stop_id uuid,kind text,start_capture_id uuid);
 create function private.save_route_journey_visit(cid uuid,sid uuid,stop uuid,origin text,payload jsonb,kind text,start_id uuid)
 returns uuid language plpgsql as $stub$
 declare s public.attendance_verifications%rowtype;
 begin
  select * into s from public.attendance_verifications where id=sid;
  insert into private.route_journey_captures values(cid,s.company_id,sid,s.worker_id,s.route_assignment_id,stop,s.work_date,origin,payload,null);
  insert into private.route_journey_visit_events values(cid,sid,stop,kind,start_id);
  return cid;
 end $stub$;`);
 const fixture=JSON.parse(await readFile('tool/fixtures/closed_day_actual_clock_sources.json','utf8'));
 eq(fixture.application_rows_read,false,'No production attendance rows');
 for(const f of fixture.functions){
  eq(createHash('md5').update(body(f.definition)).digest('hex'),f.source_md5,'Exact observed guard body '+f.signature);
  await exec(f.definition);
  eq(await q('select md5(prosrc) v from pg_proc where oid=$1::regprocedure',[f.signature]),f.source_md5,'Guard installed without weakening');
 }
 await exec(`create trigger attendance_shift_evidence_guard before insert or update on public.attendance_verifications for each row execute function private.validate_attendance_shift_evidence();
 create trigger route_journey_visit_before_clock_out before insert on public.attendance_verifications for each row execute function private.route_journey_visit_before_clock_out();`);
 await exec(await readFile('docs/candidates/closed_day_paid_hours_scope.sql.review-only','utf8'));
 const A=id(1),B=id(2),U=id(3),SITE=id(4),SITE2=id(5),W=id(10),WR=id(11),R=id(20),R2=id(21),R3=id(22),RR=id(23),ROUTE=id(30),STOP1=id(31),STOP2=id(32),D='2020-10-10';
 await client.query("select set_config('fixture.actor',$1,false)",[U]);
 await client.query('insert into companies values($1),($2)',[A,B]);
 await client.query('insert into company_members values($1,$2)',[A,U]);
 await client.query("insert into workers values($1,$2,$3,'active'),($4,$2,$3,'active')",[W,A,U,WR]);
 for(const [rid,sid,route,wid] of [[R,SITE,null,W],[R2,SITE2,null,W],[R3,SITE2,null,W],[RR,null,ROUTE,WR]]){
  await client.query('insert into daily_reports(id,company_id,site_id,route_assignment_id,report_date) values($1,$2,$3,$4,$5)',[rid,A,sid,route,D]);
  await client.query('insert into daily_report_workers values($1,$2)',[rid,wid]);
 }
 const start=async(n,wid,rid,sid,route,time)=>client.query("insert into attendance_verifications(id,company_id,worker_id,site_id,route_assignment_id,event_type,confirmed_at,daily_report_id) values($1,$2,$3,$4,$5,'clock_in',$6,$7)",[id(n),A,wid,sid,route,D+'T'+time+':00+09:00',rid]);
 const end=async(n,sn,time)=>client.query("insert into attendance_verifications(id,company_id,worker_id,site_id,route_assignment_id,event_type,confirmed_at,source_clock_in_id,daily_report_id) select $1,company_id,worker_id,site_id,route_assignment_id,'clock_out',$2,id,daily_report_id from attendance_verifications where id=$3",[id(n),D+'T'+time+':00+09:00',id(sn)]);
 const scope=(wid,rid)=>q('select checkout_paid_hours_candidate_private.read_closed_day_scope($1,$2,$3,$4) v',[A,wid,D,rid]);
 phase='exact-closed-set-and-final-report';
 await start(100,W,R,SITE,null,'09:00');
 eq((await scope(W,R)).reasons.includes('open_shift'),true,'Open shift cannot be called final');
 await end(101,100,'12:00');
 eq((await scope(W,R)).blocked,false,'One exact closed source pair accepted');
 await start(102,W,R2,SITE2,null,'13:00');await end(103,102,'17:00');
 const closed=await scope(W,R2);
 eq(closed.blocked,false,'All closed shifts use actual final report binding');
 eq(closed.closed_shift_set.length,2,'Both same-day shifts belong to canonical set');
 eq(closed.final_clock_out_id,id(103),'Final event comes from server records');
 eq((await scope(W,R)).reasons.includes('report_is_not_final_closed_shift'),true,'Earlier report cannot claim client final');
 eq(closed.daily_quantity_connected,false,'Reader does not pretend quantity is connected');
 eq(closed.source_fingerprint.length,64,'Stable SHA256 source fingerprint');
 eq((await scope(W,R2)).source_fingerprint,closed.source_fingerprint,'Unchanged read idempotent');
 await client.query("update daily_reports set status='signed' where id=$1",[R2]);
 eq((await scope(W,R2)).source_fingerprint,closed.source_fingerprint,'Signing does not mutate the physical evidence fingerprint');
 phase='same-day-reentry-and-no-hour-selection';
 await start(104,W,R3,SITE2,null,'18:00');
 const reopened=await scope(W,R2);
 eq(reopened.blocked,true,'New same-day start invalidates final-day scope');
 eq(reopened.source_fingerprint!==closed.source_fingerprint,true,'Reentry changes the closed-set fingerprint');
 await end(105,104,'19:00');
 eq((await scope(W,R2)).reasons.includes('report_is_not_final_closed_shift'),true,'Previous report is no longer final after later closed shift');
 eq((await scope(W,R3)).blocked,false,'New true final report accepted without any allowance selection');
 phase='route-intermediate-versus-final-clock-out';
 await client.query('insert into route_stops values($1,$2),($3,$2)',[STOP1,ROUTE,STOP2]);
 await start(200,WR,RR,null,ROUTE,'09:00');
 const visit=async(n,stop,kind,time,startId=null)=>client.query('select private.save_route_journey_visit($1,$2,$3,\'manual\',$4::jsonb,$5,$6)',[id(n),id(200),stop,JSON.stringify({attempted_at:D+'T'+time+':00+09:00'}),kind,startId]);
 await visit(201,STOP1,'start','09:30');
 await reject(()=>end(202,200,'12:00'),/finish current visit before clock-out/);
 eq(await q('select count(*)::int v from attendance_verifications where id=$1',[id(202)]),0,'Rejected intermediate clock-out rolls back');
 await visit(203,STOP1,'end','12:00',id(201));
 eq((await scope(WR,RR)).blocked,true,'Intermediate movement is not a final closed shift');
 await visit(204,STOP2,'start','13:00');
 await end(205,200,'17:00');
 const routeClosed=await scope(WR,RR);
 eq(routeClosed.blocked,false,'Actual route-before-clock-out guard closes final visit atomically');
 eq(routeClosed.final_clock_out_id,id(205),'Route final end binds exact clock-out event ID');
 eq(await q('select count(*)::int v from private.route_journey_visit_events where capture_id=$1 and kind=\'end\'',[id(205)]),1,'Exact observed guard persisted final end through declared synthetic store');
 phase='overlapping-source-evidence-and-same-minute';
 await start(107,W,R3,SITE2,null,'18:30');
 await reject(()=>end(108,107,'18:30'),/出勤と同じ時刻/);
 await end(108,107,'20:00');
 eq((await scope(W,R3)).reasons.includes('overlapping_shift_evidence'),true,'Overlapping exact source pairs block rather than invent a daily quantity');
 phase='scope-access-and-source-immutability';
 await reject(()=>q('select checkout_paid_hours_candidate_private.read_closed_day_scope($1,$2,$3,$4) v',[B,W,D,R3]),/scope unavailable/);
 await reject(()=>scope(WR,R3),/report scope unavailable/);
 await reject(()=>client.query("update attendance_verifications set confirmed_at=confirmed_at+interval '1 minute' where id=$1",[id(105)]),/chronology is immutable/);
 await reject(()=>end(106,104,'20:00'),/duplicate key/);
 eq(await q("select has_function_privilege('authenticated','checkout_paid_hours_candidate_private.read_closed_day_scope(uuid,uuid,date,uuid)','execute') v"),false,'No public/client capability exposed');
 for(const f of fixture.functions)eq(await q('select md5(prosrc) v from pg_proc where oid=$1::regprocedure',[f.signature]),f.source_md5,'Existing evidence guards unchanged');
 console.log(JSON.stringify({pass:true,checks,server_closed_shift_set_reader:true,final_report_binding_from_saved_clock_evidence:true,same_day_reentry_invalidates_scope:true,route_final_guard_source_bound:true,real_auth_tested:false,route_visit_store_explicitly_synthetic:true,daily_hours_input_ledger_implemented:false,payroll_quantity_connected:false,production_changed:false}));
}catch(e){console.error(JSON.stringify({pass:false,phase,code:e.code??null,message:String(e.message).slice(0,600),production_changed:false}));process.exitCode=1;}
finally{if(client)await client.end();}
