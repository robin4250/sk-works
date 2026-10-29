// New cross-module composition only. Synthetic native claims, NOT GoTrue evidence.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {createHash} from 'node:crypto';
const pg=(await import(process.argv[2])).default;
const url=new URL(process.env.SKO_BANK_DOCUMENT_FIXTURE_URL??'');
assert.ok(['127.0.0.1','localhost'].includes(url.hostname)&&url.port==='5432'&&url.pathname==='/sko_bank_document_fixture'&&!url.search&&!url.hash&&url.username==='postgres'&&url.password==='synthetic_bank_document_only');
const db=new pg.Client({connectionString:url.href});await db.connect();
const read=p=>fs.readFile(p,'utf8');
const id=n=>`50000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const [C,A,B,SA,SB,R,W0,W1,W2,S0,S1,S2]=Array.from({length:12},(_,i)=>id(i+1));
const claims=(actor,sid,role='authenticated')=>JSON.stringify({sub:actor,session_id:sid,role,is_anonymous:false});
const actor=async(user,sid)=>{await db.query('reset role');await db.query("select set_config('request.jwt.claims',$1,false)",[claims(user,sid)]);await db.query('set role authenticated');};
const admin=async()=>{await db.query('reset role');};
const sha=s=>createHash('sha256').update(s).digest('hex');
let checks=0,stage='setup';const eq=(a,b)=>{assert.deepEqual(a,b);checks++;};
try{
 assert.match((await db.query('show server_version')).rows[0].server_version,/^17\./);
 eq((await db.query("select count(*)::int n from pg_tables where schemaname='public'")).rows[0].n,0);
 await db.query(`create role anon;create role authenticated;create role service_role;create schema auth;
 create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 create function auth.uid() returns uuid language sql stable as $$select (auth.jwt()->>'sub')::uuid$$;
 create function auth.role() returns text language sql stable as $$select auth.jwt()->>'role'$$;
 create table auth.users(id uuid primary key,is_anonymous boolean default false,banned_until timestamptz,encrypted_password text);
 create table auth.sessions(id uuid primary key,user_id uuid not null,not_after timestamptz);
 grant usage on schema auth to authenticated,service_role;
 create schema storage;create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text);
 create table public.company_approval_assignees(company_id uuid,user_id uuid);`);
 // Replace only the two simplified fixture tables with the saved actual checklist definitions.
 // The bank module/trigger source is never rewritten or relaxed.
 let business=await read('tool/security/employee_bank_initial/fixture-business.sql');
 const checklist=await read('supabase/migrations/20260918133000_add_worker_document_checklist.sql');
 for(const name of ['document_requirements','worker_document_statuses']){
  const full=checklist.match(new RegExp('create table if not exists public\\.'+name+' \\([\\s\\S]*?\\n\\);'));
  assert.ok(full);const simple=new RegExp('create table public\\.'+name+'\\([^\\n]*\\);');
  assert.equal([...business.matchAll(new RegExp(simple.source,'g'))].length,1);
  business=business.replace(simple,()=>full[0]);
 }
 await db.query(business);
 await db.query(await read('tool/security/employee_bank_initial/baseline-functions.sql'));
 await db.query(await read('tool/security/worker_document_change_session/baseline.sql'));
 for(const file of ['20260918133000_add_worker_document_checklist.sql','20260918144500_add_worker_document_status_history.sql','20260919023500_harden_worker_document_rls.sql','20261003121632_allow_self_document_registration.sql','20261010222524_worker_document_multiple_photos.sql'])await db.query(await read('supabase/migrations/'+file));
 await db.query(`create policy "people feature fixture" on public.worker_document_statuses for all to authenticated
 using(private.has_company_feature(company_id,'can_manage_people')) with check(private.has_company_feature(company_id,'can_manage_people')
 and exists(select 1 from public.workers w where w.id=worker_id and w.company_id=worker_document_statuses.company_id)
 and exists(select 1 from public.document_requirements d where d.id=requirement_id and d.company_id=worker_document_statuses.company_id));
 grant select on public.companies,public.company_members,public.workers,public.document_requirements,public.worker_document_status_history to authenticated;
 grant select,insert,update,delete on public.worker_document_statuses to authenticated;`);
 await db.query('insert into auth.users(id) values($1),($2)',[A,B]);await db.query('insert into auth.sessions values($1,$3,null),($2,$4,null)',[SA,SB,A,B]);
 await db.query("insert into public.companies values($1,'SYNTHETIC')",[C]);
 await db.query("insert into public.company_members values($1,$2,'employee'),($1,$3,'employee')",[C,A,B]);
 await db.query('insert into public.member_feature_permissions(company_id,user_id,can_manage_people,can_manage_payroll) values($1,$2,true,true)',[C,B]);
 await db.query("insert into public.workers(id,company_id,user_id) values($1,$4,$5),($2,$4,$5),($3,$4,$5)",[W0,W1,W2,C,A]);
 await db.query("insert into public.document_requirements(id,company_id,name) values($1,$2,'銀行口座情報')",[R,C]);
 const path=worker=>`${C}/${worker}/${R}/own-upload/original.jpg`;
 for(const [worker,status] of [[W0,S0],[W1,S1],[W2,S2]]){
  await db.query("insert into public.worker_document_statuses(id,company_id,worker_id,requirement_id,status,original_verified,attachment_path,attachment_paths,notes,expires_at,updated_by) values($1,$2,$3,$4,'verified',true,$5,array[$5],'SYNTHETIC ORIGINAL NOTE','2030-01-01',$6)",[status,C,worker,R,path(worker),A]);
  await db.query("insert into storage.objects(bucket_id,name) values('worker-documents',$1)",[path(worker)]);
 }
 const snapshot=async worker=>(await db.query('select to_jsonb(t) v from public.worker_document_statuses t where worker_id=$1',[worker])).rows[0].v;
 const originals=new Map();for(const worker of [W0,W1,W2])originals.set(worker,await snapshot(worker));
 const bankBefore=async worker=>(await db.query('select md5(to_jsonb(t)::text) v from public.worker_private_bank_accounts t where worker_id=$1',[worker])).rows[0]?.v;
 const trigger=(await db.query("select pg_get_triggerdef(oid) def,tgenabled enabled from pg_trigger where tgrelid='public.worker_private_bank_accounts'::regclass and tgname='sync_bank_document_status'")).rows[0];
 assert.ok(trigger&&trigger.enabled==='O');
 stage='install-off';
 await db.query(await read('docs/candidates/employee_bank_preapply_capsule_20261029/install.sql.review-only'));
 await db.query(await read('docs/candidates/worker_document_change_session_20261029/install.sql.review-only'));
 eq((await db.query('select private.employee_bank_initial_enabled() v')).rows[0].v,false);
 eq((await db.query('select private.worker_document_change_enabled() v')).rows[0].v,false);
 const input={bank_name:'SYNTHETIC BANK',branch_name:'SYNTHETIC BRANCH',account_type:'普通',account_number:'0000001',account_holder:'SYNTHETIC HOLDER'};
 const unchangedContent=async worker=>{const row=await snapshot(worker),old=originals.get(worker);for(const key of ['notes','attachment_path','attachment_paths','expires_at'])eq(row[key],old[key]);eq(row.status,'submitted');eq(row.original_verified,false);};
 stage='original-self-trigger-both-off';
 await actor(A,SA);
 await db.query('insert into public.worker_private_bank_accounts(worker_id,company_id,bank_name,branch_name,account_type,account_number,account_holder) values($1,$2,$3,$4,$5,$6,$7)',[W0,C,input.bank_name,input.branch_name,input.account_type,input.account_number,input.account_holder]);
 await unchangedContent(W0);await admin();
 // Enable only isolated bank fixture. Password proof acquisition remains covered by old real Auth; native issuer uses explicit synthetic service claims.
 await db.query("create or replace function private.employee_bank_initial_enabled() returns boolean language sql stable security definer set search_path='' as $$select true$$");
 async function register(worker){
  await admin();await db.query("select set_config('request.jwt.claims',$1,false)",[claims(B,SB,'service_role')]);
  const digest=(await db.query('select private.employee_bank_initial_digest($1,$2,$3) v',[C,worker,input])).rows[0].v;
  const target={company_id:C,worker_id:worker,input_sha256:digest};const proof=sha('synthetic-operation-'+worker);
  await db.query("select public.issue_reauthentication_proof($1,$2,'employee.bank.initial',$3,$4)",[B,SB,target,sha(proof)]);
  await actor(B,SB);
  const response=(await db.query('select public.register_employee_bank_initial($1,$2,$3,$4) v',[C,worker,input,proof])).rows[0].v;
  eq(response.worker_id,worker);eq(response.registered,true);await unchangedContent(worker);await admin();
  eq((await db.query('select count(*)::int n from private.employee_bank_initial_context')).rows[0].n,0);
 }
 stage='manager-bank-trigger-document-off';await register(W1);
 stage='document-on-active-request';await db.query('update private.worker_document_change_rollout set enabled=true');
 await actor(A,SA);const row=await snapshot(W2);
 const req=id(90),proposed={attachment_paths:[path(W2)],expires_at:'2031-01-01',notes:'SYNTHETIC PROPOSED NOTE'};
 eq((await db.query("select public.worker_document_change('prepare',$1) v",[{request_id:req,status_id:S2,expected_updated_at:row.updated_at,proposed}])).rows[0].v.status,'draft');
 eq((await db.query("select public.worker_document_change('submit',$1) v",[{request_id:req}])).rows[0].v.status,'pending');
 stage='manager-bank-trigger-document-on';await register(W2);
 const retained=await bankBefore(W2);
 await actor(B,SB);await assert.rejects(db.query("select public.worker_document_change('approve',$1)",[{request_id:req}]),error=>error.code==='40001');checks++;
 await admin();eq((await db.query('select status from private.worker_document_changes where id=$1',[req])).rows[0].status,'pending');eq(await bankBefore(W2),retained);
 eq((await db.query('select count(*)::int n from private.worker_document_apply_tickets')).rows[0].n,0);
 eq((await db.query("select pg_get_triggerdef(oid) def,tgenabled enabled from pg_trigger where tgrelid='public.worker_private_bank_accounts'::regclass and tgname='sync_bank_document_status'")).rows[0],trigger);
 eq((await db.query("select count(*)::int n from private.reauthentication_proofs where operation='employee.bank.initial' and consumed_at is not null")).rows[0].n,2);
 console.log(JSON.stringify({pass:true,checks,native_pg17:true,synthetic_claims_not_gotrue:true,original_real_trigger_dispatched:true,self_both_off:true,manager_document_off:true,manager_active_request_on:true,images_notes_expiry_preserved:true,stale_approval_denied_without_rewrite:true,old_suites_repeated:false,production_changed:false}));
}catch(error){console.error(JSON.stringify({stage,sqlstate:error.code??null,position:error.position??null}));throw error;}finally{await db.end();}
