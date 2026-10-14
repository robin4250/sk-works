import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const {PGlite}=await import(process.argv[2]);
const db=new PGlite();
try {
await db.exec(`create role anon;create role authenticated;create role service_role;
create schema auth;create schema private;
create table company_members(company_id uuid,user_id uuid);
create table private.master_admin_audit_log(id uuid primary key,actor_user_id uuid,target_user_id uuid,action text,details jsonb,created_at timestamptz);
create table auth.audit_log_entries(id uuid primary key,payload json,created_at timestamptz,ip_address text);
create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
create function private.security_incident_actor_company() returns uuid language plpgsql security definer set search_path='' as $$declare c uuid;n int;begin
if auth.uid() is null or current_setting('test.master',true) is distinct from 'true' or current_setting('test.blocked',true)='true' then raise exception 'unavailable';end if;
select count(*),(array_agg(company_id))[1] into n,c from public.company_members where user_id=auth.uid();if n<>1 then raise exception 'unavailable';end if;return c;end$$;
grant usage on schema public,private,auth to authenticated,anon;
revoke all on function private.security_incident_actor_company() from public,anon,authenticated,service_role;`);
const uid=crypto.randomUUID(),other=crypto.randomUUID(),company=crypto.randomUUID(),othercompany=crypto.randomUUID();
await db.query('insert into company_members values($1,$2),($1,$3)',[company,uid,other]);
const now=new Date().toISOString();
await db.query('insert into private.master_admin_audit_log values($1,$2,$2,$3,$4::jsonb,$5),($6,$7,$7,$3,$4::jsonb,$5),($8,$2,$7,$3,$4::jsonb,$5),($9,$2,$2,$10,$4::jsonb,$5)',[crypto.randomUUID(),uid,'master_device_bootstrap',JSON.stringify({email:'forbidden@example.invalid',ip:'127.1.2.3',secret:'forbidden-secret',device_name:'forbidden-device'}),now,crypto.randomUUID(),other,crypto.randomUUID(),crypto.randomUUID(),'unknown-private-action']);
await db.query('insert into auth.audit_log_entries values($1,$2::json,$3,$4),($5,$6::json,$3,$4),($7,$8::json,$3,$4),($9,$10::json,$3,$4)',[
crypto.randomUUID(),JSON.stringify({actor_id:uid,action:'login',actor_username:'forbidden@example.invalid',metadata:{secret:'forbidden-secret'}}),now,'127.1.2.3',
crypto.randomUUID(),JSON.stringify({actor_id:other,action:'login'}),
crypto.randomUUID(),JSON.stringify({actor_id:uid,action:'unknown-private-action'}),
crypto.randomUUID(),JSON.stringify({action:'login',actor_username:'forbidden@example.invalid'})]);
await db.exec(await readFile(new URL('../../supabase/migrations/20261014061009_master_self_operation_audit.sql',import.meta.url),'utf8'));
const read=async(name)=> (await db.query(`select public.${name}() v`)).rows[0].v;
const names=['master_self_operation_audit','master_self_auth_audit'];
await db.exec(`select set_config('test.uid','${uid}',false),set_config('test.master','true',false);set role authenticated`);
for(const [i,name] of names.entries()){
 const result=await read(name);
 assert.equal(result.source_provenance,i?'supabase_auth_database_audit':'server_master_operation_audit');
 assert.equal(result.scope,'self_master_account');assert.equal(result.events.length,1);
 assert.deepEqual(Object.keys(result.events[0]).sort(),['action','at']);
 assert.ok(!JSON.stringify(result).includes(uid));assert.ok(!JSON.stringify(result).includes('forbidden'));assert.ok(!JSON.stringify(result).includes('127.1.2.3'));
}

const fixed=await read(names[1]);
await db.exec('reset role');
await db.query("insert into auth.audit_log_entries values(gen_random_uuid(),json_build_object('actor_id',$1::text,'action','login'),clock_timestamp()+interval '1 millisecond',null)",[uid]);
await new Promise(resolve=>setTimeout(resolve,10));
await db.exec('set role authenticated');
assert.deepEqual((await db.query('select public.master_self_auth_audit($1::timestamptz) v',[fixed.cutoff])).rows[0].v,fixed);
assert.equal((await read(names[1])).events.length,2);
for (const cutoff of ['infinity','-infinity',new Date(Date.now()+3600000).toISOString(),new Date(Date.now()-8*86400000).toISOString()]) {
 for(const name of names) await assert.rejects(db.query(`select public.${name}($1::timestamptz)`,[cutoff]));
}

await assert.rejects(db.query('select * from private.master_admin_audit_log'));
await assert.rejects(db.query('select * from auth.audit_log_entries'));
await assert.rejects(db.query("insert into auth.audit_log_entries(id,payload)values(gen_random_uuid(),'{}')"));
await db.exec(`select set_config('test.master','false',false)`);for(const n of names)await assert.rejects(read(n));
await db.exec(`select set_config('test.master','true',false),set_config('test.blocked','true',false)`);for(const n of names)await assert.rejects(read(n));
await db.exec(`select set_config('test.blocked','false',false),set_config('test.uid','',false)`);for(const n of names)await assert.rejects(read(n));
await db.exec(`select set_config('test.uid','${other}',false)`);for(const n of names)assert.equal((await read(n)).events.length,1);
await db.exec(`reset role;insert into company_members values('${othercompany}','${other}');set role authenticated`);for(const n of names)await assert.rejects(read(n));
await db.exec(`reset role;delete from company_members where user_id='${other}';set role authenticated`);for(const n of names)await assert.rejects(read(n));
await db.exec('reset role;set role anon');for(const n of names)await assert.rejects(read(n));
await db.exec('reset role;set role service_role');for(const n of names)await assert.rejects(read(n));
await db.exec(`reset role;select set_config('test.uid','${uid}',false)`);
await db.query("insert into auth.audit_log_entries select gen_random_uuid(),json_build_object('actor_id',$1::text,'action','logout'),now()-make_interval(secs=>i),'forbidden' from generate_series(1,120)i",[uid]);
await db.exec('set role authenticated');const bounded=await read(names[1]);assert.equal(bounded.events.length,100);
for(let i=1;i<bounded.events.length;i++)assert.ok(bounded.events[i].at<=bounded.events[i-1].at);
console.log('Master self audit SQL: source separation, allowlist, redaction, self-only scope, role/account/company denial, direct table denial, limit and ordering passed.');
} finally {await db.close();}
