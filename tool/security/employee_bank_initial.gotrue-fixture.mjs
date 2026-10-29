// Synthetic application rows; actual GoTrue/JWT/password/proof/SQL boundaries.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import path from 'node:path';
const id=n=>`20000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const sha=value=>createHash('sha256').update(value).digest('hex');
export async function verifyEmployeeBankInitial({db,api,publicKey,serviceKey,users,sessions,password,request,rpc,eq}){
 let stage='setup';
 try{
  const authBefore=(await db.query("select jsonb_agg(jsonb_build_object('oid',oid::text,'definition',pg_get_functiondef(oid)) order by oid) value from pg_proc where oid in('auth.uid()'::regprocedure,'auth.jwt()'::regprocedure)")).rows[0].value;
  for(const file of ['tool/security/employee_bank_initial/fixture-business.sql','tool/security/employee_bank_initial/baseline-functions.sql','tool/staged/employee_bank_initial_registration.sql.review-only']){
   const sql=await fs.readFile(file,'utf8');
   assert.ok(!/\b(?:insert\s+into|update|delete\s+from|truncate(?:\s+table)?)\s+auth\./i.test(sql));
   await db.query(sql);
  }
  const A=id(1),B=id(2),W=id(3),W2=id(4),W3=id(5),W4=id(6),R=id(7);
  await db.query("insert into public.companies values($1,'Synthetic A'),($2,'Synthetic B')",[A,B]);
  await db.query("insert into public.company_members values($1,$2,'manager'),($3,$4,'admin'),($1,$5,'employee'),($1,$6,'manager')",[A,users.owner.id,B,users.othercompany.id,users.outsider.id,users.revoked.id]);
  await db.query('insert into public.member_feature_permissions(company_id,user_id,can_manage_payroll) values($1,$2,true),($1,$3,true)',[A,users.owner.id,users.revoked.id]);
  await db.query("insert into public.workers(id,company_id,user_id) values($1,$2,null),($3,$4,null),($5,$2,null),($6,$2,null)",[W,A,W2,B,W3,W4]);
  await db.query("insert into public.document_requirements values($1,$2,'銀行口座情報',true)",[R,A]);
  await db.query("insert into public.payroll_statements values($1,$2,$3,'{\"synthetic\":\"retained\"}')",[id(80),A,W]);
  await db.query("insert into payroll_final_private.documents values($1,'{\"synthetic_signature\":\"retained\"}')",[id(80)]);
  await db.query("insert into payroll_final_private.history values($1,'{\"synthetic_original\":\"retained\"}')",[id(81)]);
  const original=async()=>(await db.query("select jsonb_build_object('payroll',(select jsonb_agg(to_jsonb(t)) from public.payroll_statements t),'documents',(select jsonb_agg(to_jsonb(t)) from payroll_final_private.documents t),'history',(select jsonb_agg(to_jsonb(t)) from payroll_final_private.history t)) value")).rows[0].value;
  const originalsBefore=await original();
  await db.query("notify pgrst,'reload schema'");
  const token=sessions.owner.access_token;
  const input={bank_name:'Synthetic Bank',branch_name:'Synthetic Branch',account_type:'普通',account_number:'1234567',account_holder:'SYNTHETIC WORKER'};
  const digest=(company,worker,data)=>sha('sko-employee-bank-initial-v1\n'+[company.toLowerCase(),worker.toLowerCase(),data.bank_name,data.branch_name,data.account_type,data.account_number,data.account_holder].map(value=>Buffer.byteLength(value,'utf8')+':'+value).join('\n'));
  const target=(worker=W,company=A,data=input)=>({company_id:company,worker_id:worker,input_sha256:digest(company,worker,data)});
  const cap=(worker=W,company=A,access=token)=>rpc('employee_bank_initial_capability',{p_company_id:company,p_worker_id:worker},access);
  const save=(proof,worker=W,company=A,data=input,access=token)=>rpc('register_employee_bank_initial',{p_company_id:company,p_worker_id:worker,p_bank_data:data,p_proof:proof},access);
  const ledger=async()=>(await db.query('select count(*)::int n from private.reauthentication_proofs where consumed_at is not null')).rows[0].n;
  const bankCount=async()=>(await db.query('select count(*)::int n from public.worker_private_bank_accounts')).rows[0].n;
  const deny=async response=>{assert.ok(response.status>=400);eq(await bankCount(),0);eq(await ledger(),0);};
  // Schema cache readiness is bounded and retries only its explicit missing-RPC code.
  let capability;
  for(let attempt=0;attempt<30;attempt++){
   const response=await cap();
   if(response.status===200){capability=await response.json();break;}
   const value=await response.json();assert.equal(value.code,'PGRST202');
   await new Promise(resolve=>setTimeout(resolve,100));
  }
  assert.ok(capability);eq(capability.enabled,false);eq(capability.registered,false);
  stage='off-no-write';await deny(await save('a'.repeat(64)));
  // Only the disposable application fixture enables the private review gate.
  await db.query('create or replace function private.employee_bank_initial_enabled() returns boolean language sql stable as $$select true$$');
  eq((await (await cap()).json()).enabled,true);
  eq((await db.query('select private.employee_bank_initial_digest($1,$2,$3::jsonb) value',[A,W,input])).rows[0].value,target().input_sha256);
  const {createReauthenticationHandler}=await import(pathToFileURL(path.join(process.cwd(),'supabase/functions/reauthenticate-operation/handler.mjs')).href);
  const handler=createReauthenticationHandler({baseUrl:api.origin,publicKey,serviceKey});
  const issueResponse=(scope=target(),access=token,secret=password)=>handler(new Request('https://synthetic.invalid/reauthenticate',{method:'POST',headers:{authorization:'Bearer '+access,'content-type':'application/json'},body:JSON.stringify({operation:'employee.bank.initial',target:scope,password:secret})}));
  const issue=async(scope=target(),access=token)=>{const before=(await db.query('select count(*)::int n from auth.sessions')).rows[0].n;const response=await issueResponse(scope,access);eq(response.status,200);const value=await response.json();eq(value.protocol,'sko-reauthentication-v1');assert.match(value.proof,/^[a-f0-9]{64}$/);eq(value.operation,'employee.bank.initial');eq(value.target,scope);eq((await db.query('select count(*)::int n from auth.sessions')).rows[0].n,before);return value.proof;};
  stage='first-password-required';assert.ok((await issueResponse(target(),token,'wrong-synthetic-password')).status>=400);await deny(await save('b'.repeat(64)));
  stage='proof-digest-worker-company';const proof=await issue();
  await deny(await save(proof,W,A,{...input,account_number:'7654321'}));
  await deny(await save(proof,W3));await deny(await save(proof,W2,B));
  stage='foreign-actor';for(const access of [sessions.outsider.access_token,sessions.othercompany.access_token])await deny(await save(proof,W,A,input,access));
  stage='foreign-live-session';
  const newLogin=await request('/auth/v1/token?grant_type=password',{body:{email:users.owner.email,password}});eq(newLogin.status,200);const newSession=await newLogin.json();
  assert.notEqual(JSON.parse(Buffer.from(newSession.access_token.split('.')[1],'base64url')).session_id,JSON.parse(Buffer.from(token.split('.')[1],'base64url')).session_id);
  await deny(await save(proof,W,A,input,newSession.access_token));
  stage='authority-rechecked';await db.query('update public.member_feature_permissions set can_manage_payroll=false where company_id=$1 and user_id=$2',[A,users.owner.id]);
  await deny(await save(proof));
  await db.query('update public.member_feature_permissions set can_manage_payroll=true where company_id=$1 and user_id=$2',[A,users.owner.id]);
  stage='expired-proof';const expired=await issue(target(W3));
  await db.query("update private.reauthentication_proofs set issued_at=clock_timestamp()-interval '300 seconds',expires_at=clock_timestamp()-interval '200 seconds' where proof_hash=$1",[sha(expired)]);
  await deny(await save(expired,W3));
  stage='revoked-original-session';const revokedProof=await issue(target(W4),sessions.revoked.access_token);
  const revokedClaims=JSON.parse(Buffer.from(sessions.revoked.access_token.split('.')[1],'base64url'));
  const logout=await request('/auth/v1/logout?scope=local',{token:sessions.revoked.access_token});assert.ok([200,204].includes(logout.status));
  eq((await db.query('select count(*)::int n from auth.sessions where id=$1',[revokedClaims.session_id])).rows[0].n,0);
  await deny(await save(revokedProof,W4,A,input,sessions.revoked.access_token));
  stage='single-initial-write';const response=await save(proof);eq(response.status,200);const result=await response.json();
  eq(Object.keys(result).sort(),['company_id','protocol','registered','updated_at','worker_id']);eq(result.registered,true);eq(result.company_id,A);eq(result.worker_id,W);eq(result.protocol,'sko-employee-bank-initial-v1');assert.ok(Number.isFinite(Date.parse(result.updated_at)));
  eq(await bankCount(),1);eq(await ledger(),1);
  const retained=async()=>(await db.query('select md5(to_jsonb(t)::text) value from public.worker_private_bank_accounts t where worker_id=$1',[W])).rows[0].value;
  const retainedBefore=await retained();
  stage='singleuse-and-existing-row';assert.ok((await save(proof)).status>=400);assert.ok((await save('c'.repeat(64),W,A,{...input,account_number:'7654321'})).status>=400);
  eq(await retained(),retainedBefore);eq(await bankCount(),1);eq(await ledger(),1);eq(await original(),originalsBefore);
  eq((await db.query("select jsonb_agg(jsonb_build_object('oid',oid::text,'definition',pg_get_functiondef(oid)) order by oid) value from pg_proc where oid in('auth.uid()'::regprocedure,'auth.jwt()'::regprocedure)")).rows[0].value,authBefore);
  console.log('PASS isolated real GoTrue first password -> standard proof issuer -> exact company/worker/digest and live SID -> one initial bank row; expired/foreign/permission-revoked/single-use failures preserve rows, ledger, payroll originals and auth functions; production unchanged');
 }catch(error){error.code='EMPLOYEE_BANK_'+stage.replaceAll('-','_').toUpperCase();throw error;}
}
