import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
const {PGlite}=await import(pathToFileURL(process.argv[2]).href);
const db=new PGlite();
const id=n=>`10000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const [company,other,owner,manager,employee,another,foreign,worker,worker2,requirement,sid]=Array.from({length:11},(_,i)=>id(i+1));
try {
 await db.exec(`create role anon;create role authenticated;create schema auth;create schema private;
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
 create function auth.jwt() returns jsonb language sql stable as $$select jsonb_build_object('role','authenticated','session_id',current_setting('test.sid',true),'is_anonymous',false)$$;
 create table auth.users(id uuid primary key,is_anonymous boolean default false,banned_until timestamptz);
 create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
 create function private.account_access_allowed() returns boolean language sql stable as $$select current_setting('test.blocked',true) is distinct from 'yes'$$;
 create function private.account_deletion_barrier_key(uuid) returns bigint language sql immutable as $$select hashtextextended($1::text,765)$$;
 create table public.company_members(company_id uuid,user_id uuid,role text);
 create table public.workers(id uuid primary key,company_id uuid,user_id uuid,status text);
 create table public.document_requirements(id uuid primary key,company_id uuid,name text,is_active boolean,is_required boolean,sort_order integer);
 create table public.worker_document_statuses(id uuid primary key,company_id uuid,worker_id uuid,requirement_id uuid,status text,attachment_path text);
 create table public.worker_private_bank_accounts(worker_id uuid,company_id uuid);
 grant usage on schema public,auth,private to authenticated,anon;
 `);
 // Exact existing session boundary, with disposable auth rows (not GoTrue).
 await db.exec(`create function private.require_reauthentication_session() returns uuid language plpgsql security definer set search_path='' as $$
 declare actor uuid:=auth.uid();sid uuid;
 begin
 if actor is null or auth.jwt()->>'role' is distinct from 'authenticated'
  or coalesce(auth.jwt()->>'is_anonymous','false')<>'false'
  or not private.account_access_allowed() then raise sqlstate '42501' using message='reauthentication_required';end if;
 begin sid:=(auth.jwt()->>'session_id')::uuid;exception when invalid_text_representation then raise sqlstate '42501' using message='reauthentication_required';end;
 if sid is null or not pg_try_advisory_xact_lock_shared(private.account_deletion_barrier_key(actor)) then raise sqlstate '42501' using message='reauthentication_required';end if;
 perform 1 from auth.users where id=actor and not coalesce(is_anonymous,false) and (banned_until is null or banned_until<=clock_timestamp()) for share;
 if not found then raise sqlstate '42501' using message='reauthentication_required';end if;
 perform 1 from auth.sessions where id=sid and user_id=actor and (not_after is null or not_after>clock_timestamp()) for share;
 if not found then raise sqlstate '42501' using message='reauthentication_required';end if;
 return sid;end $$;`);
 let attention=await fs.readFile(new URL('../supabase/migrations/20260922010000_add_required_document_attention.sql',import.meta.url),'utf8');
 attention=attention.replace("or wds.status in ('not_submitted','missing','expired')",`or wds.status in ('not_submitted','missing','expired')
      or (dr.name <> '銀行口座情報' and nullif(wds.attachment_path, '') is null)
      or (dr.name = '銀行口座情報' and not exists (
        select 1 from public.worker_private_bank_accounts ba where ba.worker_id = v_worker_id and ba.company_id = v_company_id))`);
 await db.exec(attention);
 const install=await fs.readFile(new URL('../docs/candidates/worker_document_exemption_20261027/install.sql.review-only',import.meta.url),'utf8');
 await db.exec(install);
 await assert.rejects(db.exec(install),e=>e.code==='55000');await db.exec('rollback');
 await db.query("insert into public.company_members values($1,$3,'owner'),($1,$4,'manager'),($1,$5,'worker'),($1,$6,'viewer'),($2,$7,'admin')",[company,other,owner,manager,employee,another,foreign]);
 await db.query("insert into public.workers values($1,$2,$3,'active'),($4,$2,$5,'active')",[worker,company,employee,worker2,another]);
 await db.query("insert into public.document_requirements values($1,$2,'本人書類',true,true,1)",[requirement,company]);
 await db.query("insert into public.worker_document_statuses values($1,$2,$3,$4,'submitted','saved/original.pdf')",[id(20),company,worker2,requirement]);
 const retained=(await db.query('select to_jsonb(s) row from public.worker_document_statuses s')).rows;
 for(const actor of [owner,manager,employee,another,foreign]) {
  await db.query('insert into auth.users(id) values($1)',[actor]);
  await db.query('insert into auth.sessions values($1,$2,null)',[id(Number(actor.slice(-12))+100),actor]);
 }
 async function actor(user,role='authenticated') {
  await db.exec('reset role');await db.query("select set_config('test.uid',$1,false),set_config('test.sid',$2,false)",[user,user?id(Number(user.slice(-12))+100):'']);await db.exec(`set role ${role}`);
 }
 const call=async(action,data)=>(await db.query('select public.worker_document_exemption($1,$2::jsonb) result',[action,JSON.stringify(data)])).rows[0].result;
 const set=(version,active=true,overrides={})=>call('set',{company_id:company,worker_id:worker,requirement_id:requirement,active,expected_version:version,reason:'本人の事情を管理者が確認',...overrides});
 await actor(owner);assert.equal((await call('list',{company_id:company})).can_manage,false);
 await assert.rejects(set(0),e=>e.code==='42501');
 await db.exec('reset role;update private.worker_document_exemption_settings set enabled=true');
 await actor(owner);assert.equal((await set(0)).item.version,1);
 await assert.rejects(set(0),e=>e.code==='40001');
 await assert.rejects(set(1,true),e=>e.code==='22023');
 await assert.rejects(set(1,false,{reason:'  '}),e=>e.code==='22023');
 await assert.rejects(set(1,false,{worker_id:worker2}),e=>e.code==='40001');
 await assert.rejects(set(1,false,{company_id:other}),e=>e.code==='42501');
 await assert.rejects(db.exec('delete from private.worker_document_exemptions'),e=>e.code==='42501');
 await assert.rejects(db.exec('delete from private.worker_document_exemption_events'),e=>e.code==='42501');
 await actor(employee);assert.equal((await call('list',{company_id:company})).items.length,1);
 assert.equal((await db.query('select public.current_user_required_document_attention() result')).rows[0].result.missing_count,0);
 await assert.rejects(set(1,false),e=>e.code==='42501');
 await actor(another);assert.equal((await call('list',{company_id:company})).items.length,0);
 await assert.rejects(set(1,false),e=>e.code==='42501');
 await actor(foreign);await assert.rejects(call('list',{company_id:company}),e=>e.code==='42501');
 await actor(manager);assert.equal((await set(1,false)).item.version,2);
 await actor(employee);assert.equal((await db.query('select public.current_user_required_document_attention() result')).rows[0].result.missing_count,1);
 await actor(manager);assert.equal((await set(2)).item.version,3);
 await db.exec("set test.blocked='yes'");await assert.rejects(set(3,false),e=>e.code==='42501');await db.exec("set test.blocked='no'");
 await db.exec('reset role');await db.query("update auth.sessions set not_after=now()-interval '1 second' where user_id=$1",[manager]);
 await actor(manager);await assert.rejects(call('list',{company_id:company}),e=>e.code==='42501');
 await actor('', 'anon');await assert.rejects(call('list',{company_id:company}),e=>e.code==='42501');
 await db.exec('reset role');assert.deepEqual((await db.query('select to_jsonb(s) row from public.worker_document_statuses s')).rows,retained);
 assert.equal((await db.query('select count(*)::int n from private.worker_document_exemption_events')).rows[0].n,3);
 await db.exec('update private.worker_document_exemption_settings set enabled=false');
 await actor(owner);await assert.rejects(set(3,false),e=>e.code==='42501');
 assert.equal((await call('list',{company_id:company})).items[0].active,true);
 assert.equal((await call('list',{company_id:company})).can_manage,false);
 await db.exec('reset role');
 assert.equal((await db.query("select count(*)::int n from pg_policies where schemaname='private' and tablename like 'worker_document_exemption%'")).rows[0].n,0);
 console.log('PASS individual exemption: owner/manager, same-worker read, other-company/viewer/anon/expired/blocked rejection, stale CAS, revoke restores attention, submitted/photo unchanged, audit append and direct denial');
} finally {await db.close();}
