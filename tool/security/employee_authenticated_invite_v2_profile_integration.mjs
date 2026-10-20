import assert from 'node:assert/strict';import fs from 'node:fs';import {createHash} from 'node:crypto';
if(!process.env.SKO_PGLITE_MODULE)throw Error('Pinned PGlite 0.3.14 entrypoint required');
const {PGlite}=await import(process.env.SKO_PGLITE_MODULE),db=new PGlite();const root=new URL('../../',import.meta.url);
const read=p=>fs.readFileSync(new URL(p,root),'utf8'),sql='docs/candidates/employee_authenticated_invite_v2.sql.review-only';
const patch=read('docs/candidates/employee_authenticated_invite_v2_profile_gate.sql.review-only');
const id=n=>`20000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const company=id(1),owner=id(2),actor=id(3),worker=id(4),sid=id(5),legacy=id(6),identity=id(7),approved=id(8),wrongSid=id(9);
const token='ab'.repeat(32),hash=createHash('sha256').update(token).digest('hex');
const signature='public.save_employee_onboarding_profile(text,text,text,text,text,text,text,text,text,text)';
let checks=0;
const q=(s,a=[])=>db.query(s,a);
async function login(uid,session=sid){await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[uid,JSON.stringify({sub:uid,session_id:session})]);await db.exec('set role authenticated');}
const reset=()=>db.exec('reset role');
const save=(values=['address','unknown','family','relation','contact','phone','address',null,null,null])=>q('select public.save_employee_onboarding_profile($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)',values);
const deny=async f=>{await assert.rejects(f,e=>['P0001','42501','55000'].includes(e.code));checks++;};
const meta=async()=>(await q(`select oid,proacl::text acl,proconfig,prosrc,prosecdef,proowner from pg_proc where oid='${signature}'::regprocedure`)).rows[0];
async function applyPatch(){try{await db.exec(patch);}catch(e){await db.exec('rollback');throw e;}}
try{
 await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;create schema private;
 create table auth.users(id uuid primary key,encrypted_password text);create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
 create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create function auth.jwt() returns jsonb language sql as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 create function private.account_access_allowed() returns boolean language sql as $$select auth.uid() is not null$$;
 create table public.companies(id uuid primary key);
 create table public.workers(id uuid primary key,company_id uuid,name text,phone text,affiliation text,user_id uuid,status text);
 create table public.company_members(company_id uuid,user_id uuid,role text);
 create table public.company_approval_assignees(company_id uuid,user_id uuid);
 create table private.fixture_notifications(id uuid default gen_random_uuid(),recipient uuid);
 create function private.enqueue_notification(uuid,uuid,text,text,text,text,uuid) returns uuid language sql as $$insert into private.fixture_notifications(recipient) values($2) returning id$$;
 grant usage on schema public,auth,private to authenticated;`);
 await db.exec(read('tool/security/employee_invite_foundation.main.fixture.sql'));
 await db.exec(`alter table public.employee_registration_invites add column identity_verified_at timestamptz,add column address text,add column blood_type text,add column family_composition text,add column emergency_relation text,add column emergency_name text,add column emergency_phone text,add column emergency_address text,add column portrait_path text,add column my_number_front_path text,add column my_number_back_path text,add column submitted_at timestamptz;`);
 await db.exec(read(sql));
 await q('insert into auth.users values($1,$6),($2,$6),($3,$6),($4,$6),($5,$6)',[owner,actor,legacy,identity,approved,'unchanged-permanent-hash']);
 await q('insert into auth.sessions values($1,$2,null),($3,$2,null)',[sid,actor,wrongSid]);
 await q('insert into public.companies values($1)',[company]);await q("insert into public.company_members values($1,$2,'owner')",[company,owner]);
 await q("insert into public.workers values($1,$2,'Employee','09012345678','employee',null,'active')",[worker,company]);
 await q('insert into private.employee_authenticated_invite_v2_rollout values($1,true)',[company]);
 await login(owner,id(10));const issued=(await q('select public.issue_employee_authenticated_invite_v2($1,$2,$3,$4) value',[company,worker,id(11),hash])).rows[0].value;
 await login(actor,sid);const receipt=(await q('select public.redeem_employee_authenticated_invite_v2($1,$2,$3,$4,true) value',[issued.invite_id,issued.generation,token,id(12)])).rows[0].value;
 await reset();
 for(const [uid,phone,status,password,verified] of [[legacy,'+819000000001','profile_pending',true,false],[identity,'+819000000002','profile_pending',false,true],[approved,'+819000000003','approved',true,true]])
  await q("insert into public.employee_registration_invites(company_id,worker_id,auth_user_id,name,phone_e164,status,created_by,password_changed_at,identity_verified_at) values($1,$2,$3,'Legacy',$4,$5,$6,case when $7 then now() end,case when $8 then now() end)",[company,worker,uid,phone,status,owner,password,verified]);
 for(const variant of ['main','retained']){
  await db.exec(read(`tool/security/employee_onboarding_profile.${variant}.fixture.sql`));
  await db.exec(`revoke all on function ${signature} from public,anon,authenticated,service_role;grant execute on function ${signature} to authenticated,service_role;`);
  await login(actor);await deny(()=>save());await reset();const before=await meta();
  await applyPatch();const after=await meta();assert.deepEqual({...before,prosrc:undefined},{...after,prosrc:undefined});checks++;
  const old='and (eri.password_changed_at is not null or eri.identity_verified_at is not null)';
  const replacement='and case when exists(select 1 from private.employee_authenticated_invite_v2 l where l.product_invite_id=eri.id)\n      then private.employee_authenticated_invite_v2_proof_valid(eri.id)\n      else (eri.password_changed_at is not null or eri.identity_verified_at is not null) end';
  assert.equal(after.prosrc,before.prosrc.replace(old,replacement));checks++;
  await login(actor);await save();await reset();
  let row=(await q('select * from public.employee_registration_invites where id=$1',[receipt.invite_id])).rows[0];assert.equal(row.status,'approval_pending');assert.equal(row.password_changed_at,null);assert.equal(row.identity_verified_at,null);checks++;
  assert.equal((await q('select count(*)::int n from public.company_members where user_id=$1',[actor])).rows[0].n,0);assert.equal((await q('select user_id from public.workers where id=$1',[worker])).rows[0].user_id,null);checks++;
  await q('update public.employee_registration_invites set password_changed_at=now(),identity_verified_at=now() where id=$1',[receipt.invite_id]);
  await login(actor,wrongSid);await deny(()=>save());await reset();await q('update public.employee_registration_invites set password_changed_at=null,identity_verified_at=null where id=$1',[receipt.invite_id]);
  await q("update auth.sessions set not_after=now()-interval '1 second' where id=$1",[sid]);await login(actor);await deny(()=>save());await reset();await q('update auth.sessions set not_after=null where id=$1',[sid]);
  await q("update private.employee_authenticated_invite_v2 set expires_at=now()-interval '1 second' where id=$1",[issued.invite_id]);await login(actor);await deny(()=>save());await reset();await q("update private.employee_authenticated_invite_v2 set expires_at=now()+interval '1 day' where id=$1",[issued.invite_id]);
  await q("update private.employee_authenticated_invite_v2 set state='cancelled' where id=$1",[issued.invite_id]);await login(actor);await deny(()=>save());await reset();await q("update private.employee_authenticated_invite_v2 set state='redeemed' where id=$1",[issued.invite_id]);
  await login(legacy);await save();await login(identity);await save();checks+=2;await login(approved);await deny(()=>save());await reset();
  await login(actor);await deny(()=>save(['address','unknown','family','relation','contact','phone','address','fake.jpg',null,null]));await deny(()=>save(['','unknown','family','relation','contact','phone','address',null,null,null]));await reset();
  if(variant==='retained'){
   await q("update public.employee_registration_invites set portrait_path='existing-portrait',my_number_front_path='existing-front',my_number_back_path='existing-back' where id=$1",[receipt.invite_id]);await login(actor);await save();await reset();
   row=(await q('select portrait_path,my_number_front_path,my_number_back_path from public.employee_registration_invites where id=$1',[receipt.invite_id])).rows[0];assert.deepEqual(row,{portrait_path:'existing-portrait',my_number_front_path:'existing-front',my_number_back_path:'existing-back'});checks++;
  }
  await deny(()=>applyPatch()); // Already patched source cannot be blindly replaced.
 }
 await db.exec(read('tool/security/employee_onboarding_profile.retained.fixture.sql'));
 const proofDefinition=(await q("select pg_get_functiondef('private.employee_authenticated_invite_v2_proof_valid(uuid)'::regprocedure) definition")).rows[0].definition;
 await db.exec(proofDefinition.replace('l.expires_at>clock_timestamp()',`l.expires_at>clock_timestamp()-interval '1 hour'`));await deny(()=>applyPatch());await db.exec(proofDefinition);
 await db.exec('grant execute on function private.employee_authenticated_invite_v2_proof_valid(uuid) to authenticated');await deny(()=>applyPatch());await db.exec('revoke execute on function private.employee_authenticated_invite_v2_proof_valid(uuid) from authenticated');
 await db.exec(read('tool/security/employee_onboarding_profile.retained.fixture.sql').replace('required onboarding field missing','drifted field validation'));await deny(()=>applyPatch());
 assert.equal((await q('select count(distinct encrypted_password)::int n from auth.users')).rows[0].n,1);checks++;
 console.log(JSON.stringify({result:'PASS authenticated invite profile gate',checks,source_variants:2,source_hash_guard:true,oid_acl_preserved:true,legacy_password_and_identity_preserved:true,password_markers_not_fabricated:true,preapproval_membership:false,photos_retained_in_retention_variant:true,storage_proven:false,production_changes:false}));
}catch(e){console.error(JSON.stringify({result:'FAIL',code:e.code,message:e.message}));process.exitCode=1;}finally{await db.close();}
