import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
const pg = await import(process.argv[2]);
const Client = pg.Client ?? pg.default.Client;
const url = process.env.SKO_WORK_CATEGORY_FIXTURE_URL;
if (!url || !url.includes('127.0.0.1')) throw Error('isolated native fixture only');
const db = new Client({connectionString:url}); await db.connect();
let checks = 0;
const company='10000000-0000-4000-8000-000000000001', other='10000000-0000-4000-8000-000000000002';
const owner='20000000-0000-4000-8000-000000000001', member='20000000-0000-4000-8000-000000000002', outsider='20000000-0000-4000-8000-000000000003';
const policy = {schema:1,night_start_minute:1320,night_end_minute:300,holiday_weekdays:[7],holiday_dates:['2026-10-26'],working_dates:['2026-11-01'],include_japanese_holidays:false};
const one = async (sql,args=[]) => (await db.query(sql,args)).rows[0];
async function reject(sql,args,code){await assert.rejects(db.query(sql,args),e=>e.code===code);checks++;}
const session='30000000-0000-4000-8000-000000000001';
async function as(actor){await db.query('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[actor,JSON.stringify({sub:actor,role:'authenticated',is_anonymous:false,session_id:actor===member?'30000000-0000-4000-8000-000000000002':actor===outsider?'30000000-0000-4000-8000-000000000003':session})]);await db.query('set role authenticated');} 
async function read(){return (await one('select public.read_company_work_category_policy($1) as v',[company])).v;}
async function save(revision,value=policy){return (await one('select public.save_company_work_category_policy($1,$2,$3) as v',[company,revision,value])).v;}
try {
 await db.query(`create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls; create schema auth; create schema private;
 create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
 create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
 create function private.account_access_allowed() returns boolean language sql stable as $$ select coalesce(nullif(current_setting('fixture.account_allowed',true),''),'true')::boolean $$;
 create function private.account_deletion_barrier_key(actor uuid) returns bigint language sql immutable as $$ select hashtextextended(actor::text,0) $$;
 create table auth.users(id uuid primary key,is_anonymous boolean,banned_until timestamptz);
 create table auth.sessions(id uuid not null,user_id uuid,not_after timestamptz);
 insert into auth.users values('${owner}',false,null),('${member}',false,null),('${outsider}',false,null);
 insert into auth.sessions values('${session}','${owner}',null),('30000000-0000-4000-8000-000000000002','${member}',null),('30000000-0000-4000-8000-000000000003','${outsider}',null);
 grant usage on schema auth to authenticated; grant execute on function auth.uid() to authenticated;
 create table public.companies(id uuid primary key); create table public.company_members(company_id uuid references public.companies(id),user_id uuid,role text);
 insert into public.companies values('${company}'),('${other}');
 insert into public.company_members values('${company}','${owner}','owner'),('${company}','${member}','worker'),('${other}','${outsider}','owner');`);
 await db.query(await fs.readFile('docs/review/company-work-category-policy/require_session.fixture.sql','utf8'));
 await db.query('revoke all on function private.require_reauthentication_session() from public,anon,authenticated,service_role');
 const source=await fs.readFile('docs/review/company-work-category-policy/company_work_category_policy.sql.review-only','utf8');
 await db.query(source);
 assert.equal((await one('select count(*)::int n from company_work_category_private.settings')).n,0);checks++;
 assert.equal((await one('select count(*)::int n from company_work_category_private.history')).n,0);checks++;
 const restore=await fs.readFile('docs/review/company-work-category-policy/restore_unused.sql.review-only','utf8');
 await db.query(restore);
 assert.equal((await one("select to_regnamespace('company_work_category_private') is null absent")).absent,true);checks++;
 await db.query(source);
 assert.equal((await one("select has_function_privilege('anon','public.read_company_work_category_policy(uuid)','execute') ok")).ok,false);checks++;
 assert.equal((await one("select has_function_privilege('anon','public.save_company_work_category_policy(uuid,integer,jsonb)','execute') ok")).ok,false);checks++;
 await as(owner); assert.deepEqual(await read(),{schema:1,actor_id:owner,company_id:company,revision:0,can_manage:true,policy:null});checks++;
 await reject('select * from company_work_category_private.settings',[],'42501');
 const first=await save(0);assert.equal(first.revision,1);assert.deepEqual(first.policy,policy);checks+=2;
 await reject('select public.save_company_work_category_policy($1,$2,$3)',[company,0,policy],'PT409');
 for(const bad of [null,{...policy,extra:true},{...policy,schema:2},{...policy,night_start_minute:1440},{...policy,night_end_minute:1320},{...policy,night_end_minute:2.5},{...policy,holiday_weekdays:[7,7]},{...policy,holiday_weekdays:[0]},{...policy,holiday_dates:['2026-02-30']},{...policy,holiday_dates:['2026-1-01']},{...policy,working_dates:['2026-10-26']},{...policy,include_japanese_holidays:'false'}]){
  await reject('select public.save_company_work_category_policy($1,$2,$3)',[company,1,bad],'22023');
 }
 await as(member);assert.equal((await read()).can_manage,false);checks++;
 await reject('select public.save_company_work_category_policy($1,$2,$3)',[company,1,policy],'42501');
 await as(outsider);await reject('select public.read_company_work_category_policy($1)',[company],'42501');
 await reject('select public.save_company_work_category_policy($1,$2,$3)',[company,1,policy],'42501');
 await as('');await reject('select public.read_company_work_category_policy($1)',[company],'42501');
 await as(owner);
 await db.query("select set_config('fixture.account_allowed','false',false)");
 await reject('select public.read_company_work_category_policy($1)',[company],'42501');
 await reject('select public.save_company_work_category_policy($1,$2,$3)',[company,1,policy],'42501');
 await db.query("select set_config('fixture.account_allowed','true',false)");
 await db.query('reset role');await db.query(`update auth.users set banned_until=clock_timestamp()+interval '1 hour' where id=$1`,[owner]);
 await as(owner);await reject('select public.save_company_work_category_policy($1,$2,$3)',[company,1,policy],'42501');
 await db.query('reset role');await db.query('update auth.users set banned_until=null,is_anonymous=true where id=$1',[owner]);
 await as(owner);await reject('select public.read_company_work_category_policy($1)',[company],'42501');
 await db.query('reset role');await db.query('update auth.users set is_anonymous=false where id=$1',[owner]);
 await db.query(`update auth.sessions set not_after=clock_timestamp()-interval '1 second' where user_id=$1`,[owner]);
 await as(owner);await reject('select public.save_company_work_category_policy($1,$2,$3)',[company,1,policy],'42501');
 await db.query('reset role');await db.query('update auth.sessions set not_after=null where user_id=$1',[owner]);
 await as(owner);
 await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({role:'authenticated',session_id:'bad'})]);
 await reject('select public.read_company_work_category_policy($1)',[company],'42501');
 await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({role:'authenticated',session_id:'30000000-0000-4000-8000-000000000002'})]);
 await reject('select public.save_company_work_category_policy($1,$2,$3)',[company,1,policy],'42501');
 await as(owner); const second=await save(1,{...policy,include_japanese_holidays:true});assert.equal(second.revision,2);checks++;
 await db.query('reset role');
 assert.equal((await one('select count(*)::int n from company_work_category_private.history')).n,2);checks++;
 // Multiple live memberships for this exact company fail closed.
 await db.query('insert into company_members values($1,$2,$3)',[company,owner,'owner']);
 await as(owner);await reject('select public.read_company_work_category_policy($1)',[company],'42501');
 await reject('select public.save_company_work_category_policy($1,$2,$3)',[company,2,policy],'42501');
 await db.query('reset role');await db.query('delete from company_members where ctid=(select max(ctid) from company_members where company_id=$1 and user_id=$2)',[company,owner]);
 // Two writers starting from the same revision cannot both succeed.
 const writers=await Promise.all([1,2].map(async()=>{const c=new Client({connectionString:url});await c.connect();await c.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[owner,JSON.stringify({role:'authenticated',is_anonymous:false,session_id:session})]);await c.query('set role authenticated');return c;}));
 try {const results=await Promise.allSettled(writers.map(c=>c.query('select public.save_company_work_category_policy($1,$2,$3)',[company,2,policy])));
 assert.equal(results.filter(r=>r.status==='fulfilled').length,1);assert.equal(results.filter(r=>r.status==='rejected'&&r.reason.code==='PT409').length,1);checks+=2;
 } finally {await Promise.all(writers.map(c=>c.end()));}
 assert.equal((await one('select count(*)::int n from company_work_category_private.history')).n,3);checks++;
 assert.equal((await one('select count(*)::int n from company_work_category_private.settings')).n,1);checks++;
 assert.equal((await one('select count(*)::int n from company_members')).n,3);checks++;
 assert.equal((await one('select count(*)::int n from companies')).n,2);checks++;
 await assert.rejects(db.query(restore), /used policy cannot be restored/);checks++;
 await db.query('rollback');
 assert.equal((await one('select count(*)::int n from company_work_category_private.history')).n,3);checks++;
 console.log(`Native PostgreSQL company policy: ${checks} checks passed; no business writer replaced.`);
} finally {await db.end();}
