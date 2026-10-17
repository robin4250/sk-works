import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createHash,createHmac,randomUUID} from 'node:crypto';
import {r20Setup,r20Verify,r20Http,r20Restore} from './r20_fixture.mjs';
const catalog22=JSON.parse(await fs.readFile(new URL('./r22_catalog.json',import.meta.url),'utf8'));
const signature22='public.decide_attendance_correction_request(uuid,text,text)';
let original22;let checks22=0;
const metadata22=async db=>(await db.query(`select p.oid::text,pg_get_functiondef(p.oid) definition,pg_get_userbyid(p.proowner) owner,p.proacl::text acl,p.proconfig::text config,p.prosecdef from pg_proc p where p.oid=$1::regprocedure`,[signature22])).rows;
const actor22=async(db,actor,fn)=>{await db.exec('set role authenticated');try{await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:actor})]);return await fn();}finally{await db.exec('reset role').catch(()=>{});}};
const snapshot22=async db=>(await db.query(`select jsonb_build_object('requests',(select jsonb_agg(to_jsonb(x) order by id) from public.attendance_correction_requests x),'items',(select jsonb_agg(to_jsonb(x) order by id) from public.attendance_correction_items x),'entries',(select jsonb_agg(to_jsonb(x) order by id) from public.attendance_entries x),'leave',(select jsonb_agg(to_jsonb(x) order by id) from public.paid_leave_requests x),'notifications',(select jsonb_agg(to_jsonb(x) order by id) from public.app_notifications x)) s`)).rows[0].s;
async function r22Setup(db,id){
 await db.exec(`alter table public.attendance_correction_requests add status text default 'submitted',add requested_by uuid default '${id(1)}',add request_kind text default 'past_attendance',add reviewed_by uuid,add reviewed_at timestamptz,add review_note text,add updated_at timestamptz;
 alter table public.attendance_correction_items add attendance_entry_id uuid,add proposed_snapshot jsonb,add created_at timestamptz default '2026-10-01';
 update public.attendance_correction_items set proposed_snapshot=jsonb_build_object('workerId','${id(80)}','siteId','${id(81)}','date','2026/10/01','manDays',1.5,'overtimeHours',2,'earlyHours',0.5,'nightHours',1,'allowanceYen',3000,'allowanceNames',jsonb_build_array('fixture'),'notes','fixture');
 create table public.company_approval_assignees(company_id uuid,user_id uuid);
 insert into public.company_approval_assignees values('${id(10)}','${id(1)}'),('${id(10)}','${id(2)}'),('${id(11)}','${id(5)}');
 create table public.attendance_entries(id uuid default gen_random_uuid(),company_id uuid,work_date date,worker_id uuid,site_id uuid,work_category text,base_man_days numeric,overtime_hours numeric,early_hours numeric,night_hours numeric,allowance_amount integer,allowance_names text[],notes text,created_by uuid,updated_by uuid,updated_at timestamptz,source_report_id uuid);
 create table public.paid_leave_requests(id uuid,company_id uuid,worker_id uuid,leave_date date,status text,reviewed_by uuid,reviewed_at timestamptz,review_note text,updated_at timestamptz);
 create table public.sites(id uuid,company_id uuid,name text);
 create table public.daily_report_workers(report_id uuid,worker_id uuid,overtime_hours numeric,early_hours numeric,night_hours numeric,allowance_amount integer,allowance_label text);
 insert into public.paid_leave_requests values('${id(89)}','${id(10)}','${id(80)}','2026-10-01','approved',null,null,null,null);`);
 await db.exec(catalog22[0].definition);
 await db.exec(`revoke all on function ${signature22} from public,anon;grant execute on function ${signature22} to authenticated,service_role`);
 original22=await metadata22(db);
 assert.equal(original22[0].acl,catalog22[0].acl);checks22++;
}
async function r22Verify(db,id){
 // Original SECURITY DEFINER bypasses SELECT RLS and publishes the linked item.
 await db.exec('begin');try{
 await actor22(db,id(2),()=>db.query('select public.decide_attendance_correction_request($1,$2)',[id(21),'approve']));
 assert.equal((await db.query('select count(*)::int n from public.attendance_entries')).rows[0].n,1);checks22++;
 }finally{await db.exec('rollback');}
 await db.exec(await fs.readFile(new URL('./r22_candidate.sql.review-only',import.meta.url),'utf8'));
 const before=await snapshot22(db);
 for(const actor of [id(2),id(4)])for(const decision of ['approve','reject']){
 await actor22(db,actor,()=>assert.rejects(db.query('select public.decide_attendance_correction_request($1,$2)',[id(21),decision]),e=>e.code==='42501'));checks22++;
 assert.deepEqual(await snapshot22(db),before);checks22++;
 }
 // Existing company approval checks still refuse an unrelated company assignee.
 await actor22(db,id(5),()=>assert.rejects(db.query('select public.decide_attendance_correction_request($1,$2)',[id(20),'approve']),/approval assignee permission required/));checks22++;
 // Verify ordinary permitted decisions and Master decisions, each rolled back.
 for(const [actor,request]of [[id(2),id(20)],[id(1),id(21)]])for(const decision of ['approve','reject']){
 await db.exec('begin');try{
 if(actor===id(1))await db.query('update public.attendance_correction_requests set requested_by=$1 where id=$2',[id(2),request]);
 const result=await actor22(db,actor,()=>db.query('select public.decide_attendance_correction_request($1,$2) result',[request,decision]));
 assert.equal(result.rows[0].result,decision==='approve'?'approved':'rejected');checks22++;
 const entries=(await db.query('select * from public.attendance_entries')).rows;
 if(decision==='approve'){
 assert.equal(entries.length,1);assert.equal(Number(entries[0].base_man_days),1.5);assert.equal(Number(entries[0].overtime_hours),2);assert.equal(entries[0].allowance_amount,3000);assert.deepEqual(entries[0].allowance_names,['fixture']);checks22+=5;
 assert.equal((await db.query('select status from public.paid_leave_requests')).rows[0].status,'cancelled');checks22++;
 }else{assert.equal(entries.length,0);checks22++;}
 }finally{await db.exec('rollback');}
 assert.deepEqual(await snapshot22(db),before);checks22++;
 }
 const after=await metadata22(db);for(const key of ['oid','owner','acl','config','prosecdef']){assert.equal(after[0][key],original22[0][key]);checks22++;}
}
async function r22Http(db,id,token,origin){
 await db.exec("notify pgrst, 'reload schema'");
 const before=await snapshot22(db);
 for(const actor of [id(2),id(4)])for(const decision of ['approve','reject']){
 const r=await fetch(new URL('/rpc/decide_attendance_correction_request',origin),{method:'POST',redirect:'error',headers:{Authorization:'Bearer '+token(actor),'Content-Type':'application/json'},body:JSON.stringify({p_request_id:id(21),p_decision:decision})});assert.equal(r.status,403);checks22++;
 }
 assert.deepEqual(await snapshot22(db),before);checks22++;
}
async function r22Restore(db){
 await db.exec(catalog22[0].definition);assert.deepEqual(await metadata22(db),original22);checks22++;
 await db.exec(catalog22[0].definition.replace('AS $function$','AS $function$ -- fixture-only drift\n'));
 const drifted=await metadata22(db);await assert.rejects(db.exec(await fs.readFile(new URL('./r22_candidate.sql.review-only',import.meta.url),'utf8')),e=>e.code==='55000');checks22++;await db.exec('rollback');assert.deepEqual(await metadata22(db),drifted);checks22++;
 await db.exec(catalog22[0].definition);assert.deepEqual(await metadata22(db),original22);checks22++;
 console.log(`PASS ${checks22} R22 correction entry guard checks; Master publication and creation-before-lineage remain explicit blockers.`);
}
const source22=await fs.readFile(new URL('./r21_fixture.mjs',import.meta.url),'utf8');
const source19=await fs.readFile(new URL('./r19_fixture.mjs',import.meta.url),'utf8');
assert.equal(createHash('sha256').update(source19).digest('hex'),'4a07279de9ee5e4d72075efa994737f419d28a7fad5f6d12901a1447dc611586');
const self22=await fs.readFile(fileURLToPath(import.meta.url),'utf8');
let adapted22=self22.slice(0,self22.indexOf('const source22='))+'\n'+source22.slice(0,source22.indexOf("if(fileURLToPath(import.meta.url)===process.argv[1])")).replace(/^import .*;\n/gm,'')+'\n'+source19.replace(/^import .*;\n/gm,'');
for(const [anchor,replacement]of [
 ['  const before=await Promise.all','  await r21Setup(db,id);await r22Setup(db,id);\n  const before=await Promise.all'],
 ['  const helpers=(await db.query','  await r21Verify(db,id);await r22Verify(db,id);\n  const helpers=(await db.query'],
 ["    console.log('VERIFIED actual PG17","    await r21Http(db,id,token,origin);await r22Http(db,id,token,origin);\n    console.log('VERIFIED actual PG17"],
 ['  for(let i=0;i<tables.length;i++){','  await r22Restore(db);await r21Restore(db);\n  for(let i=0;i<tables.length;i++){']
 ]){assert.equal(adapted22.split(anchor).length,2);adapted22=adapted22.replace(anchor,replacement);}
const temp22=new URL(`./.r22-${randomUUID()}.mjs`,import.meta.url);
try{await fs.writeFile(temp22,adapted22,{mode:0o600,flag:'wx'});await import(temp22.href);}finally{await fs.unlink(temp22).catch(()=>{});}
