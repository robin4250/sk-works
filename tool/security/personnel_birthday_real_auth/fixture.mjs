// Real local GoTrue JWTs and PostgREST, with saved canonical personnel SQL.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {setupRealPersonnelFoundation} from './foundation.mjs';
const sha=value=>createHash('sha256').update(value).digest('hex');
export async function verifyPersonnelBirthdayRealAuth({db,users,sessions,password,request,rpc,eq}){
 let stage='genuine-extra-actors';
 try{
  assert.match((await db.query('show server_version')).rows[0].server_version,/^17\./);
  for(const name of ['managerOff','managerOn','viewer','employee','deleted','retiredSelf']){
   const created=await request('/auth/v1/admin/users',{service:true,body:{email:name.toLowerCase()+'@example.invalid',password,email_confirm:true}});eq(created.status,200);users[name]=await created.json();
   const login=await request('/auth/v1/token?grant_type=password',{body:{email:users[name].email,password}});eq(login.status,200);sessions[name]=await login.json();
   const claims=JSON.parse(Buffer.from(sessions[name].access_token.split('.')[1],'base64url'));
   eq(claims.sub,users[name].id);assert.ok(claims.session_id);
   eq((await db.query('select count(*)::int n from auth.sessions where id=$1 and user_id=$2',[claims.session_id,users[name].id])).rows[0].n,1);
  }
  const actors={owner:users.owner.id,admin:users.revoked.id,self:users.outsider.id,outsider:users.othercompany.id,
   ...Object.fromEntries(['managerOff','managerOn','viewer','employee','deleted','retiredSelf'].map(key=>[key,users[key].id]))};
  const authCatalog=async()=>(await db.query("select jsonb_agg(jsonb_build_object('name',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid),'owner',p.proowner,'acl',p.proacl::text,'config',p.proconfig) order by p.oid) v from pg_proc p where p.oid in('auth.uid()'::regprocedure,'auth.jwt()'::regprocedure)")).rows[0].v;
  const beforeAuth=await authCatalog();
  stage='exact-foundation';const {C,F,W,WF}=await setupRealPersonnelFoundation({db,actors});
  eq(await authCatalog(),beforeAuth);
  const originalAttrs=async()=>(await db.query("select p.oid::regprocedure::text signature,pg_get_userbyid(p.proowner) owner,p.proacl::text acl,p.proconfig,p.prosecdef,p.provolatile,p.proisstrict,p.proleakproof,p.proparallel,p.prokind,p.proretset,p.prorettype::regtype::text return_type from pg_proc p where p.oid=any($1::regprocedure[]) order by 1",[['private.worker_personnel_payload(uuid)','private.apply_worker_personnel_payload(uuid,jsonb,uuid)','private.employee_personnel_view(uuid)','public.save_worker_personnel_profile(uuid,jsonb)']])).rows;
  const attrsBefore=await originalAttrs();
  const sources=[
   ['tool/staged/employee_personnel_birth_date.sql.review-only','47005bf6973ad86c99af8ecad60f4576596e3c8ee547b1fb01baab78961a6cb5'],
   ['tool/staged/personnel_birthday_noop.sql.review-only','c4ae672ce99c6a6dc6e3eca1d892345995ed4eea7c72779a11ed3772b383bca3'],
  ];
  for(const [file,hash] of sources){const sql=await fs.readFile(file,'utf8');eq(sha(sql),hash);await db.query(sql);}
  eq(await originalAttrs(),attrsBefore);eq(await authCatalog(),beforeAuth);
  // Existing canonical account pre-request hook, exact saved source; no SID gate is added.
  await db.query("alter role authenticator set pgrst.db_pre_request='private.check_account_access';notify pgrst,'reload config';notify pgrst,'reload schema'");
  const token=key=>sessions[key].access_token;
  const owner=token('owner'),self=token('outsider'),foreign=token('othercompany');
  stage='actual-hook-and-contract';
  let ready=false;
  for(let attempt=0;attempt<40;attempt++){
   const res=await rpc('fixture_account_hook_status',{},owner);const value=await res.json();
   if(res.status===200&&value.hook==='data-api-v1'){eq(value.actor_present,true);ready=true;break;}
   assert.ok(res.status===200||value.code==='PGRST202');
   await new Promise(resolve=>setTimeout(resolve,100));
  }
  assert.ok(ready,'Exact saved account pre-request hook must run');
  const view=async(access=owner,company=C)=>{const response=await rpc('employee_personnel_view',{p_company:company},access);eq(response.status,200);const value=await response.json();eq(value.company_id,company);eq(value.birth_date_contract_version,1);return value;};
  const record=async()=>{const records=(await view()).records.filter(row=>row.id===W);eq(records.length,1);eq(records[0].birthDateContractVersion,1);return records[0];};
  // Same key mapping as the existing client; the payload comes from an authorized HTTP read.
  const payload=(row,withDate=true)=>({name:row.name,kind:row.kind,...(withDate?{birth_date:row.birthDate}:{}),
   blood_type:row.bloodType,role:row.role,employee_number:row.employeeNumber,department:row.department,hire_date:row.hireDate,phone:row.phone,address:row.address,
   emergency_name:row.emergencyName,emergency_relation:row.emergencyRelation,emergency_phone:row.emergencyPhone,emergency_address:row.emergencyAddress,
   family_composition:row.familyComposition,family_members:row.familyMembers});
  const save=(data,access=owner,worker=W)=>rpc('save_worker_personnel_profile',{p_worker_id:worker,p_payload:data},access);
  const decide=(id,access=owner)=>rpc('decide_worker_personnel_change',{p_request_id:id,p_approve:true},access);
  const state=async()=>(await db.query("select jsonb_build_object('workers',(select jsonb_agg(to_jsonb(t) order by id) from public.workers t),'profiles',(select jsonb_agg(to_jsonb(t) order by worker_id) from public.worker_personnel_profiles t),'family',(select jsonb_agg(to_jsonb(t) order by id) from public.worker_family_members t),'requests',(select jsonb_agg(to_jsonb(t) order by id) from public.worker_personnel_change_requests t),'approvals',(select jsonb_agg(to_jsonb(t) order by request_id,approver_user_id) from public.worker_personnel_change_approvals t),'notifications',(select jsonb_agg(to_jsonb(t) order by id) from public.app_notifications t)) v")).rows[0].v;
  const denyUnchanged=async action=>{const before=await state();const response=await action();assert.ok(response.status>=400);eq(await state(),before);};
  eq((await record()).birthDate,null);
  stage='canonical-direct-save-marker-omission';
  let response=await save({...payload(await record()),birth_date:'1980-02-29'});eq(response.status,200);eq((await response.json()).status,'saved');eq((await record()).birthDate,'1980-02-29');
  const noMarker=payload(await record());assert.equal(Object.hasOwn(noMarker,'birth_date_contract_version'),false);
  const beforeNoop=await state();response=await save(noMarker);eq(response.status,200);eq((await response.json()).status,'unchanged');eq(await state(),beforeNoop);
  stage='self-pending-two-actor-approval';
  response=await save({...payload(await record()),birth_date:'1990-01-01'},self);eq(response.status,200);const pending=await response.json();eq(pending.status,'pending');eq(pending.required_approvals,1);eq((await record()).birthDate,'1980-02-29');
  await denyUnchanged(()=>decide(pending.request_id,self));await denyUnchanged(()=>decide(pending.request_id,foreign));
  response=await decide(pending.request_id);eq(response.status,200);eq((await response.json()).status,'approved');eq((await record()).birthDate,'1990-01-01');
  stage='same-and-other-company-scope';
  const current=payload(await record());
  await denyUnchanged(()=>save({...current,birth_date:'2000-01-01'},token('employee')));
  await denyUnchanged(()=>save({...current,birth_date:'2000-01-01'},foreign));
  await denyUnchanged(()=>save({...current,birth_date:'2000-01-01'},owner,WF));
  const foreignRead=await rpc('employee_personnel_view',{p_company:F},owner);assert.ok(foreignRead.status>=400);
  const anon=await rpc('save_worker_personnel_profile',{p_worker_id:W,p_payload:current},undefined);assert.ok(anon.status>=400);
  stage='old-client-omission-through-approval';
  const oldClient={...payload(await record(),false),address:'SYNTHETIC OLD CLIENT PROPOSED ADDRESS'};
  response=await save(oldClient,self);eq(response.status,200);const omitted=await response.json();eq(omitted.status,'pending');eq((await record()).birthDate,'1990-01-01');
  const stored=(await db.query('select requested_by,proposed from public.worker_personnel_change_requests where id=$1',[omitted.request_id])).rows[0];eq(stored.requested_by,actors.self);eq(Object.hasOwn(stored.proposed,'birth_date'),false);
  response=await decide(omitted.request_id);eq(response.status,200);eq((await response.json()).status,'approved');eq((await record()).birthDate,'1990-01-01');eq((await record()).address,oldClient.address);
  stage='nullable-clear-and-old-client-noop';
  response=await save({...payload(await record()),birth_date:null});eq(response.status,200);eq((await response.json()).status,'saved');eq((await record()).birthDate,null);
  response=await save(payload(await record(),false),self);eq(response.status,200);eq((await response.json()).status,'unchanged');eq((await record()).birthDate,null);
  stage='existing-session-revocation-boundary-observation';
  const oldJwtNoop=payload(await record(),false),beforeRevocation=await state();
  const sid=JSON.parse(Buffer.from(self.split('.')[1],'base64url')).session_id;
  const logout=await request('/auth/v1/logout?scope=local',{token:self});assert.ok([200,204].includes(logout.status));
  eq((await db.query('select count(*)::int n from auth.sessions where id=$1',[sid])).rows[0].n,0);
  const afterLogout=await save(oldJwtNoop,self);
  const revokedJwtAcceptedUntilExpiry=afterLogout.status===200;
  if(revokedJwtAcceptedUntilExpiry)eq((await afterLogout.json()).status,'unchanged');
  else assert.ok([401,403].includes(afterLogout.status));
  eq(await state(),beforeRevocation);eq(await authCatalog(),beforeAuth);eq(await originalAttrs(),attrsBefore);
  console.log(JSON.stringify({pass:true,real_gotrue:true,real_postgrest:true,native_pg17:true,synthetic_business_fixture:true,canonical_http_save_and_two_actor_approval:true,old_client_omission_and_nullable_contract:true,auth_uid_jwt_definitions_unchanged:true,revoked_jwt_noop_accepted_until_expiry:revokedJwtAcceptedUntilExpiry,live_sid_guarantee_added:false,old_suites_repeated:false,production_changed:false}));
 }catch(error){console.error(JSON.stringify({stage,sqlstate:error.code??null,position:error.position??null}));error.code='PERSONNEL_BIRTHDAY_'+stage.replaceAll('-','_').toUpperCase();throw error;}
}
