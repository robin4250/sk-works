import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {createHash,randomBytes} from 'node:crypto';
const pg=(await import(process.argv[2]??'pg')).default;
const url=new URL(process.env.SKO_EMPLOYEE_BANK_FIXTURE_URL??'');
if(!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.pathname!='/sko_employee_bank_fixture')throw Error('Disposable loopback bank fixture only');
const clients=[];
async function connect(){const c=new pg.Client({connectionString:url.href});await c.connect();clients.push(c);await c.query("set statement_timeout='8s'");return c;}
const a='10000000-0000-0000-0000-000000000001',b='10000000-0000-0000-0000-000000000002',c='10000000-0000-0000-0000-000000000003';
const sa='20000000-0000-0000-0000-000000000001',sa2='20000000-0000-0000-0000-000000000002',sb='20000000-0000-0000-0000-000000000003';
const company='30000000-0000-0000-0000-000000000001',other='30000000-0000-0000-0000-000000000002';
const w='40000000-0000-0000-0000-000000000001',raceWorker='40000000-0000-0000-0000-000000000002',selfWorker='40000000-0000-0000-0000-000000000003',foreignWorker='40000000-0000-0000-0000-000000000004',requirement='50000000-0000-0000-0000-000000000001';
const data={bank_name:'合成試験銀行',branch_name:'SYNTHETIC BRANCH',account_type:'普通',account_number:'0000001',account_holder:'SYNTHETIC HOLDER'};
const hash=v=>createHash('sha256').update(v).digest('hex');
const canonical=(worker,value=data)=>'sko-employee-bank-initial-v1\n'+[company,worker,value.bank_name,value.branch_name,value.account_type,value.account_number,value.account_holder].map(v=>Buffer.byteLength(v,'utf8')+':'+v).join('\n');
const target=(worker,value=data)=>({company_id:company,worker_id:worker,input_sha256:hash(canonical(worker,value))});
const read=relative=>fs.readFile(new URL(relative,import.meta.url),'utf8');
const deny=(promise,codes=['42501'])=>assert.rejects(promise,e=>codes.includes(e.code));
async function actor(client,id=a,sid=sa){await client.query('reset role');await client.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:id,session_id:sid,role:'authenticated',is_anonymous:false})]);await client.query('set role authenticated');}
let admin;
try {
 admin=await connect();assert.match((await admin.query('show server_version')).rows[0].server_version,/^17\./);
 await admin.query(`create role authenticated;create role anon;create role service_role;
 create schema auth;create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 create function auth.uid() returns uuid language sql stable as $$select (auth.jwt()->>'sub')::uuid$$;
 create function auth.role() returns text language sql stable as $$select auth.jwt()->>'role'$$;
 create table auth.users(id uuid primary key,is_anonymous boolean default false,banned_until timestamptz,encrypted_password text);
 create table auth.sessions(id uuid primary key,user_id uuid not null,not_after timestamptz);
 grant usage on schema auth to authenticated,service_role;grant execute on all functions in schema auth to authenticated,service_role;`);
 await admin.query(await read('./employee_bank_initial/fixture-business.sql'));
 await admin.query(await read('./employee_bank_initial/baseline-functions.sql'));
 const baseline=JSON.parse(await read('./employee_bank_initial/baseline-catalog.json'));
 const forward=await read('../staged/employee_bank_initial_registration.sql.review-only');
 const restore=await read('../staged/employee_bank_initial_registration.restore-unused.sql.review-only');
 const originalFunctions=async()=>(await admin.query(`select p.oid::regprocedure::text signature,pg_get_functiondef(p.oid) definition,p.proacl::text acl,p.prosecdef,p.provolatile,p.proconfig from pg_proc p where p.oid=any($1::regprocedure[]) order by 1`,[baseline.map(r=>r.signature)])).rows;
 const originals=await originalFunctions();
 // A drift must abort before any candidate object/grant is created.
 await admin.query("create or replace function private.reauthentication_scope(p_operation text) returns text language sql immutable set search_path='' as $$select null::text$$");
 await deny(admin.query(forward),['55000']);await admin.query('rollback');
 assert.equal((await admin.query("select to_regclass('private.employee_bank_initial_context') x")).rows[0].x,null);
 await admin.query(baseline.find(r=>r.signature==='private.reauthentication_scope(text)').definition);
 await admin.query(forward);
 await admin.query('insert into auth.users(id) values($1),($2),($3)',[a,b,c]);
 await admin.query('insert into auth.sessions values($1,$4,null),($2,$4,null),($3,$5,null)',[sa,sa2,sb,a,b]);
 await admin.query("insert into public.companies values($1,'SYNTHETIC COMPANY'),($2,'SYNTHETIC OTHER COMPANY')",[company,other]);
 await admin.query("insert into public.company_members values($1,$3,'owner'),($1,$4,'viewer'),($2,$5,'owner')",[company,other,a,b,c]);
 await admin.query("insert into public.workers values($1,$5,$7,'active'),($2,$5,$7,'active'),($3,$5,$7,'active'),($4,$6,$8,'active')",[w,raceWorker,selfWorker,foreignWorker,company,other,b,c]);
 await admin.query("insert into public.document_requirements values($1,$2,'銀行口座情報',true)",[requirement,company]);
 await admin.query("insert into public.worker_document_statuses values($1,$2,$3,'not_submitted',false,$4,now(),'SYNTHETIC-ORIGINAL-PATH','SYNTHETIC-ORIGINAL-NOTE')",[company,w,requirement,b]);
 await admin.query("insert into public.payroll_statements values('60000000-0000-0000-0000-000000000001',$1,$2,'{\"signed\":\"SYNTHETIC-ORIGINAL-SIGNATURE\",\"net\":12345}')",[company,w]);
 await admin.query("insert into payroll_final_private.documents values('60000000-0000-0000-0000-000000000001','{\"snapshot\":\"SYNTHETIC-ORIGINAL\"}');insert into payroll_final_private.history values('70000000-0000-0000-0000-000000000001','{\"history\":\"SYNTHETIC-ORIGINAL\"}')");
 const preserved=async()=>(await admin.query(`select jsonb_build_object('payroll',(select jsonb_agg(to_jsonb(p) order by id) from public.payroll_statements p),'documents',(select jsonb_agg(to_jsonb(d) order by statement_id) from payroll_final_private.documents d),'history',(select jsonb_agg(to_jsonb(h) order by id) from payroll_final_private.history h)) v`)).rows[0].v;
 const originalPayroll=await preserved();
 const self=await connect(),foreign=await connect(),differentSID=await connect(),race1=await connect(),race2=await connect(),issuer=await connect();
 await actor(self);await actor(foreign,b,sb);await actor(differentSID,a,sa2);await actor(race1);await actor(race2);
 const cap=(await self.query('select public.employee_bank_initial_capability($1,$2) v',[company,w])).rows[0].v;
 assert.equal(cap.enabled,false);assert.equal(cap.registered,false);assert.equal(cap.worker_id,w);
 assert.equal((await admin.query('select private.employee_bank_initial_digest($1,$2,$3) h',[company,w,data])).rows[0].h,target(w).input_sha256);
 const save=(client,worker,proof,value=data,companyId=company)=>client.query('select public.register_employee_bank_initial($1,$2,$3,$4) v',[companyId,worker,value,proof]);
 await deny(save(self,w,'a'.repeat(64)));
 // Validate the unused restore while genuine original self-owned data exists.
 await foreign.query('insert into public.worker_private_bank_accounts(worker_id,company_id,bank_name,branch_name,account_type,account_number,account_holder) values($1,$2,$3,$4,$5,$6,$7)',[selfWorker,company,...Object.values(data)]);
 const selfOriginal=(await admin.query('select md5(to_jsonb(b)::text) h from public.worker_private_bank_accounts b where worker_id=$1',[selfWorker])).rows[0].h;
 await admin.query(restore);assert.deepEqual(await originalFunctions(),originals);
 assert.equal((await admin.query('select md5(to_jsonb(b)::text) h from public.worker_private_bank_accounts b where worker_id=$1',[selfWorker])).rows[0].h,selfOriginal);
 await admin.query(forward);
 await admin.query("create or replace function private.employee_bank_initial_enabled() returns boolean language sql stable security definer set search_path='' as $$select true$$");
 async function issue(worker=w,value=data) {
  const nonce=randomBytes(32).toString('hex');
  await issuer.query("select set_config('request.jwt.claims','{\"role\":\"service_role\"}',false);set role service_role");
  try {await issuer.query('select public.issue_reauthentication_proof($1,$2,$3,$4,$5)',[a,sa,'employee.bank.initial',target(worker,value),hash(nonce)]);return nonce;}
  finally {await issuer.query('reset role');}
 }
 // Neither a plain table call nor a user-controlled setting can forge context.
 await self.query("select set_config('sko.employee_bank_initial_context','true',false)");
 await deny(self.query('insert into private.employee_bank_initial_context(transaction_id,actor_id,session_id,company_id,worker_id,input_sha256,proof_hash) values(pg_current_xact_id(),$1,$2,$3,$4,$5,$5)',[a,sa,company,w,'a'.repeat(64)]));
 await deny(self.query('insert into public.worker_private_bank_accounts(worker_id,company_id,bank_name,branch_name,account_type,account_number,account_holder) values($1,$2,$3,$4,$5,$6,$7)',[w,company,...Object.values(data)]),['P0001','42501']);
 const proof=await issue();
 await deny(save(differentSID,w,proof));await deny(save(foreign,w,proof));
 await deny(save(self,foreignWorker,proof,data,company));
 await deny(save(self,w,proof,{...data,account_number:'0000002'}));
 assert.equal((await admin.query('select consumed_at from private.reauthentication_proofs where proof_hash=$1',[hash(proof)])).rows[0].consumed_at,null);
 const beforeClaims=(await self.query('select auth.uid() actor,auth.jwt() claims')).rows[0];
 const receipt=(await save(self,w,proof)).rows[0].v;
 assert.deepEqual(Object.keys(receipt).sort(),['company_id','protocol','registered','updated_at','worker_id']);
 assert.equal(receipt.worker_id,w);assert.equal(receipt.company_id,company);assert.equal(receipt.registered,true);
 assert.deepEqual((await self.query('select auth.uid() actor,auth.jwt() claims')).rows[0],beforeClaims);
 const rowHash=async()=>(await admin.query('select md5(to_jsonb(b)::text) h from public.worker_private_bank_accounts b where worker_id=$1',[w])).rows[0].h;
 const initialHash=await rowHash();await deny(save(self,w,proof),['23505']);assert.equal(await rowHash(),initialHash);
 assert.equal((await admin.query('select count(*)::int n from private.employee_bank_initial_context')).rows[0].n,0);
 assert.deepEqual((await admin.query('select attachment_path,notes from public.worker_document_statuses where worker_id=$1',[w])).rows[0],{attachment_path:'SYNTHETIC-ORIGINAL-PATH',notes:'SYNTHETIC-ORIGINAL-NOTE'});
 const raceProof1=await issue(raceWorker),raceProof2=await issue(raceWorker);
 const race=await Promise.allSettled([save(race1,raceWorker,raceProof1),save(race2,raceWorker,raceProof2)]);
 assert.equal(race.filter(r=>r.status==='fulfilled').length,1);assert.equal(race.filter(r=>r.status==='rejected'&&r.reason.code==='23505').length,1);
 assert.equal((await admin.query('select md5(to_jsonb(b)::text) h from public.worker_private_bank_accounts b where worker_id=$1',[selfWorker])).rows[0].h,selfOriginal);
 assert.deepEqual(await preserved(),originalPayroll);
 assert.equal((await admin.query('select count(*)::int n from private.employee_bank_initial_context')).rows[0].n,0);
 const storedBefore=(await admin.query('select md5(jsonb_agg(to_jsonb(b) order by worker_id)::text) h from public.worker_private_bank_accounts b')).rows[0].h;
 const proofsBefore=(await admin.query('select md5(jsonb_agg(to_jsonb(p) order by proof_hash)::text) h from private.reauthentication_proofs p')).rows[0].h;
 await admin.query("create or replace function private.employee_bank_initial_enabled() returns boolean language sql stable security definer set search_path='' as $$select false$$");
 await deny(admin.query(restore),['55000']);await admin.query('rollback');
 assert.equal((await admin.query('select md5(jsonb_agg(to_jsonb(b) order by worker_id)::text) h from public.worker_private_bank_accounts b')).rows[0].h,storedBefore);
 assert.equal((await admin.query('select md5(jsonb_agg(to_jsonb(p) order by proof_hash)::text) h from private.reauthentication_proofs p')).rows[0].h,proofsBefore);
 assert.deepEqual(await preserved(),originalPayroll);
 console.log(JSON.stringify({pass:true,default_off:true,original_definition_drift_rejected:true,canonical_digest:true,real_guards_reused:true,selected_employee_not_actor:true,foreign_and_sid_and_digest_denied:true,forged_context_denied:true,concurrent_single_insert:true,self_path_retained:true,originals_and_payroll_unchanged:true,unused_restore_preserves_original_attributes_and_used_history_refuses_restore:true}));
}finally{await Promise.allSettled(clients.map(client=>client.end()));}
