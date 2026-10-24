// Reuses the existing isolated official GoTrue/PostgREST checkout setup. Real
// JWTs are issued by local GoTrue; auth.uid/session tables are never replaced.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
const original=await readFile('tool/company_checkout_real_gotrue_e2e.mjs','utf8');
const marker=" phase='real-jwt-expiry-and-revocation-observation';";
const revokedMarker=" eq((await db.query('select count(*)::int n from auth.sessions where id=$1',[revokedClaims.session_id])).rows[0].n,0);";
assert.equal(original.split(marker).length,2);assert.equal(original.split(revokedMarker).length,2);
const extension=String.raw`
 phase='paid-hours-live-session-public-api';
 const hourSources=JSON.parse(await read('tool/fixtures/checkout_paid_hours_actual_sources.json'));
 const clockSources=JSON.parse(await read('tool/fixtures/closed_day_actual_clock_sources.json'));
 await db.query("alter table workers add column user_id uuid,add column status text default 'active';create function private.has_company_feature(cid uuid,feature text) returns boolean language sql stable as $$select exists(select 1 from public.company_members where company_id=cid and user_id=auth.uid() and role in('owner','admin','manager'))$$;create table vehicles(id uuid primary key,company_id uuid);create table attendance_verifications(id uuid primary key,company_id uuid,worker_id uuid,site_id uuid,route_assignment_id uuid,vehicle_id uuid,event_type text,confirmed_at timestamptz,source_clock_in_id uuid,work_date date,daily_report_id uuid);create unique index hour_live_one_end on attendance_verifications(source_clock_in_id) where source_clock_in_id is not null;create table route_stops(id uuid,route_assignment_id uuid);create table private.route_journey_captures(id uuid,source_clock_in_id uuid);create table private.route_journey_visit_events(capture_id uuid,source_clock_in_id uuid,start_capture_id uuid,kind text,route_stop_id uuid);");
 await db.query('update workers set user_id=$1 where id=$2',[users.owner.id,W]);
 await db.query("update company_members set role='employee' where company_id=$1 and user_id=$2",[A,users.revoked.id]);
 await db.query('drop function payroll_scope_private.lock_scopes(jsonb,boolean)');
 await db.query(hourSources.functions.find(f=>f.signature==='payroll_scope_private.lock_scopes(jsonb,boolean)').definition);
 await db.query(clockSources.functions.find(f=>f.signature==='private.validate_attendance_shift_evidence()').definition);
 await db.query('create trigger hour_live_clock_guard before insert or update on attendance_verifications for each row execute function private.validate_attendance_shift_evidence()');
 for(const f of hourSources.functions.filter(f=>/report_basis|\.aggregate\(|\.resolve\(|^sign_daily_report/.test(f.signature))){
  eq(createHash('md5').update(body(f.definition)).digest('hex'),f.source_md5);await db.query(f.definition);
 }
 await db.query(await read('docs/candidates/closed_day_paid_hours_scope.sql.review-only'));
 await db.query(await read('docs/candidates/checkout_paid_hours_ledger.sql.review-only'));
 const hoursPatch=path.join(workdir,'paid-hours-patches.sql');
 await run('python3',['tool/prepare_checkout_paid_hours.py','--output',hoursPatch]);
 await db.query(await fs.readFile(hoursPatch,'utf8'));
 await db.query(await read('tool/fixtures/checkout_paid_hours_session_helper.sql'));
 await db.query(await read('docs/candidates/checkout_paid_hours_api.sql.review-only'));
 const hourId=id(950),revokedWorker=id(951);
 await db.query('insert into company_common_allowance_private.state values($1,1)',[A]);
 await db.query("insert into company_common_allowance_private.items(id,company_id,payroll_type,section,unit,name,amount_yen) values($1,$2,'daily','earning','hour','JWT時間手当',1000)",[hourId,A]);
 await db.query("insert into workers(id,company_id,name,user_id) values($1,$2,'Live session owner',$3)",[revokedWorker,A,users.revoked.id]);
 await db.query('insert into worker_payroll_settings(company_id,worker_id) values($1,$2)',[A,revokedWorker]);
 await db.query("notify pgrst,'reload schema'");
 await new Promise(resolve=>setTimeout(resolve,1000));
 const hourPayload={...draftBody,p_report_date:'2026-10-11',p_workers:[{worker_id:W,allowance_label:'JWT時間手当',allowance_amount:0,work_category:'day',company_allowance_selections:{contract_version:1,items:[{origin:'company_common',id:hourId,generation:null,registration_version:1,name_snapshot:'JWT時間手当',unit:'hour'}]}}]};
 response=await rpc('save_daily_report_destination_draft',hourPayload,owner);eq(response.status,200);const hourReport=await response.json();
 const revokedPayload={...draftBody,p_report_date:'2026-10-12',p_workers:[{worker_id:revokedWorker,allowance_label:'',allowance_amount:0,work_category:'day'}]};
 response=await rpc('save_daily_report_destination_draft',revokedPayload,owner);eq(response.status,200);const revokedHourReport=await response.json();
 for(const [rid,wid,day,n]of[[hourReport,W,'2026-10-11',960],[revokedHourReport,revokedWorker,'2026-10-12',970]]){
  await db.query("insert into attendance_verifications(id,company_id,worker_id,site_id,event_type,confirmed_at,daily_report_id) values($1,$2,$3,$4,'clock_in',$5,$6)",[id(n),A,wid,SITE,day+'T09:00:00+09:00',rid]);
  await db.query("insert into attendance_verifications(id,company_id,worker_id,site_id,event_type,confirmed_at,source_clock_in_id,daily_report_id) values($1,$2,$3,$4,'clock_out',$5,$6,$7)",[id(n+1),A,wid,SITE,day+'T17:00:00+09:00',id(n),rid]);
 }
 const hourRead={p_report_id:hourReport,p_worker_id:W};
 response=await rpc('read_checkout_paid_work_hours',hourRead,owner);eq(response.status,200);const initialHours=await response.json();
 eq(initialHours.actor_id,users.owner.id);eq(initialHours.hours,null);eq(initialHours.required,true);eq(initialHours.editable,true);
 for(const name of ['othercompany','outsider']){
  response=await rpc('read_checkout_paid_work_hours',hourRead,sessions[name].access_token);assert.ok(response.status>=400&&response.status<500);checks++;
 }
 response=await rpc('read_checkout_paid_work_hours',hourRead,sessions.revoked.access_token);assert.ok(response.status>=400&&response.status<500);checks++;
 response=await rpc('read_checkout_paid_work_hours',hourRead);assert.ok(response.status>=400&&response.status<500);checks++;
 response=await request('/rest/v1/rpc/read_checkout_paid_work_hours',{service:true,body:hourRead});assert.ok(response.status>=400&&response.status<500);checks++;
 const hourSave={...hourRead,p_hours:7.25,p_expected_revision:initialHours.revision,p_expected_scope:initialHours.scope_fingerprint};
 response=await rpc('save_checkout_paid_work_hours',hourSave,owner);
 if(response.status!==200){
  const failure=await response.clone().json().catch(()=>({}));
  // Isolated synthetic fixture only: no headers, keys, JWTs or Auth rows.
  console.error(JSON.stringify({paid_hours_save_diagnostic:{status:response.status,
   sql_code:typeof failure.code==='string'?failure.code:null,
   message:typeof failure.message==='string'?failure.message.slice(0,500):null},production_changed:false}));
 }
 eq(response.status,200);eq((await response.json()).hours,7.25);
 response=await rpc('save_checkout_paid_work_hours',{...hourSave,p_hours:8},owner);assert.ok(response.status>=400&&response.status<500);checks++;
 for(const role of ['representative','supervisor']){
  response=await rpc('save_daily_report_signature',{p_report_id:hourReport,p_role:role,p_signer_name:'Real JWT '+role,p_signature_json:signature},owner);assert.ok([200,204].includes(response.status));checks++;
 }
 const actualHours=(await db.query('select gross_pay,detail from payroll_statements where company_id=$1 and worker_id=$2 and period_start=$3',[A,W,'2026-10-01'])).rows[0];
 eq(actualHours.gross_pay,17250);eq(actualHours.detail.unit_resolution.items.find(i=>i.id===hourId).amount_yen,7250);
 response=await rpc('read_checkout_paid_work_hours',{p_report_id:revokedHourReport,p_worker_id:revokedWorker},sessions.revoked.access_token);eq(response.status,200);
 const preservedOwner=await request('/auth/v1/user',{method:'GET',token:owner});eq(preservedOwner.status,200);eq((await preservedOwner.json()).id,users.owner.id);
 eq((await db.query('select count(*)::int n from auth.sessions where id=$1 and user_id=$2',[ownerSession,users.owner.id])).rows[0].n,1);
 eq((await db.query("select md5(pg_get_functiondef('auth.uid()'::regprocedure)) value")).rows[0].value,authUidBefore);
 console.log(JSON.stringify({pass:true,paid_hours_real_gotrue_postgrest:true,same_owner_uid_and_session_preserved:true,other_worker_company_anonymous_service_denied:true,explicit_hours:7.25,allowance:7250,production_changed:false}));
`;
const revokedCheck=String.raw`
 response=await rpc('read_checkout_paid_work_hours',{p_report_id:revokedHourReport,p_worker_id:revokedWorker},sessions.revoked.access_token);
 assert.ok(response.status>=400&&response.status<500);checks++;
 console.log(JSON.stringify({pass:true,paid_hours_real_revoked_session_denied_before_jwt_expiry:true,production_changed:false}));
`;
const dir=await mkdtemp(join(tmpdir(),'paid-hours-real-gotrue-'));
try{
 const generated=original.replace(marker,()=>extension+marker).replace(revokedMarker,()=>revokedMarker+revokedCheck);
 const file=join(dir,'proof.mjs');await writeFile(file,generated);
 const result=spawnSync(process.execPath,[file],{stdio:'inherit',env:process.env});
 if(result.error)throw result.error;process.exitCode=result.status??1;
}finally{await rm(dir,{recursive:true,force:true});}
