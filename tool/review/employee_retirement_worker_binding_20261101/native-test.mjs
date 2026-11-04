import assert from 'node:assert/strict';
import fs from 'node:fs';
import {spawnSync} from 'node:child_process';

export function validateFixtureEnvironment(env) {
  assert.equal(env.PGDATABASE,'retirement_fixture','isolated database required');
  assert.ok(['127.0.0.1','localhost'].includes(env.PGHOST),'loopback required');
  assert.equal(env.PGUSER,'postgres','synthetic owner required');
  assert.match(env.PGPORT??'',/^\d{1,5}$/);
  assert.match(env.SKO_FIXTURE_SERVER_ADDR??'',/^(?:127\.0\.0\.1|::1|10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+|172\.(?:1[6-9]|2\d|3[01])\.\d+\.\d+)$/,'inspected fixture address required');
  for(const key of ['DATABASE_URL','SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY','SERVICE_ROLE_KEY','PGSERVICE','PGSERVICEFILE','PGHOSTADDR','PGOPTIONS']) {
    assert.ok(!env[key],`refusing ${key}`);
  }
}

if(process.argv.includes('--environment-faults')) {
  const safe={PGDATABASE:'retirement_fixture',PGHOST:'127.0.0.1',PGUSER:'postgres',PGPORT:'5432',SKO_FIXTURE_SERVER_ADDR:'127.0.0.1'};
  validateFixtureEnvironment(safe);
  for(const extra of [
    {PGDATABASE:'postgres'},{PGDATABASE:'postgresql://fixture.invalid/postgres'},
    {PGHOST:'db.fixture.invalid'},{PGHOST:'127.0.0.1,db.fixture.invalid'},
    {PGUSER:'service_role'},{PGPORT:'5432 --host=remote'},
    {DATABASE_URL:'postgres://fixture.invalid/postgres'},
    {SUPABASE_URL:'https://fixture.invalid'},{SUPABASE_SERVICE_ROLE_KEY:'synthetic'},
    {PGSERVICE:'production'},{PGHOSTADDR:'192.0.2.1'},{PGOPTIONS:'-c role=other'},
    {SKO_FIXTURE_SERVER_ADDR:undefined},{SKO_FIXTURE_SERVER_ADDR:'203.0.113.1'},{SKO_FIXTURE_SERVER_ADDR:'localhost'},
  ]) assert.throws(()=>validateFixtureEnvironment({...safe,...extra}));
  console.log('fixture environment rejection: 15 negative cases passed; no connection attempted');
} else {
  validateFixtureEnvironment(process.env);
  const dir=new URL('./',import.meta.url);
  // pg_get_functiondef has no statement delimiter; preserve its bytes on disk.
  const baseline=fs.readFileSync(new URL('production-observed-baseline.sql',dir),'utf8')+';';
  const repair=fs.readFileSync(new URL('repair.sql.review-only',dir),'utf8');
  let checks=0;
  function sql(query,{failure=false}={}) {
    const r=spawnSync('psql',['-XAtq','-v','ON_ERROR_STOP=1','-h',process.env.PGHOST,'-p',process.env.PGPORT,'-U','postgres','-d','retirement_fixture'],
      {input:query,encoding:'utf8',env:process.env});
    if(failure) {assert.notEqual(r.status,0);checks++;return r;}
    assert.equal(r.status,0,r.stderr);return r.stdout.trim();
  }
  const address=JSON.parse(sql("select json_build_object('db',current_database(),'addr',host(inet_server_addr()));") );
  assert.equal(address.db,'retirement_fixture');assert.equal(address.addr,process.env.SKO_FIXTURE_SERVER_ADDR);checks++;
  sql(`create schema auth;
    create role authenticated;create role service_role;create role anon;
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    create function auth.jwt() returns jsonb language sql stable as $$select '{}'::jsonb$$;
    create table public.company_members(company_id uuid,user_id uuid);
    create table public.user_profiles(user_id uuid,display_name text,phone text);
    create table public.workers(id uuid primary key default gen_random_uuid(),company_id uuid,user_id uuid,affiliation text,name text,phone text,status text,
      unique(company_id,user_id));
    create table public.fixture_preserved_originals(id integer primary key,payload jsonb);
    insert into public.fixture_preserved_originals values(1,'{"kind":"payroll-signature-qualification-synthetic-original"}');
    ${baseline}
    revoke all on function public.ensure_current_user_worker() from public,anon;
    grant execute on function public.ensure_current_user_worker() to authenticated;
    grant execute on function public.ensure_current_user_worker() to service_role;`);
  const source=()=>sql("select md5(pg_get_functiondef('public.ensure_current_user_worker()'::regprocedure));");
  const protection=()=>sql("select json_build_object('oid',oid,'owner',proowner,'acl',proacl::text,'definer',prosecdef,'config',proconfig)::text from pg_proc where oid='public.ensure_current_user_worker()'::regprocedure;");
  const protectedBefore=protection();
  const originalBefore=sql('select md5(string_agg(payload::text,\',\' order by id)) from public.fixture_preserved_originals');
  assert.equal(source(),'10565c7d5a53e45f37a4c6be0f58b538');checks++;
  const user='10000000-0000-0000-0000-000000000001',company='20000000-0000-0000-0000-000000000001',worker='30000000-0000-0000-0000-000000000001';
  const claims=`set request.jwt.claim.sub='${user}';`;
  sql(`insert into public.company_members values('${company}','${user}');
    insert into public.user_profiles values('${user}','Synthetic active profile','07000000000');
    insert into public.workers(id,company_id,user_id,affiliation,name,phone,status) values('${worker}','${company}','${user}','employee','Existing','old','inactive');`);
  assert.equal(sql(claims+'select public.ensure_current_user_worker();'),worker);
  assert.equal(sql(`select status from public.workers where id='${worker}'`),'active');checks++;
  sql(`update public.workers set status='inactive' where id='${worker}';`);
  sql(repair);
  assert.equal(protection(),protectedBefore);checks++;
  assert.notEqual(source(),'10565c7d5a53e45f37a4c6be0f58b538');checks++;
  for(const status of ['inactive','active','unknown',null]) {
    sql(`update public.workers set status=${status===null?'null':"'"+status+"'"} where id='${worker}';`);
    assert.equal(sql(claims+'select public.ensure_current_user_worker();'),worker);
    assert.equal(sql(`select coalesce(status,'<NULL>') from public.workers where id='${worker}'`),status??'<NULL>');checks++;
  }
  const newUser='10000000-0000-0000-0000-000000000002';
  sql(`insert into public.company_members values('${company}','${newUser}');`);
  const created=sql(`set request.jwt.claim.sub='${newUser}';select public.ensure_current_user_worker();`);
  assert.match(created,/^[0-9a-f-]{36}$/);assert.equal(sql(`select status from public.workers where id='${created}'`),'active');checks++;
  sql("set request.jwt.claim.sub='';select public.ensure_current_user_worker();",{failure:true});
  const denied='10000000-0000-0000-0000-000000000003';
  sql(`set request.jwt.claim.sub='${denied}';select public.ensure_current_user_worker();`,{failure:true});
  assert.equal(sql('select md5(string_agg(payload::text,\',\' order by id)) from public.fixture_preserved_originals'),originalBefore);checks++;
  const fixedSource=source();
  sql(repair,{failure:true});assert.equal(source(),fixedSource);checks++;
  // Each unknown protection drift refuses before body replacement.
  sql(baseline);sql('grant execute on function public.ensure_current_user_worker() to anon;');
  sql(repair,{failure:true});assert.equal(source(),'10565c7d5a53e45f37a4c6be0f58b538');checks++;
  sql('revoke execute on function public.ensure_current_user_worker() from anon;');
  sql("alter function public.ensure_current_user_worker() set search_path=public;");
  sql(repair,{failure:true});assert.equal(source()===fixedSource,false);checks++;
  console.log(`Native retirement binding: ${checks} checks passed; production deployment/drain not proven`);
}
