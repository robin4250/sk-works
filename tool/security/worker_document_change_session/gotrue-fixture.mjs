// Genuine local GoTrue sessions/JWT and PostgREST; application rows are synthetic.
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
const read=p=>fs.readFile(p,'utf8');
const dir='docs/candidates/worker_document_change_session_20261029/';
const id=n=>`30000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
export async function verifyDocumentChangeSession({db,users,sessions,password,request,rpc,eq}){
 let stage='setup';
 try{
  const authCatalog=async()=>(await db.query("select jsonb_agg(jsonb_build_object('name',oid::regprocedure::text,'def',pg_get_functiondef(oid),'owner',proowner,'acl',proacl) order by oid) v from pg_proc where oid in ('auth.uid()'::regprocedure,'auth.jwt()'::regprocedure)")).rows[0].v;
  const version=Number((await db.query('show server_version_num')).rows[0].server_version_num);assert.ok(version>=170000&&version<180000,'PostgreSQL17 required');
  const authBefore=await authCatalog();
  await db.query(`create schema private;
   create table public.companies(id uuid primary key);
   create table public.company_members(company_id uuid,user_id uuid,role text,primary key(company_id,user_id));
   create table public.company_approval_assignees(company_id uuid,user_id uuid);
   create table public.workers(id uuid primary key,company_id uuid references public.companies(id) on delete cascade,user_id uuid,status text not null default 'active');
   create table public.member_feature_permissions(company_id uuid,user_id uuid,
    can_approve_daily_report_edits boolean default false,can_manage_attendance boolean default false,
    can_manage_people boolean default false,can_view_invoices boolean default false,can_manage_invoices boolean default false,
    can_view_admin_site_data boolean default false,can_manage_admin_site_data boolean default false,
    can_manage_payroll boolean default false,can_manage_partner_chat boolean default false,primary key(company_id,user_id));
   create table private.account_deletion_access_restrictions(user_id uuid primary key);
   create function private.account_deletion_barrier_key(p_actor uuid) returns bigint language sql immutable as $$select hashtextextended('deletion:'||p_actor::text,0)$$;`);
  await db.query(await read('tool/security/worker_document_change_session/baseline.sql'));
  for(const name of ['20260918133000_add_worker_document_checklist.sql','20260918144500_add_worker_document_status_history.sql','20260919023500_harden_worker_document_rls.sql','20261003121632_allow_self_document_registration.sql','20261010222524_worker_document_multiple_photos.sql'])await db.query(await read('supabase/migrations/'+name));
  // Current catalog's people-feature ALL policy composes with the manager policy.
  await db.query(`create policy "people managers can manage worker document statuses" on public.worker_document_statuses for all to authenticated
   using(private.has_company_feature(company_id,'can_manage_people')) with check(private.has_company_feature(company_id,'can_manage_people')
   and exists(select 1 from public.workers w where w.id=worker_id and w.company_id=worker_document_statuses.company_id)
   and exists(select 1 from public.document_requirements d where d.id=requirement_id and d.company_id=worker_document_statuses.company_id));
   grant usage on schema public,private to authenticated;
   grant select on public.companies,public.company_members,public.workers,public.document_requirements,public.worker_document_status_history to authenticated;
   grant select,insert,update,delete on public.worker_document_statuses to authenticated;`);
  const C=id(1),W=id(2),R=id(3),S=id(4),C2=id(5),W2=id(6),R2=id(7),S2=id(8);
  await db.query('insert into public.companies values($1),($2)',[C,C2]);
  await db.query("insert into public.company_members values($1,$2,'employee'),($1,$3,'employee'),($1,$4,'manager'),($5,$6,'admin')",[C,users.owner.id,users.outsider.id,users.revoked.id,C2,users.othercompany.id]);
  await db.query('insert into public.member_feature_permissions(company_id,user_id,can_manage_people) values($1,$2,true)',[C,users.outsider.id]);
  await db.query('insert into public.workers(id,company_id,user_id) values($1,$2,$3),($4,$5,$6)',[W,C,users.owner.id,W2,C2,users.othercompany.id]);
  await db.query("insert into public.document_requirements(id,company_id,name) values($1,$2,'Synthetic'),($3,$4,'Synthetic foreign')",[R,C,R2,C2]);
  await db.query("insert into public.worker_document_statuses(id,company_id,worker_id,requirement_id,status,notes,updated_by) values($1,$2,$3,$4,'submitted','original',$5),($6,$7,$8,$9,'submitted','foreign original',$10)",[S,C,W,R,users.owner.id,S2,C2,W2,R2,users.othercompany.id]);
  const originals=async()=>(await db.query("select jsonb_agg(to_jsonb(t) order by id) v from public.worker_document_statuses t")).rows[0].v;
  const triggerCatalog=async()=>(await db.query("select jsonb_agg(jsonb_build_object('def',pg_get_triggerdef(oid),'enabled',tgenabled) order by tgname) v from pg_trigger where tgrelid='public.worker_document_statuses'::regclass and not tgisinternal and tgname<>'zz_worker_document_change_guard'")).rows[0].v;
  const before=await originals(),triggersBefore=await triggerCatalog();
  const installer=await read(dir+'install.sql.review-only'),restore=await read(dir+'restore-unused.sql.review-only');
  stage='original-attributes-pin';
  await db.query('alter function private.require_reauthentication_session() security invoker');
  await assert.rejects(db.query(installer));await db.query('rollback');
  eq((await db.query("select to_regclass('private.worker_document_change_rollout') v")).rows[0].v,null);
  await db.query('alter function private.require_reauthentication_session() security definer');
  await db.query(installer);eq(await originals(),before);eq(await triggerCatalog(),triggersBefore);
  await db.query("notify pgrst,'reload schema'");
  const actor=sessions.owner.access_token,reviewer=sessions.outsider.access_token,manager=sessions.revoked.access_token;
  const call=(action,data={},token=actor)=>rpc('worker_document_change',{p_action:action,p_data:data},token);
  const denied=async response=>{assert.ok(response.status>=400);};
  // Fixed bounded schema-cache synchronization, no mutation retry.
  for(let attempt=0;attempt<40;attempt++){
   const res=await call('capability');const value=await res.json();
   if(value.code!=='PGRST202'){assert.ok(res.status>=400);break;}
   assert.ok(attempt<39);await new Promise(resolve=>setTimeout(resolve,100));
  }
  stage='off-unused-restore';await denied(await call('prepare',{request_id:id(20),status_id:S,expected_updated_at:before[0].updated_at,proposed:{attachment_paths:[],expires_at:null,notes:'changed'}}));
  // OFF does not suppress DELETE or existing initial/server writes.
  await db.query('delete from public.worker_document_statuses where id=$1',[S2]);
  eq((await db.query('select count(*)::int n from public.worker_document_statuses where id=$1',[S2])).rows[0].n,0);
  await db.query(restore);eq(await triggerCatalog(),triggersBefore);eq(await authCatalog(),authBefore);
  await db.query(installer);
  stage='on';await db.query('update private.worker_document_change_rollout set enabled=true');
  const cap=await call('capability');eq(cap.status,200);eq((await cap.json()).new_upload_available,false);
  const snapshot=async()=>(await db.query('select to_jsonb(t) v from public.worker_document_statuses t where id=$1',[S])).rows[0].v;
  const officialBefore=await snapshot();
  const proposal={attachment_paths:[],expires_at:'2030-01-01',notes:'synthetic revised'};
  const data={request_id:id(20),status_id:S,expected_updated_at:officialBefore.updated_at,proposed:proposal};
  stage='scope-foreign-inactive';await denied(await call('prepare',data,sessions.othercompany.access_token));
  await db.query("update public.workers set status='inactive' where id=$1",[W]);await denied(await call('prepare',data));await db.query("update public.workers set status='active' where id=$1",[W]);
  await db.query('update public.document_requirements set is_active=false where id=$1',[R]);await denied(await call('prepare',data));await db.query('update public.document_requirements set is_active=true where id=$1',[R]);
  const prepared=await call('prepare',data);eq(prepared.status,200);const receipt=await prepared.json();eq(receipt.status,'draft');eq(await snapshot(),officialBefore);
  const requestId={request_id:id(20)};
  stage='new-session-explicit-resume';
  const login=await request('/auth/v1/token?grant_type=password',{body:{email:users.owner.email,password}});eq(login.status,200);const resumed=await login.json();
  const oldSid=JSON.parse(Buffer.from(actor.split('.')[1],'base64url')).session_id,newSid=JSON.parse(Buffer.from(resumed.access_token.split('.')[1],'base64url')).session_id;assert.notEqual(oldSid,newSid);
  const logout=await request('/auth/v1/logout?scope=local',{token:actor});assert.ok([200,204].includes(logout.status));
  await denied(await call('submit',requestId));eq((await db.query('select status from private.worker_document_changes where id=$1',[id(20)])).rows[0].status,'draft');
  const freshCap=await call('capability',{},resumed.access_token);eq(freshCap.status,200);
  const submitted=await call('submit',requestId,resumed.access_token);eq(submitted.status,200);eq((await submitted.json()).status,'pending');
  eq((await db.query('select created_session_id::text sid from private.worker_document_changes where id=$1',[id(20)])).rows[0].sid,oldSid);
  eq((await db.query("select session_id::text sid from private.worker_document_change_events where request_id=$1 and action='submit'",[id(20)])).rows[0].sid,newSid);
  stage='self-approval-new-upload-denied';await denied(await call('approve',requestId,resumed.access_token));
  await denied(await call('prepare',{...data,request_id:id(21),proposed:{...proposal,attachment_paths:['new/unprepared.jpg']}},resumed.access_token));eq(await snapshot(),officialBefore);
  stage='permission-revocation';await db.query('update public.member_feature_permissions set can_manage_people=false where company_id=$1 and user_id=$2',[C,users.outsider.id]);await denied(await call('approve',requestId,reviewer));eq(await snapshot(),officialBefore);await db.query('update public.member_feature_permissions set can_manage_people=true where company_id=$1 and user_id=$2',[C,users.outsider.id]);
  stage='demoted-requester-current-scope';
  const managed=await call('prepare',{...data,request_id:id(23)},manager);eq(managed.status,200);
  await db.query("update public.company_members set role='employee' where company_id=$1 and user_id=$2",[C,users.revoked.id]);
  const demotedList=await call('list',{},manager);eq(demotedList.status,200);eq((await demotedList.json()).some(row=>row.id===id(23)),false);
  for(const action of ['detail','submit','cancel'])await denied(await call(action,{request_id:id(23)},manager));
  await db.query("update public.company_members set role='manager' where company_id=$1 and user_id=$2",[C,users.revoked.id]);
  eq((await call('cancel',{request_id:id(23)},manager)).status,200);
  stage='existing-status-only-server-shape';
  for(const status of ['expired','submitted']){
   const response=await request('/rest/v1/worker_document_statuses?id=eq.'+S,{method:'PATCH',token:resumed.access_token,body:{status,original_verified:false,updated_by:users.owner.id}});eq(response.status,204);
  }
  eq(await snapshot(),officialBefore);
  stage='ticket-forgery';
  const fake=await request('/rest/v1/worker_document_statuses?id=eq.'+S,{method:'PATCH',token:resumed.access_token,body:{notes:'direct bypass',updated_by:users.owner.id}});await denied(fake);eq(await snapshot(),officialBefore);
  eq((await db.query("select has_table_privilege('authenticated','private.worker_document_apply_tickets','INSERT') v")).rows[0].v,false);
  stage='concurrent-approval';
  const historyBefore=(await db.query('select count(*)::int n from public.worker_document_status_history where source_status_id=$1',[S])).rows[0].n;
  await db.query('begin');
  await db.query('select id from public.worker_document_statuses where id=$1 for update',[S]);
  const pendingResults=Promise.all([call('approve',requestId,reviewer),call('approve',requestId,manager)]);
  // Assert real database lock overlap; Promise.all alone is not a race proof.
  let blocked=false;
  for(let attempt=0;attempt<100;attempt++){
   await db.query('select pg_stat_clear_snapshot()');
   const count=(await db.query("select count(*)::int n from pg_stat_activity where pid<>pg_backend_pid() and wait_event_type='Lock' and query like '%worker_document_change%'")).rows[0].n;
   if(count>=2){blocked=true;break;}
   await new Promise(resolve=>setTimeout(resolve,50));
  }
  await db.query('commit');assert.ok(blocked,'Both actual RPCs must be observed waiting on locks');
  const results=await pendingResults;
  for(const result of results){eq(result.status,200);eq((await result.json()).status,'approved');}
  eq((await snapshot()).notes,proposal.notes);eq((await db.query('select count(*)::int n from public.worker_document_status_history where source_status_id=$1',[S])).rows[0].n,historyBefore+1);
  eq((await db.query('select count(*)::int n from private.worker_document_apply_tickets')).rows[0].n,0);
  stage='after-use-preservation';await db.query('update private.worker_document_change_rollout set enabled=false');await assert.rejects(db.query(restore));await db.query('rollback');
  eq((await db.query('select count(*)::int n from private.worker_document_changes')).rows[0].n,2);
  // Parent cascade remains authoritative even with an active pending request.
  await db.query('update private.worker_document_change_rollout set enabled=true');
  const applied=await snapshot();
  eq((await call('prepare',{...data,request_id:id(22),expected_updated_at:applied.updated_at,proposed:{...proposal,notes:'pending retained'}},resumed.access_token)).status,200);
  eq((await call('submit',{request_id:id(22)},resumed.access_token)).status,200);
  const detail=await call('detail',requestId,resumed.access_token);eq(detail.status,200);eq((await detail.json()).status,'approved');
  await db.query('delete from public.workers where id=$1',[W]);eq((await db.query('select count(*)::int n from public.worker_document_statuses where id=$1',[S])).rows[0].n,0);eq((await db.query('select count(*)::int n from private.worker_document_changes')).rows[0].n,3);
  await denied(await call('approve',{request_id:id(22)},reviewer));
  eq(await triggerCatalog(),triggersBefore);eq(await authCatalog(),authBefore);
  console.log('PASS actual GoTrue/PostgREST: OFF/unused restore, source/attribute pin, live SID revocation and explicit fresh-session resume with retained creation SID, people-feature/legacy manager RLS union, scope/new-upload/self approval/forged ticket failures, concurrent single apply/history, after-use restore refusal and original cascade preservation; production unchanged');
 }catch(error){console.error(JSON.stringify({synthetic_fixture_stage:stage,sqlstate:error.code??null,position:error.position??null}));error.code='DOCUMENT_CHANGE_'+stage.replaceAll('-','_').toUpperCase();throw error;}
}
