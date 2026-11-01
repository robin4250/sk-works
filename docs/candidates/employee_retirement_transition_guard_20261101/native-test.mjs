import assert from 'node:assert/strict';
import fs from 'node:fs';
import crypto from 'node:crypto';
import {spawn,spawnSync} from 'node:child_process';

const dir=new URL('./',import.meta.url), root=new URL('../../../',dir);
const safe={PGHOST:'127.0.0.1',PGPORT:'5432',PGUSER:'postgres',PGDATABASE:'retirement_fixture',SKO_FIXTURE_SERVER_ADDR:'127.0.0.1'};
function validate(e){
  assert.equal(e.PGDATABASE,'retirement_fixture');assert.equal(e.PGUSER,'postgres');
  assert.ok(['127.0.0.1','localhost'].includes(e.PGHOST));assert.match(e.PGPORT??'',/^\d{1,5}$/);
  assert.match(e.SKO_FIXTURE_SERVER_ADDR??'',/^(?:127\.0\.0\.1|::1|10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+|172\.(?:1[6-9]|2\d|3[01])\.\d+\.\d+)$/);
  for(const k of ['DATABASE_URL','SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY','SERVICE_ROLE_KEY','PGSERVICE','PGSERVICEFILE','PGHOSTADDR','PGOPTIONS'])assert.ok(!e[k],k);
}
if(process.argv.includes('--environment-faults')){
  validate(safe);let n=0;
  for(const v of [{PGDATABASE:'postgres'},{PGHOST:'db.invalid'},{PGHOST:'127.0.0.1,remote'}, {PGUSER:'service_role'},{PGPORT:'5432 --host=remote'}, {SKO_FIXTURE_SERVER_ADDR:'203.0.113.1'},...['DATABASE_URL','SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY','SERVICE_ROLE_KEY','PGSERVICE','PGSERVICEFILE','PGHOSTADDR','PGOPTIONS'].map(k=>({[k]:'refuse'}))]){assert.throws(()=>validate({...safe,...v}));n++;}
  console.log(`environment: ${n} denials; no connection`);process.exit(0);
}
validate(process.env);
const args=['-XAtq','-v','ON_ERROR_STOP=1','-h',process.env.PGHOST,'-p',process.env.PGPORT,'-U','postgres','-d','retirement_fixture'];
let checks=0;
function sql(q,{deny=false}={}){
  const r=spawnSync('psql',args,{input:q,encoding:'utf8',env:process.env,timeout:20000});
  if(deny){assert.notEqual(r.status,0,r.stdout);assert.match(r.stderr,/explicit reinstatement is required/);checks++;return r;}
  assert.equal(r.status,0,r.stderr);return r.stdout.trim();
}
function pinned(path,sha){const b=fs.readFileSync(new URL(path,root));assert.equal(crypto.createHash('sha256').update(b).digest('hex'),sha);return b.toString();}
const baseline=pinned('tool/review/employee_retirement_worker_binding_20261101/production-observed-baseline.sql','e70287a0ff7cfe89e91af2e243dd4c4a38bedabe6b08c37d23a9c4731c94b824');
const repair=pinned('tool/review/employee_retirement_worker_binding_20261101/repair.sql.review-only','4e621d5d92cdb66ffade23dec719bf602b3d12235f80ad37502c2669d01af426');
const migration=pinned('supabase/migrations/20260922024000_add_invite_role_and_approver_selection.sql','8ad24f44c759f28c7396175ab56002f2732f86386917fc1045f1579d1d94dace');
const invite=migration.slice(migration.indexOf('create or replace function public.approve_employee_onboarding('),migration.indexOf('create or replace function public.pending_employee_onboarding_review_rows()'));
assert.ok(invite.includes("status = 'active'"));
const address=JSON.parse(sql("select json_build_object('db',current_database(),'addr',host(inet_server_addr()));"));
assert.equal(address.db,'retirement_fixture');assert.equal(address.addr,process.env.SKO_FIXTURE_SERVER_ADDR);checks++;
sql(`create schema auth;create schema private;create role authenticated;create role anon;create role service_role;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create function auth.jwt() returns jsonb language sql stable as $$select '{}'::jsonb$$;
create table public.company_members(company_id uuid,user_id uuid,role text,primary key(company_id,user_id));
create table public.user_profiles(user_id uuid primary key,display_name text,phone text,updated_at timestamptz);
create table public.workers(id uuid primary key default gen_random_uuid(),company_id uuid,user_id uuid,affiliation text,name text,phone text,status text,role text,updated_at timestamptz,unique(company_id,user_id));
create table public.company_approval_assignees(company_id uuid,user_id uuid,created_by uuid,primary key(company_id,user_id));
create table public.employee_registration_invites(id uuid primary key,company_id uuid,worker_id uuid,auth_user_id uuid,status text,requested_role text,requested_approval_assignee boolean,replace_approval_assignee_user_id uuid,name text,phone_e164 text,approved_by uuid,approved_at timestamptz);
create table public.app_notifications(company_id uuid,action_key text,action_id uuid,read_at timestamptz);
create function private.enqueue_notification(uuid,uuid,text,text,text,text,uuid) returns void language plpgsql as $$begin return;end;$$;
create table public.fixture_originals(id int primary key,payload jsonb);insert into public.fixture_originals values(1,'{"qualification":"original-preserved"}');
${baseline};revoke all on function public.ensure_current_user_worker() from public,anon;grant execute on function public.ensure_current_user_worker() to authenticated,service_role;
${invite}
grant usage on schema public,auth,private to authenticated;
grant select,insert,update on public.workers to authenticated;`);
const c='20000000-0000-0000-0000-000000000001', u='10000000-0000-0000-0000-000000000001', admin='10000000-0000-0000-0000-000000000002', w='30000000-0000-0000-0000-000000000001', iv='40000000-0000-0000-0000-000000000001';
const actor=(id=u)=>`set role authenticated;set request.jwt.claim.sub='${id}';`;
sql(`insert into company_members values('${c}','${u}','viewer'),('${c}','${admin}','admin');insert into user_profiles(user_id,display_name,phone)values('${u}','profile','07000000000');insert into workers(id,company_id,user_id,affiliation,name,status)values('${w}','${c}','${u}','employee','retired','inactive');`);
const originals=sql('select md5(payload::text) from fixture_originals');
sql(fs.readFileSync(new URL('candidate.sql.review-only',dir),'utf8'));
sql(actor()+'select public.ensure_current_user_worker();',{deny:true});
assert.equal(sql(`select status from workers where id='${w}'`),'inactive');checks++;
// Preserve exact legacy approval source; fixture dependencies do not assert hosted authentication.
sql(`delete from company_members where user_id='${u}';insert into employee_registration_invites values('${iv}','${c}','${w}','${u}','approval_pending','manager',false,null,'invite','07000000000',null,null);`);
sql(actor(admin)+`select public.approve_employee_onboarding('${iv}');`,{deny:true});
assert.equal(sql(`select count(*) from company_members where user_id='${u}'`),'0');
assert.equal(sql(`select status from employee_registration_invites where id='${iv}'`),'approval_pending');checks++;
sql(`insert into company_members values('${c}','${u}','viewer');`);
sql(repair);
assert.equal(sql(actor()+'select public.ensure_current_user_worker();'),w);assert.equal(sql(`select status from workers where id='${w}'`),'inactive');checks++;
assert.equal(sql('select md5(payload::text) from fixture_originals'),originals);checks++;
for(const old of ["'inactive'","'unknown'",'null']){
  sql(`update workers set status=${old} where id='${w}';`);
  sql(actor()+`update workers set status='active' where id='${w}';`,{deny:true});
}
sql(`insert into workers(company_id,name,status)values('${c}','new-active','active');update workers set name='profile-change' where name='new-active';`);checks++;
sql(actor()+`update workers set name='history-profile',status='inactive' where id='${w}';`);checks++;
sql(`create function private.fixture_before_status()returns trigger language plpgsql as $$begin if NEW.name='force-active' then NEW.status='active';end if;return NEW;end;$$;create trigger fixture_before_status before update on workers for each row execute function private.fixture_before_status();`);
sql(actor()+`update workers set name='force-active' where id='${w}';`,{deny:true});
sql(actor()+`insert into workers(id,company_id,status)values('${w}','${c}','active')on conflict(id)do update set status=excluded.status;`,{deny:true});
sql('drop trigger fixture_before_status on workers;drop function private.fixture_before_status();');
// Guard exists before this race. This is not a guard-install/admission-drain proof.
sql(`update workers set status='inactive' where id='${w}';`);
sql(actor()+`select set_config('private.allow_reinstatement','true',false);update workers set status='active' where id='${w}';`,{deny:true});
function child(){const p=spawn('psql',args,{env:process.env});let out='',err='';p.stdout.on('data',b=>out+=b);p.stderr.on('data',b=>err+=b);const done=new Promise(resolve=>p.on('close',code=>resolve({code,out,err})));return {p,done,get out(){return out;}};}
const a=child();let b;try {a.p.stdin.write(`begin;set application_name='retirement_guard_locker';update workers set status='inactive' where id='${w}';\\echo LOCKED\n`);
const deadline=Date.now()+12000;
while(!a.out.includes('LOCKED')){assert.ok(Date.now()<deadline,'locker did not acknowledge');await new Promise(r=>setTimeout(r,25));}
// Temporarily use exact old body again so the existing-frame update attempts reactivation.
sql(baseline+';');
b=child();b.p.stdin.end(actor()+`set application_name='retirement_guard_old_ensure';select public.ensure_current_user_worker();`);
let blocked=false;
while(Date.now()<deadline){if(sql("select exists(select 1 from pg_stat_activity b join pg_stat_activity a on a.pid=any(pg_blocking_pids(b.pid))where b.application_name='retirement_guard_old_ensure' and a.application_name='retirement_guard_locker');")==='t'){blocked=true;break;}await new Promise(r=>setTimeout(r,25));}
assert.ok(blocked,'real old ensure wait not observed');
a.p.stdin.end('commit;');const [ar,br]=await Promise.all([a.done,b.done]);assert.equal(ar.code,0,ar.err);assert.notEqual(br.code,0);assert.match(br.err,/explicit reinstatement is required/);assert.equal(sql(`select status from workers where id='${w}'`),'inactive');checks++;
assert.equal(sql('select md5(payload::text) from fixture_originals'),originals);checks++;
} finally {for(const x of [a,b]){if(x&&!x.p.killed){x.p.stdin.destroy();x.p.kill('SIGTERM');}}}
console.log(`Native transition guard: ${checks} checks passed; old ensure wait observed; production admission/install drain unproven; deployable:false`);
