// Local synthetic database only; imports saved schema and review-only candidate.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
import {setupWorkerDocumentChangeFixture} from './worker_document_change_fixture_setup.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
assert.ok(path.isAbsolute(process.argv[2]??''),'First argument: absolute PGlite index path');
const {PGlite}=await import(pathToFileURL(process.argv[2]).href);
const db=new PGlite();
const uid=n=>`10000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const [company,worker,requirement,owner,reviewer,outsider,target]=[1,2,3,4,5,6,7].map(uid);
const photo=`${company}/${worker}/${requirement}/own-upload/front.jpg`;
const source=name=>fs.readFileSync(path.join(root,name),'utf8');
let groups=0;
const pass=label=>{groups++;console.log(`PASS ${groups}: ${label}`)};
const actor=async id=>{await db.exec('reset role');await db.query("select set_config('fixture.uid',$1,false)",[id]);await db.exec('set role authenticated')};
const rpc=async(action,data={})=>(await db.query('select public.worker_document_change($1,$2::jsonb) result',[action,JSON.stringify(data)])).rows[0].result;
const denied=async(sql,code='42501')=>assert.rejects(db.exec(sql),e=>e.code===code);
const denyRpc=async(a,d,code='42501')=>assert.rejects(rpc(a,d),e=>e.code===code);
const official=async()=>(await db.query('select * from public.worker_document_statuses where id=$1',[target])).rows[0];
try {
 await setupWorkerDocumentChangeFixture(db);
 await db.exec("select set_config('fixture.session','live',false)");
 await actor(owner);
 await db.exec("select set_config('fixture.session','revoked',false)");await denyRpc('capability');
 await db.exec("select set_config('fixture.session','live',false)");
 pass('revoked session blocks API, live session permitted');
 await db.exec('reset role');await db.exec(`update auth.sessions set not_after=clock_timestamp()-interval '1 minute' where id='${owner}'`);await actor(owner);await denyRpc('capability');
 await db.exec('reset role');await db.exec(`update auth.sessions set not_after=null,user_id='${reviewer}' where id='${owner}'`);await actor(owner);await denyRpc('capability');
 await db.exec('reset role');await db.exec(`update auth.sessions set user_id='${owner}' where id='${owner}';update auth.users set banned_until=clock_timestamp()+interval '1 hour' where id='${owner}'`);await actor(owner);await denyRpc('capability');
 await db.exec('reset role');await db.exec(`update auth.users set banned_until=null,is_anonymous=true where id='${owner}'`);await actor(owner);await denyRpc('capability');
 await db.exec('reset role');await db.exec(`update auth.users set is_anonymous=false where id='${owner}'`);await actor(owner);
 pass('actual session helper rejects expiry, foreign session, banned and anonymous users');
 assert.deepEqual(await rpc('capability'),{version:1,change_requests_available:true,new_upload_available:false,max_photos:20,self_approval_allowed:false});
 await db.exec(`insert into public.worker_document_statuses(id,company_id,worker_id,requirement_id,updated_by) values('${target}','${company}','${worker}','${requirement}','${owner}')`);
 await db.exec(`update public.worker_document_statuses set status='submitted',attachment_path='${photo}',notes='original',updated_by='${owner}' where id='${target}'`);
 pass('actual schema/history/photo triggers permit proven initial placeholder registration');
 const original=await official();
 await denied(`update public.worker_document_statuses set notes='bypass' where id='${target}'`);
 await db.exec("select set_config('worker_document_change.approved','true',false)");
 await denied(`update public.worker_document_statuses set notes='GUC bypass' where id='${target}'`);
 await denied(`delete from public.worker_document_status_history`);
 await denied(`insert into private.worker_document_apply_tickets values('${target}','${uid(90)}','${owner}',txid_current(),'{}','{}')`);
 await db.exec(`delete from public.worker_document_statuses where id='${target}'`);assert.ok(await official());
 pass('old direct edit/delete, fake GUC, history tampering and private ticket injection rejected');
 const proposal={attachment_paths:[photo],expires_at:'2027-01-01',notes:'approved draft'};
 const command=id=>({request_id:uid(id),status_id:target,expected_updated_at:original.updated_at,proposed:proposal});
 const prepared=await rpc('prepare',command(20));assert.equal(prepared.status,'draft');assert.equal(prepared.previous.notes,'original');
 assert.deepEqual(await rpc('prepare',command(20)),prepared);
 await denyRpc('prepare',{...command(20),proposed:{...proposal,notes:'different'}},'23505');
 await denyRpc('prepare',{...command(21),proposed:{...proposal,attachment_paths:[photo.replace('front','new')]}},'22023');
 assert.equal((await official()).notes,'original');
 await rpc('submit',{request_id:uid(20)});await rpc('submit',{request_id:uid(20)});
 await denyRpc('approve',{request_id:uid(20)});
 pass('fixed prepare/submit retries stable, no official write, new upload and self approval denied');
 await actor(outsider);await denyRpc('detail',{request_id:uid(20)});assert.deepEqual(await rpc('list'),[]);
 await actor(reviewer);await denied(`update public.worker_document_statuses set notes='manager bypass',updated_by='${reviewer}' where id='${target}'`);
 await denyRpc('approve',{request_id:uid(20)},'22023');
 await db.exec('reset role');await db.exec(`insert into storage.objects(bucket_id,name) values('worker-documents','${photo}')`);await actor(reviewer);
 const approved=await rpc('approve',{request_id:uid(20)});assert.equal(approved.status,'approved');assert.deepEqual(await rpc('approve',{request_id:uid(20)}),approved);
 assert.equal((await official()).notes,proposal.notes);
 await db.exec('reset role');assert.equal((await db.query('select count(*)::int n from private.worker_document_apply_tickets')).rows[0].n,0);
 pass('foreign actor and manager bypass blocked; missing saved object fails; other reviewer applies once and consumes ticket');
 await actor(owner);const latest=await official();
 const prepare=async id=>rpc('prepare',{...command(id),expected_updated_at:latest.updated_at,proposed:{...proposal,notes:`request ${id}`}});
 await prepare(22);const cancel=await rpc('cancel',{request_id:uid(22)});assert.deepEqual(await rpc('cancel',{request_id:uid(22)}),cancel);
 await prepare(23);await rpc('submit',{request_id:uid(23)});await actor(reviewer);
 const reject=await rpc('reject',{request_id:uid(23),reason:'needs review'});assert.deepEqual(await rpc('reject',{request_id:uid(23),reason:'needs review'}),reject);
 await denyRpc('approve',{request_id:uid(23)});assert.equal((await official()).notes,proposal.notes);
 pass('cancel/reject receipts idempotent; opposite final action rejected; official preserved');
 await actor(owner);await prepare(24);await rpc('submit',{request_id:uid(24)});await actor(reviewer);
 await denied(`update public.worker_document_statuses set status='verified',notes='mixed',updated_by='${reviewer}' where id='${target}'`);
 await denied(`update public.worker_document_statuses set status='verified',updated_by='${owner}' where id='${target}'`);
 await db.exec(`update public.worker_document_statuses set status='verified',original_verified=true,updated_by='${reviewer}',updated_at=clock_timestamp() where id='${target}'`);
 await denyRpc('approve',{request_id:uid(24)},'40001');
 pass('verification-only manager update allowed; mixed content/updater spoof rejected; old snapshot CAS blocks approval');
 await actor(owner);const now=await official();await rpc('prepare',{...command(25),expected_updated_at:now.updated_at});await rpc('submit',{request_id:uid(25)});
 await actor(reviewer);await db.exec('begin');await rpc('approve',{request_id:uid(25)});await db.exec('rollback');
 assert.equal((await rpc('detail',{request_id:uid(25)})).status,'pending');assert.deepEqual((await official()).updated_at,now.updated_at);
 await db.exec('reset role');await db.exec(`delete from public.company_members where user_id='${owner}'`);await actor(reviewer);await denyRpc('approve',{request_id:uid(25)});
 pass('transaction rollback preserves official/request; current requester membership revocation blocks final apply');
 await db.exec('reset role');await db.exec(`insert into public.company_members values('${company}','${owner}','member')`);await actor(owner);
 await db.exec(`delete from storage.objects where name='${photo}'`);assert.equal((await db.query('select count(*)::int n from storage.objects')).rows[0].n,1);
 await actor(owner);
 for (const proposed of [null,{...proposal,attachment_paths:null},{...proposal,attachment_paths:[null]},{...proposal,attachment_paths:[42]},{...proposal,notes:''},{...proposal,notes:' padded '},{...proposal,expires_at:'invalid'}]) {
  await assert.rejects(rpc('prepare',{...command(30),expected_updated_at:(await official()).updated_at,proposed}));
 }
 await db.exec('reset role');await db.exec(`update public.document_requirements set is_active=false where id='${requirement}'`);await actor(reviewer);
 await denyRpc('approve',{request_id:uid(25)});
 await db.exec('reset role');await db.exec(`update public.document_requirements set is_active=true where id='${requirement}'`);await actor(reviewer);
 await denied(`delete from public.worker_document_statuses where id='${target}'`);
 pass('malformed/null/nonstring/date/empty notes rejected; hidden requirement and manager delete fail closed');
 // A pre-audit empty legacy row cannot prove that this is its first registration.
 await db.exec('reset role');
 const legacyWorker=uid(40),legacyTarget=uid(41);
 await db.exec(`insert into public.workers values('${legacyWorker}','${company}','${owner}');
 insert into public.worker_document_statuses(id,company_id,worker_id,requirement_id,updated_by)
 values('${legacyTarget}','${company}','${legacyWorker}','${requirement}','${reviewer}');
 delete from public.worker_document_status_history where source_status_id='${legacyTarget}'`);
 await actor(owner);
 await denied(`update public.worker_document_statuses set notes='unproven first save',updated_by='${owner}' where id='${legacyTarget}'`);
 await denied(`insert into public.worker_document_status_history(company_id,source_status_id,worker_id,requirement_id,operation,status) values('${company}','${legacyTarget}','${legacyWorker}','${requirement}','insert','not_submitted')`);
 pass('unproven legacy placeholder fails closed; caller cannot forge positive INSERT history');
 await db.exec("select set_config('fixture.blocked','yes',false)");await denyRpc('detail',{request_id:uid(25)});
 pass('saved attachment retention policy and current account gate preserved');
 // Existing personal-document approval must remain usable, but cannot self-approve.
 await db.exec("select set_config('fixture.blocked','',false)");
 await db.exec('reset role');
 const legacyWorker2=uid(50),legacyTarget2=uid(51),legacyRequest=uid(52),legacyOldPhoto=photo.replace(worker,legacyWorker2),legacyPhoto=photo.replace(worker,legacyWorker2).replace('front.jpg','legacy-new.pdf');
 await db.exec(`insert into public.workers values('${legacyWorker2}','${company}','${owner}');
 insert into public.worker_document_statuses(id,company_id,worker_id,requirement_id,status,attachment_path,notes,updated_by)
 values('${legacyTarget2}','${company}','${legacyWorker2}','${requirement}','submitted','${legacyOldPhoto}','before','${owner}');
 insert into storage.objects(bucket_id,name) values('worker-documents','${legacyPhoto}');
 insert into private.document_submissions(id,company_id,worker_id,requirement_id,requested_by,previous,attachment_path,notes,status)
 select '${legacyRequest}','${company}','${legacyWorker2}','${requirement}','${owner}',to_jsonb(s),'${legacyPhoto}','after','pending'
 from public.worker_document_statuses s where s.id='${legacyTarget2}';
 insert into public.company_approval_assignees values('${company}','${owner}'),('${company}','${reviewer}');
 update public.company_members set role='member' where company_id='${company}' and user_id='${reviewer}';`);
 await actor(owner);await denyRpc('detail',{request_id:uid(999)});
 await assert.rejects(db.query('select private.personal_document_submission($1,$2::jsonb)', ['approve',JSON.stringify({id:legacyRequest})]),e=>e.code==='42501');
 await actor(reviewer);await db.query('select private.personal_document_submission($1,$2::jsonb)', ['approve',JSON.stringify({id:legacyRequest})]);
 await db.exec('reset role');
 assert.equal((await db.query(`select notes from public.worker_document_statuses where id='${legacyTarget2}'`)).rows[0].notes,'after');
 assert.equal((await db.query('select count(*)::int n from private.worker_document_legacy_tickets')).rows[0].n,0);
 pass('legacy personal-document approval applies once and consumes its ticket; self approval denied');
 const firstWorker=uid(60),firstRequest=uid(61),firstPhoto=photo.replace(worker,uid(60)).replace('front.jpg','first.pdf');
 await db.exec(`insert into public.workers values('${firstWorker}','${company}','${owner}');
 insert into storage.objects(bucket_id,name) values('worker-documents','${firstPhoto}');
 insert into private.document_submissions(id,company_id,worker_id,requirement_id,requested_by,previous,attachment_path,notes,status)
 values('${firstRequest}','${company}','${firstWorker}','${requirement}','${owner}',null,'${firstPhoto}','first approved','pending');`);
 await actor(reviewer);await db.query('select private.personal_document_submission($1,$2::jsonb)', ['approve',JSON.stringify({id:firstRequest})]);
 await db.exec('reset role');
 assert.equal((await db.query(`select notes from public.worker_document_statuses where worker_id='${firstWorker}'`)).rows[0].notes,'first approved');
 assert.equal((await db.query('select count(*)::int n from private.worker_document_legacy_tickets')).rows[0].n,0);
 pass('legacy initial document approval inserts once for a non-admin assigned reviewer');
 // A legacy approval must not overwrite a document changed after submission.
 const staleWorker=uid(70),staleTarget=uid(71),staleRequest=uid(72),stalePhoto=photo.replace(worker,uid(70)).replace('front.jpg','stale.pdf');
 await db.query("select set_config('fixture.uid',$1,false)",[owner]);
 await db.exec(`insert into public.workers values('${staleWorker}','${company}','${owner}');
 insert into public.worker_document_statuses(id,company_id,worker_id,requirement_id,status,notes,updated_by)
 values('${staleTarget}','${company}','${staleWorker}','${requirement}','submitted','original','${owner}');
 insert into storage.objects(bucket_id,name) values('worker-documents','${stalePhoto}');
 insert into private.document_submissions(id,company_id,worker_id,requirement_id,requested_by,previous,attachment_path,notes,status)
 select '${staleRequest}','${company}','${staleWorker}','${requirement}','${owner}',to_jsonb(s),'${stalePhoto}','stale proposal','pending'
 from public.worker_document_statuses s where s.id='${staleTarget}';`);
 // Simulate a previously authorized concurrent change, bypassing only the test fixture trigger.
 await db.exec(`alter table public.worker_document_statuses disable trigger zz_worker_document_change_guard;
 update public.worker_document_statuses set notes='newer approved content' where id='${staleTarget}';
 alter table public.worker_document_statuses enable trigger zz_worker_document_change_guard;`);
 await actor(reviewer);
 await assert.rejects(db.query('select private.personal_document_submission($1,$2::jsonb)', ['approve',JSON.stringify({id:staleRequest})]));
 await db.exec('reset role');
 assert.equal((await db.query(`select notes from public.worker_document_statuses where id='${staleTarget}'`)).rows[0].notes,'newer approved content');
 assert.equal((await db.query(`select status from private.document_submissions where id='${staleRequest}'`)).rows[0].status,'pending');
 assert.equal((await db.query('select count(*)::int n from private.worker_document_legacy_tickets')).rows[0].n,0);
 pass('stale legacy approval cannot overwrite newer content or leave a ticket');
 console.log(`PASS: ${groups} boundary groups; ${process.argv[3]==='postgres'?'native PostgreSQL17 synthetic fixture':'PGlite synthetic fixture'}; real JWT/production not exercised`);
} finally {await db.close()}
