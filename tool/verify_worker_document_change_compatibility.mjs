// Disposable PGlite / existing native fixture adapter. No product data or API.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
import {setupWorkerDocumentChangeFixture,uid,company,worker,requirement,owner,reviewer,target,photo} from './worker_document_change_fixture_setup.mjs';
const {PGlite}=await import(pathToFileURL(process.argv[2]).href);
const db=new PGlite();
const source=p=>fs.readFileSync(p,'utf8');
const actor=async id=>{await db.exec('reset role');await db.query("select set_config('fixture.uid',$1,false)",[id]);await db.exec('set role authenticated');};
const rpc=async(action,data)=>(await db.query('select public.worker_document_change($1,$2::jsonb) result',[action,JSON.stringify(data)])).rows[0].result;
const official=async()=>(await db.query('select * from public.worker_document_statuses where id=$1',[target])).rows[0];
const snapshot=async()=>{
 await db.exec('reset role');
 return (await db.query(`select jsonb_build_object(
 'companies',(select jsonb_agg(to_jsonb(t) order by id) from public.companies t),
 'workers',(select jsonb_agg(to_jsonb(t) order by id) from public.workers t),
 'requirements',(select jsonb_agg(to_jsonb(t) order by id) from public.document_requirements t),
 'statuses',(select jsonb_agg(to_jsonb(t) order by id) from public.worker_document_statuses t),
 'history',(select jsonb_agg(to_jsonb(t) order by id) from public.worker_document_status_history t),
 'objects',(select jsonb_agg(to_jsonb(t) order by id) from storage.objects t)) state`)).rows[0].state;
};
try {
 await setupWorkerDocumentChangeFixture(db,{applyCandidate:false});
 await actor(owner);
 // An already filled pre-candidate legacy row does not require INSERT history
 // to submit a change: only an empty first-save exception requires that proof.
 await db.query("insert into public.worker_document_statuses(id,company_id,worker_id,requirement_id,status,attachment_path,notes,updated_by) values($1,$2,$3,$4,'submitted',$5,'legacy original',$6)",[target,company,worker,requirement,photo,owner]);
 await db.exec('reset role');
 await db.query('delete from public.worker_document_status_history where source_status_id=$1',[target]);
 await db.query("insert into storage.objects(bucket_id,name) values('worker-documents',$1)",[photo]);
 const before=await snapshot();
 await db.exec(source('docs/candidates/worker_document_change_20261019.sql.review-only'));
 assert.deepEqual(await snapshot(),before,'Installing candidate must not backfill or alter saved data');
 await actor(owner);const row=await official();
 const id=uid(60);
 await rpc('prepare',{request_id:id,status_id:target,expected_updated_at:row.updated_at,proposed:{attachment_paths:[],expires_at:null,notes:'legacy changed'}});
 await rpc('submit',{request_id:id});await actor(reviewer);await rpc('approve',{request_id:id});
 assert.equal((await official()).notes,'legacy changed');assert.deepEqual((await official()).attachment_paths,[]);
 await db.exec('reset role');assert.equal(Number((await db.query('select count(*) n from storage.objects')).rows[0].n),1);
 console.log('PASS historical filled row without INSERT proof: install preserves all rows, normal approval works without backfill');
 const frozen=await snapshot();
 for(const [label,sql,params] of [
  ['worker cascade','delete from public.workers where id=$1',[worker]],
  ['requirement cascade','delete from public.document_requirements where id=$1',[requirement]],
  ['company cascade','delete from public.companies where id=$1',[company]],
  ['auth updater SET NULL','delete from auth.users where id=$1',[reviewer]],
  ['privileged direct status deletion','delete from public.worker_document_statuses where id=$1',[target]],
 ]) {
  await assert.rejects(db.query(sql,params),e=>e.code==='42501',label);
  assert.deepEqual(await snapshot(),frozen,label+' must roll back every data effect');
  console.log('PASS '+label+' refuses atomically; original/history/storage retained');
 }
 await db.query('update public.document_requirements set is_active=false where id=$1',[requirement]);
 assert.equal((await official()).notes,'legacy changed');
 await db.query('update public.document_requirements set is_active=true where id=$1',[requirement]);
 assert.deepEqual(await snapshot(),frozen,'soft visibility change/restore preserves stored content');
 console.log('PASS existing soft hide/restore avoids DELETE cascade and preserves content');
 // Replay the saved worker-document Storage policy text, not an invented
 // replacement policy. Helpers below are explicitly synthetic prerequisites.
 await db.exec(`create function private.try_uuid(value text) returns uuid language plpgsql immutable as $$begin return value::uuid;exception when invalid_text_representation then return null;end$$;
 create function private.has_company_feature(cid uuid,feature text) returns boolean language sql stable security definer set search_path='' as $$select coalesce(current_setting('fixture.feature_off',true),'')<>'yes' and exists(select 1 from public.company_members m where m.company_id=cid and m.user_id=auth.uid() and m.role in ('owner','admin','manager'))$$;
 drop policy fixture_read on storage.objects;drop policy fixture_delete on storage.objects;drop policy fixture_update on storage.objects;`);
 const policySource=source('supabase/migrations/20260920205500_restrict_worker_private_documents.sql');
 const start=policySource.indexOf('drop policy if exists "worker_documents_read"');
 const end=policySource.indexOf('drop policy if exists "qualification_certificates_read"',start);
 assert.ok(start>=0&&end>start);await db.exec(policySource.slice(start,end));
 const otherWorker=uid(70),otherOwner=uid(71),otherCompany=uid(72),otherPath=`${otherCompany}/${otherWorker}/${requirement}/own-upload/front.jpg`;
 await db.query('insert into auth.users values($1)',[otherOwner]);
 await db.query('insert into public.companies values($1)',[otherCompany]);
 await db.query('insert into public.workers values($1,$2,$3)',[otherWorker,otherCompany,otherOwner]);
 await db.query("insert into storage.objects(bucket_id,name) values('worker-documents',$1)",[otherPath]);
 await actor(owner);assert.deepEqual((await db.query('select name from storage.objects order by name')).rows.map(r=>r.name),[photo]);
 await actor(reviewer);assert.deepEqual((await db.query('select name from storage.objects order by name')).rows.map(r=>r.name),[photo]);
 await db.query('delete from storage.objects where name=$1',[photo]);
 assert.deepEqual((await db.query('select name from storage.objects order by name')).rows.map(r=>r.name),[photo],'history-retained removed photo must resist authorized manager DELETE');
 await db.exec("select set_config('fixture.feature_off','yes',false)");assert.deepEqual((await db.query('select name from storage.objects')).rows,[]);
 await db.exec("select set_config('fixture.feature_off','',false)");await actor(otherOwner);assert.deepEqual((await db.query('select name from storage.objects order by name')).rows.map(r=>r.name),[otherPath]);
 await db.query('delete from storage.objects where name=$1',[otherPath]);
 await db.exec('reset role');assert.equal(Number((await db.query('select count(*) n from storage.objects')).rows[0].n),2,'no real deletion privilege granted by read scope');
 console.log('PASS saved-source Storage read scope: own/admin same company, feature-off and cross-company denial; removed saved photo retained by history');
 console.log('PASS compatibility/cascade/storage source checks; real production helper/JWT/Storage bytes not exercised');
} finally {await db.close();}
