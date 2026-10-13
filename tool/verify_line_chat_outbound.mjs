import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import {pathToFileURL} from 'node:url';
let db,pg;
if(process.env.SKO_LINE_OUTBOUND_TEST_DB_URL){
 const url=new URL(process.env.SKO_LINE_OUTBOUND_TEST_DB_URL);
 assert.ok(['localhost','127.0.0.1'].includes(url.hostname)&&url.pathname==='/sko_line_outbound','Disposable local test database only');
 pg=await import(pathToFileURL(process.argv[2]).href);const client=new pg.default.Client({connectionString:url.href});await client.connect();
 db={exec:s=>client.query(s),query:async(s,p)=>{const r=await client.query(s,p);for(const row of r.rows)if('n' in row)row.n=Number(row.n);return r;},close:()=>client.end()};
}else{const {PGlite}=await import(pathToFileURL(process.argv[2]).href);db=new PGlite();}
const u='00000000-0000-0000-0000-000000000001',other='00000000-0000-0000-0000-000000000002',company='00000000-0000-0000-0000-000000000011',group='00000000-0000-0000-0000-000000000021',secondary='00000000-0000-0000-0000-000000000022';
await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;create schema private;
create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.actor',true),'')::uuid$$;
create table auth.users(id uuid primary key);create table companies(id uuid primary key,name text);
create table communication_groups(id uuid primary key,company_id uuid,group_type text,participants_only boolean,archived_at timestamptz);
create table communication_group_members(group_id uuid,user_id uuid);
create table private.account_deletion_access_restrictions(user_id uuid);
create table line_group_bindings(id uuid primary key default gen_random_uuid(),company_id uuid,communication_group_id uuid,line_group_id text,status text);
create table private.line_joined_groups(id uuid primary key default gen_random_uuid(),line_group_id text,joined boolean);
create table private.line_chat_source_links(group_id uuid,company_id uuid,directory_id uuid);
create table chat_messages(id uuid primary key default gen_random_uuid(),company_id uuid,communication_group_id uuid,sender_user_id uuid,origin text,body text,sender_display_name text);
insert into auth.users values('${u}'),('${other}');insert into companies values('${company}','Registered company');
insert into communication_groups values('${group}','${company}','company',true,null),('${secondary}','${company}','company',true,null);
insert into communication_group_members values('${group}','${u}'),('${secondary}','${u}');
insert into line_group_bindings(company_id,communication_group_id,line_group_id,status) values('${company}','${group}','Csynthetic','active');
insert into private.line_joined_groups(line_group_id,joined) values('Csynthetic',true);
insert into chat_messages(company_id,communication_group_id,sender_user_id,origin,body,sender_display_name) values('${company}','${group}','${u}','sk_works','old history','Stored sender');
set test.actor='${u}';`);
await db.exec(await readFile(new URL('../supabase/migrations/20261013204634_line_chat_outbound.sql',import.meta.url),'utf8'));
assert.equal((await db.query('select count(*) n from private.line_chat_outbox')).rows[0].n,0);
const q=(s,p=[])=>db.query(s,p);const role=async r=>db.exec(`set role ${r}`);const post=async(origin='sk_works',body='new text',target=group,sender=u)=>{await role('postgres');return (await q('insert into chat_messages(company_id,communication_group_id,sender_user_id,origin,body,sender_display_name) values($1,$2,$3,$4,$5,$6) returning id',[company,target,sender,origin,body,'😀'.repeat(12)])).rows[0].id;};
const prep=async id=>{await role('authenticated');return (await q('select public.prepare_line_chat_dispatch($1) v',[id])).rows[0].v;};
const claim=async ticket=>{await role('service_role');return (await q('select public.claim_line_chat_dispatch($1,$2) v',[ticket,u])).rows[0].v;};
const finish=async(c,state)=>{await role('service_role');return (await q('select public.finish_line_chat_dispatch($1,$2,$3) v',[c.outbox_id,c.lease_id,state])).rows[0].v;};
const id=await post();let p=await prep(id);const c=await claim(p.ticket);assert.equal(c.state,'claimed');assert.equal(c.body,'new text');assert.equal(c.sender_name,'😀'.repeat(5)+' from SKO');assert.ok(c.sender_name.length<=20);
await assert.rejects(claim(p.ticket));await role('service_role');await assert.rejects(q('select public.claim_line_chat_dispatch($1,$2)',[p.ticket,other]));assert.equal(await finish(c,'unknown'),true);
p=await prep(id);assert.equal((await claim(p.ticket)).state,'busy');
await role('postgres');await q("update private.line_chat_outbox set next_attempt_at=now()-interval '1 second' where message_id=$1",[id]);
await role('authenticated');await q("select public.line_chat_sender_preferences($1,'nickname','New name')",[group]);
p=await prep(id);const retry=await claim(p.ticket);assert.equal(retry.retry_key,c.retry_key);assert.equal(retry.sender_name,c.sender_name);assert.equal(retry.body,c.body);assert.equal(await finish(c,'accepted'),false);assert.equal(await finish(retry,'accepted'),true);assert.equal((await prep(id)).state,'accepted');
let n=await post();await role('postgres');await q("set test.actor='"+other+"'");await assert.rejects(prep(n));await role('postgres');await q("set test.actor='"+u+"'");
p=await prep(n);await role('postgres');await q("insert into private.account_deletion_access_restrictions values($1)",[u]);await assert.rejects(claim(p.ticket));await role('postgres');await q('delete from private.account_deletion_access_restrictions');
p=await prep(n);await role('postgres');await q("update line_group_bindings set status='disabled'");await assert.rejects(claim(p.ticket));await role('postgres');await q("update line_group_bindings set status='active'");
await role('postgres');const before=(await q('select count(*) n from private.line_chat_outbox')).rows[0].n;await post('line');await post('import');await post('sk_works','x',group,other);await post('sk_works','😀'.repeat(2501));assert.equal((await q('select count(*) n from private.line_chat_outbox')).rows[0].n,before);
await role('authenticated');await q("select public.line_chat_sender_preferences($1,'company')",[group]);n=await post();p=await prep(n);const companyClaim=await claim(p.ticket);assert.equal(companyClaim.sender_name,'Registered  from SKO');await finish(companyClaim,'rejected');assert.equal((await prep(n)).state,'rejected');
await role('postgres');await q('insert into private.line_chat_source_links select $1,$2,id from private.line_joined_groups',[secondary,company]);n=await post('sk_works','secondary text',secondary);p=await prep(n);assert.equal((await claim(p.ticket)).to,'Csynthetic');
await role('postgres');await q("insert into line_group_bindings(company_id,communication_group_id,line_group_id,status) values($1,null,'Csecond','active')",[company]);await q("insert into private.line_joined_groups(line_group_id,joined) values('Csecond',true)");await q("insert into private.line_chat_source_links select $1,$2,id from private.line_joined_groups where line_group_id='Csecond'",[secondary,company]);n=await post('sk_works','ambiguous',secondary);assert.equal((await prep(n)).state,'ambiguous');
n=await post();p=await prep(n);const exp=await claim(p.ticket);await role('postgres');await q("update private.line_chat_outbox set first_attempt_at=now()-interval '24 hours',lease_until=now()-interval '1 second' where id=$1",[exp.outbox_id]);p=await prep(n);assert.equal((await claim(p.ticket)).state,'expired');
await role('postgres');for(const r of ['anon','authenticated'])for(const fn of ['public.claim_line_chat_dispatch(uuid,uuid)','public.finish_line_chat_dispatch(uuid,uuid,text)'])assert.equal((await q('select has_function_privilege($1,$2,\'execute\') v',[r,fn])).rows[0].v,false);
for(const r of ['anon','authenticated','service_role'])assert.equal((await q("select has_table_privilege($1,'private.line_chat_outbox','select') v",[r])).rows[0].v,false);
if(pg){
 await role('postgres');const raceMessage=await post();const ticket=(await prep(raceMessage)).ticket;
 const a=new pg.default.Client({connectionString:process.env.SKO_LINE_OUTBOUND_TEST_DB_URL}),b=new pg.default.Client({connectionString:process.env.SKO_LINE_OUTBOUND_TEST_DB_URL});await a.connect();await b.connect();
 try{
  await a.query('begin');await a.query('set role service_role');const claimed=(await a.query('select public.claim_line_chat_dispatch($1,$2) v',[ticket,u])).rows[0].v;
  await b.query('begin');await b.query('set role service_role');const pid=(await b.query('select pg_backend_pid() p')).rows[0].p;
  const second=b.query('select public.claim_line_chat_dispatch($1,$2) v',[ticket,u]).then(()=>({ok:true}),e=>({error:e}));
  await role('postgres');let locked=false;for(let i=0;i<50;i++){const row=(await q('select wait_event_type from pg_stat_activity where pid=$1',[pid])).rows[0];if(row?.wait_event_type==='Lock'){locked=true;break;}await new Promise(r=>setTimeout(r,20));}
  assert.equal(locked,true,'Concurrent dispatch must wait on persisted outbox lock');await a.query('commit');assert.equal(claimed.state,'claimed');assert.ok((await second).error);await b.query('rollback');
  assert.equal((await q('select attempts from private.line_chat_outbox where message_id=$1',[raceMessage])).rows[0].attempts,1);
 }finally{await a.end();await b.end();}
}
await role('postgres');await q('delete from auth.users where id=$1',[u]);assert.equal((await q('select count(*) n from private.line_chat_outbox')).rows[0].n,0);assert.equal((await q('select count(*) n from private.line_chat_sender_preferences')).rows[0].n,0);
await db.close();console.log('Outbound real SQL: new-only snapshots, UTF16 names, own actor, account restriction, canonical/unique sources, ambiguous denial, lease/retry/expired, preference snapshot and explicit role ACL passed.');
