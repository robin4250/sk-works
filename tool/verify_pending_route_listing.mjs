import fs from 'node:fs';import path from 'node:path';import{pathToFileURL}from'node:url';import assert from'node:assert/strict';
const{PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);const db=new PGlite();let checks=0;
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const actor=id(1),company=id(2),worker=id(3),otherActor=id(4),otherCompany=id(5);
await db.exec(`create role anon;create role authenticated;create role service_role;
create schema auth;create schema private;
create function auth.uid()returns uuid language sql stable as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
create function private.account_access_allowed()returns boolean language sql stable as $$select current_setting('test.account_allowed',true)='true'$$;
create table public.company_members(company_id uuid,user_id uuid);
create table public.workers(id uuid,company_id uuid);
create table private.route_visit_reports(id uuid primary key,company_id uuid,created_by uuid,report_date date,created_at timestamptz,
 site_id uuid,site_name text,status text,work_description text,workers jsonb,
 representative_signature_json jsonb,supervisor_signature_json jsonb,
 source_clock_in_id uuid,route_assignment_id uuid,route_stop_id uuid,start_capture_id uuid,end_capture_id uuid);
revoke all on schema private from public,anon,authenticated,service_role;
insert into company_members values('${company}','${actor}'),('${company}','${otherActor}');
insert into workers values('${worker}','${company}');
set test.uid='${actor}';set test.account_allowed='true';`);
const signature=JSON.stringify({strokes:[[{x:0.2,y:0.3}]]});
for(const[n,who,co,status,date,supervisor,description]of[
 [10,actor,company,'reporter_signed','2024-01-01',null,'保存作業'],
 [11,actor,company,'reporter_signed','2025-02-02',null,'保存作業'],
 [12,actor,company,'draft','2025-02-03',null,'入力途中'],
 [13,actor,company,'completed','2025-02-04',signature,'確定済み'],
 [14,otherActor,company,'reporter_signed','2025-02-05',null,'他人'],
 [15,actor,otherCompany,'reporter_signed','2025-02-06',null,'他社'],
 [16,actor,company,'skipped','2025-02-07',null,'非作成'],
 [17,actor,company,'reporter_signed','2025-02-08',null,' '],
]){
 await db.query('insert into private.route_visit_reports values($1,$2,$3,$4,now(),$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16)',[id(n),co,who,date,id(100),'合成現場',status,description,JSON.stringify([{worker_id:worker}]),signature,supervisor,id(101),id(102),id(103),id(104),id(105)]);
}
const sql=fs.readFileSync('supabase/review/list_pending_route_visit_reports.sql.review-only','utf8');await db.exec(sql);checks++;
const before=(await db.query("select md5(jsonb_agg(to_jsonb(r)order by id)::text) h from private.route_visit_reports r")).rows[0].h;
await db.exec('set role authenticated');
const call=async(co=company,w=null,date=null,cursor=null,limit=200)=>(await db.query('select public.list_pending_route_visit_reports($1,$2,$3,$4,$5) v',[co,w,date,cursor,limit])).rows[0].v;
let all=await call();assert.equal(all.actor_id,actor);checks++;assert.equal(all.company_id,company);checks++;
assert.deepEqual(all.entries.map(e=>e.id),[id(10),id(11)]);checks++;
assert(all.entries.every(e=>e.reporter_signed===true&&e.supervisor_signed===false));checks++;
assert(!JSON.stringify(all).includes('signature_json'));checks++;
let page=await call(company,null,null,null,1);assert.equal(page.entries[0].id,id(10));checks++;
page=await call(company,null,'2024-01-01',id(10),1);assert.equal(page.entries[0].id,id(11));checks++;
assert.equal((await call(company,null,'2025-02-02',id(11),1)).entries.length,0);checks++;
assert.equal((await call(company,worker)).entries.length,2);checks++;
for(const args of [[otherCompany],[company,id(999)],[company,null,null,id(10)],[company,null,'2024-01-01',null],[company,null,'2025-02-05',id(14)],[company,null,'2025-02-06',id(15)],[company,null,null,null,0],[company,null,null,null,201],[company,null,null,null,null]]){
 await assert.rejects(call(...args),/pending_report_/);checks++;
}
await db.exec("set test.account_allowed='false'");await assert.rejects(call(),/account/);checks++;
await db.exec("set test.account_allowed='true';set test.uid=''");await assert.rejects(call(),/account/);checks++;
await db.exec(`set test.uid='${otherActor}'`);assert.deepEqual((await call()).entries.map(e=>e.id),[id(14)]);checks++;
await db.exec('reset role');
assert.equal((await db.query("select has_function_privilege('service_role','public.list_pending_route_visit_reports(uuid,uuid,date,uuid,integer)','execute')ok")).rows[0].ok,false);checks++;
assert.equal((await db.query("select has_function_privilege('anon','public.list_pending_route_visit_reports(uuid,uuid,date,uuid,integer)','execute')ok")).rows[0].ok,false);checks++;
assert.equal((await db.query("select md5(jsonb_agg(to_jsonb(r)order by id)::text) h from private.route_visit_reports r")).rows[0].h,before);checks++;
await assert.rejects(db.exec(sql),/fresh_install/);await db.exec('rollback');checks++;
const historySql=fs.readFileSync('supabase/review/list_site_route_visit_reports.sql.review-only','utf8');await db.exec(historySql);checks++;
await db.exec(`set test.uid='${actor}';set role authenticated`);
const history=async(category='saved',cursorDate=null,cursorId=null,site=id(100),limit=200)=>(await db.query('select public.list_site_route_visit_reports($1,$2,$3,$4,$5,$6,$7,$8,$9) v',[company,site,null,null,category,null,cursorDate,cursorId,limit])).rows[0].v;
assert.deepEqual((await history()).entries.map(e=>e.id),[id(13)]);checks++;
assert.deepEqual((await history('supervisorPending')).entries.map(e=>e.id),[id(10),id(11)]);checks++;
assert.equal((await history('supervisorPending',null,null,id(100),1)).entries[0].id,id(10));checks++;
assert.equal((await history('supervisorPending','2024-01-01',id(10),id(100),1)).entries[0].id,id(11));checks++;
assert.deepEqual((await history('inputPending')).entries,[]);checks++;
assert.deepEqual((await history('finalizationPending')).entries,[]);checks++;
for(const args of [['saved',null,null,id(999)],['supervisorPending','2025-02-05',id(14)],['wrong'],['saved',null,id(13)],['saved',null,null,null],['saved',null,null,id(100),null]]) {
 if(args[3]===id(999)){assert.equal((await history(...args)).entries.length,0);checks++;continue;}
 await assert.rejects(history(...args),/site_report_/);checks++;
}
await db.exec('reset role');
assert.equal((await db.query("select has_function_privilege('service_role','public.list_site_route_visit_reports(uuid,uuid,uuid,text,text,uuid,date,uuid,integer)','execute')ok")).rows[0].ok,false);checks++;
assert.equal((await db.query("select md5(jsonb_agg(to_jsonb(r)order by id)::text) h from private.route_visit_reports r")).rows[0].h,before);checks++;
await db.close();console.log(JSON.stringify({checks,productionApplied:false,actualFunction:true,authSessionHelper:'isolated fixture only'}));
