// Reuse the existing exact-source fixture; add requests that predate installation.
// Disposable synthetic DB only: no Supabase/Storage API or production connection.
import fs from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
const fixture = new URL('./verify_qualification_admin_saved_photos.mjs', import.meta.url);
let source = (await fs.readFile(fixture, 'utf8')).replaceAll('import.meta.url', JSON.stringify(fixture.href));
const before = ' await db.exec(candidate);\n // Inspect the actually installed function:';
const after = ' const adminBody=';
if (source.split(before).length !== 2 || source.split(after).length !== 2) throw new Error('Legacy fixture anchors drift');
const prepare = `
 // Seed genuine legacy requests through the unmodified router BEFORE new DDL.
 const legacyRpc=async(action,data={})=>(await db.query('select private.personal_qualification_submission($1,$2::jsonb) v',[action,JSON.stringify(data)])).rows[0].v;
 await db.exec("set test.uid='"+user+"'");
 const oldMetadata=await legacyRpc('prepare',{worker_id:worker,qualification_master_id:master,target_id:target,certificate_number:'legacy pending',notes:'legacy approved metadata'});
 await legacyRpc('submit',{id:oldMetadata.id});
 await legacyRpc('prepare_photos',{request_id:id(90),target_id:target,photo_slots:[{existing_path:back},{existing_path:front}]});
 await legacyRpc('submit',{id:id(90)});
 const oldQueue=(await db.query('select to_jsonb(r) v from private.qualification_submissions r order by id')).rows.map(({v})=>({v:{...v,admin_saved_photos:false}}));
 const oldOfficial=(await db.query('select to_jsonb(q) v from worker_qualifications q where id=$1',[target])).rows[0].v;
 await db.exec("set test.uid='"+admin+"'");
`;
source = source.replace(before, prepare + before);
const checks = `
 await db.exec('begin');
 // Installation itself must neither rewrite pending requests nor the official row.
 assert.deepEqual((await db.query('select to_jsonb(r) v from private.qualification_submissions r order by id')).rows,oldQueue);
 assert.deepEqual((await db.query('select to_jsonb(q) v from worker_qualifications q where id=$1',[target])).rows[0].v,oldOfficial);
 // Exercise each pre-installation pending independently; preserve their original
 // snapshots and roll back only the synthetic approval probes, not deployment.
 for (const [request,photo] of [[oldMetadata.id,false],[id(90),true]]) {
  await db.exec('savepoint legacy_pending_probe');
  await db.exec("set test.uid='"+reviewer+"';set role authenticated");
  const approved=await legacyRpc('approve',{id:request});
  if(photo) assert.equal(approved.status,'approved');else assert.deepEqual(approved,{});
  await db.exec('reset role');
  assert.equal((await db.query('select status from private.qualification_submissions where id=$1',[request])).rows[0].status,'approved');
  const row=(await db.query('select * from worker_qualifications where id=$1',[target])).rows[0];
  if(photo){assert.equal(row.attachment_path,back);assert.equal(row.attachment_back_path,front);}
  else {assert.equal(row.certificate_number,'legacy pending');assert.equal(row.notes,'legacy approved metadata');}
  assert.equal((await db.query('select count(*)::int n from private.qualification_approved_write_permits')).rows[0].n,0);
  for(const path of [front,back]) {
   assert.equal((await db.query("select private.qualification_photo_unreferenced('qualification-certificates',$1) v",[path])).rows[0].v,false);
   assert.equal((await db.query("select count(*)::int n from storage.objects where name=$1",[path])).rows[0].n,1);
  }
  await db.exec('rollback to savepoint legacy_pending_probe;release savepoint legacy_pending_probe');
 }
 assert.deepEqual((await db.query('select to_jsonb(r) v from private.qualification_submissions r order by id')).rows,oldQueue);
 assert.deepEqual((await db.query('select to_jsonb(q) v from worker_qualifications q where id=$1',[target])).rows[0].v,oldOfficial);
 // Existing self-request is not rewritten/cancelled; a different existing
 // legitimate reviewer can approve the same ID after installation.
 await db.exec('savepoint self_request_probe');
 await db.query('insert into company_approval_assignees values($1,$2)',[company,user]);
 await db.exec("set test.uid='"+user+"';set role authenticated");
 await assert.rejects(legacyRpc('approve',{id:oldMetadata.id}),e=>e.code==='42501');
 await db.exec('rollback to savepoint self_request_probe;release savepoint self_request_probe');
 // Current admin photo request, then retirement: status retirement itself does
 // not edit qualification snapshots. Approve fails; rejection remains possible.
 await db.exec('savepoint retirement_probe');
 await db.exec("set test.uid='"+admin+"'");
 await legacyRpc('prepare_admin_saved_photos',{company_id:company,target_id:target,request_id:id(91),photo_slots:[]});
 await legacyRpc('submit',{id:id(91)});
 const retiredQueue=(await db.query('select to_jsonb(r) v from private.qualification_submissions r where id=$1',[id(91)])).rows[0].v;
 await db.query("update workers set status='retired' where id=$1",[worker]);
 await db.exec('savepoint retired_approval');
 await db.exec("set test.uid='"+reviewer+"';set role authenticated");
 await assert.rejects(legacyRpc('approve',{id:id(91)}),e=>e.code==='40001');
 await db.exec('rollback to savepoint retired_approval;release savepoint retired_approval');
 assert.deepEqual((await db.query('select to_jsonb(r) v from private.qualification_submissions r where id=$1',[id(91)])).rows[0].v,retiredQueue);
 assert.deepEqual((await db.query('select to_jsonb(q) v from worker_qualifications q where id=$1',[target])).rows[0].v,oldOfficial);
 await db.exec("set test.uid='"+reviewer+"';set role authenticated");
 assert.equal((await legacyRpc('reject',{id:id(91),reason:'退職済みのため原本を保持'})).status,'rejected');
 await db.exec('reset role');
 for(const path of [front,back]) assert.equal((await db.query("select private.qualification_photo_unreferenced('qualification-certificates',$1) v",[path])).rows[0].v,false);
 // Model an actual worker FK cascade explicitly: its DELETE is rejected by the
 // qualification guard and the entire parent deletion is atomic/rolled back.
 await db.exec('alter table worker_qualifications add constraint fixture_worker_cascade foreign key(worker_id) references workers(id) on delete cascade');
 await db.exec('savepoint worker_delete_probe');
 await assert.rejects(db.query('delete from workers where id=$1',[worker]),e=>e.code==='42501');
 await db.exec('rollback to savepoint worker_delete_probe;release savepoint worker_delete_probe');
 assert.equal((await db.query('select status from workers where id=$1',[worker])).rows[0].status,'retired');
 assert.deepEqual((await db.query('select to_jsonb(q) v from worker_qualifications q where id=$1',[target])).rows[0].v,oldOfficial);
 await db.exec('rollback to savepoint retirement_probe;release savepoint retirement_probe');
 assert.deepEqual((await db.query('select to_jsonb(r) v from private.qualification_submissions r order by id')).rows,oldQueue);
 // The broad candidate also blocks legacy metadata and registered DELETE.
 await db.exec('commit');
 // Give DELETE its existing role/RLS equivalent in this synthetic schema:
 // a deny must come from the guard rather than a missing fixture grant.
 await db.exec("grant delete on worker_qualifications to authenticated;create policy fixture_existing_delete on worker_qualifications for delete to authenticated using(private.has_company_feature(company_id,'can_manage_people'));");
 await db.exec("set test.uid='"+admin+"';set role authenticated");
 await assert.rejects(db.query('delete from worker_qualifications where id=$1',[target]),e=>e.code==='42501' && e.message.includes('separate review'));
 await assert.rejects(db.query("update worker_qualifications set notes='legacy direct metadata' where id=$1",[target]),e=>e.code==='42501');
 for(const statement of ["attachment_path=null","attachment_back_path=null","attachment_extra_paths='{}'::text[],attachment_path=null"])
  await assert.rejects(db.query('update worker_qualifications set '+statement+' where id=$1',[target]),e=>e.code==='42501');
 await db.exec('reset role');
 assert.deepEqual((await db.query('select to_jsonb(r) v from private.qualification_submissions r order by id')).rows,oldQueue);
 assert.deepEqual((await db.query('select to_jsonb(q) v from worker_qualifications q where id=$1',[target])).rows[0].v,oldOfficial);
 console.log('PASS pre-install legacy pending metadata/photo independently approve without rewriting IDs, history/Storage references survive; DELETE and direct SDK writes remain rollout blockers');
`;
source=source.replace(after,checks+after);
try { await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64')); }
catch(error) { console.error(error.name+': '+error.message.split(' from "data:')[0]);process.exitCode=1; }

