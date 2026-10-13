import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
const pg=(await import(process.argv[2]??'pg')).default;
const url=new URL(process.env.SKO_SECONDARY_PROOF_FIXTURE_URL??'');
if(!['localhost','127.0.0.1','[::1]'].includes(url.hostname)||url.pathname!='/sko_secondary_proof_fixture')throw Error('Dedicated disposable loopback proof fixture only');
const a=new pg.Client({connectionString:url.href}),b=new pg.Client({connectionString:url.href});await Promise.all([a.connect(),b.connect()]);
const actor='10000000-0000-0000-0000-000000000001',other='10000000-0000-0000-0000-000000000002',session='20000000-0000-0000-0000-000000000001',second='20000000-0000-0000-0000-000000000002',foreign='20000000-0000-0000-0000-000000000003';
const context=async(client,id=actor,sid=session,role='authenticated')=>{await client.query('reset role');await client.query("select set_config('test.uid',$1,false),set_config('test.jwt',$2,false)",[id,JSON.stringify({session_id:sid,role})]);await client.query('set role '+role);};
const mint=async(password='synthetic-initial')=>(await a.query('select public.secondary_candidate_issue_with_secondary($1) v',[password])).rows[0].v;
const change=(client,ticket,password='synthetic-replacement')=>client.query('select public.secondary_candidate_change($1,$2)',[ticket,password]);
const admin=async(sql,params=[])=>{await a.query('reset role');try{return await a.query(sql,params);}finally{await context(a);}};
const rejected=async(task)=>assert.rejects(task,/proof|permission|session|restricted|password length|credential required/);
try {
 await a.query(`create extension pgcrypto;create schema auth;create schema private;create role anon;create role authenticated;create role service_role;create table auth.sessions(id uuid primary key,user_id uuid not null);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('test.uid',true),'')::uuid$$;create function auth.jwt() returns jsonb language sql stable as $$select current_setting('test.jwt',true)::jsonb$$;create table public.user_secondary_credentials(user_id uuid primary key,password_hash text not null,failed_attempts int not null default 0,locked_until timestamptz,updated_at timestamptz);alter table public.user_secondary_credentials enable row level security;revoke all on public.user_secondary_credentials from public,anon,authenticated,service_role;create table private.fixture_account_restrictions(user_id uuid primary key);revoke all on private.fixture_account_restrictions from public,anon,authenticated,service_role;insert into auth.sessions values('${session}','${actor}'),('${second}','${actor}'),('${foreign}','${other}');`);
 await a.query(await fs.readFile(new URL('../supabase/tests/fixtures/secondary_proof_before.sql',import.meta.url),'utf8'));
 await a.query(`revoke all on function public.set_secondary_password(text),public.verify_secondary_password(text) from public,anon;grant execute on function public.verify_secondary_password(text) to authenticated;`);
 await a.query(await fs.readFile(new URL('../supabase/tests/fixtures/secondary_proof_candidate.sql',import.meta.url),'utf8'));
 await context(a);await a.query("select public.secondary_candidate_initial_set('synthetic-initial')");
 await rejected(a.query("select public.secondary_candidate_initial_set('synthetic-overwrite')"));
 assert.equal(await mint('synthetic-wrong'),null);
 assert.equal((await admin('select failed_attempts from public.user_secondary_credentials')).rows[0].failed_attempts,1,'failed proof commits existing counter');
 const ticket=await mint();assert.match(ticket,/^[0-9a-f]{64}$/);
 const stored=(await admin('select token_hash,scope from private.secondary_change_tickets')).rows[0];assert.notEqual(stored.token_hash,ticket);assert.equal(stored.scope,'secondary-password-change');
 await rejected(a.query('select * from private.secondary_change_tickets'));
 await rejected(a.query('select private.secondary_candidate_mint($1,$2)',[actor,session]));
 await rejected(a.query('select public.secondary_candidate_issue_after_server_primary($1,$2)',[actor,session]));
 await rejected(change(a,'0'.repeat(64)));await rejected(change(a,ticket,'short'));
 await context(a,other,foreign);await rejected(change(a,ticket));
 await context(a,actor,second);await rejected(change(a,ticket));
 await context(a);await change(a,ticket);await rejected(change(a,ticket));
 const consumed=(await admin('select count(*)::int n from private.secondary_change_tickets where consumed_at is not null')).rows[0].n;assert.equal(consumed,1);
 const expired=await mint('synthetic-replacement');await admin("update private.secondary_change_tickets set expires_at=clock_timestamp()-interval '1 second' where token_hash=encode(digest($1,'sha256'),'hex')",[expired]);await rejected(change(a,expired));
 const blocked=await mint('synthetic-replacement');await admin('insert into private.fixture_account_restrictions values($1)',[actor]);await rejected(change(a,blocked));await rejected(mint('synthetic-replacement'));await admin('delete from private.fixture_account_restrictions');
 const revoked=await mint('synthetic-replacement');await admin('delete from auth.sessions where id=$1',[session]);await rejected(change(a,revoked));await admin('insert into auth.sessions values($1,$2)',[session,actor]);
 const stale=await mint('synthetic-replacement'),fresh=await mint('synthetic-replacement');await change(a,fresh,'synthetic-newer');await rejected(change(a,stale));
 // The new issuing path preserves the existing attempt lock; primary recovery
 // can restore a locked secondary credential through the trusted issuer.
 for(let i=0;i<5;i++)assert.equal(await mint("synthetic-wrong"),null);
 await assert.rejects(mint("synthetic-newer"),/temporarily locked/);
 // Primary proof can only be minted by the trusted service issuer, not a client.
 await context(a,actor,session,'service_role');const primary=(await a.query('select public.secondary_candidate_issue_after_server_primary($1,$2) v',[actor,session])).rows[0].v;
 await context(a);await change(a,primary,'synthetic-primary-restored');
 // Two independent sessions of execution consuming the same actor/session ticket.
 const race=await mint('synthetic-primary-restored');await context(b);await b.query("set statement_timeout='8s';set lock_timeout='6s'");
 await a.query('begin');await change(a,race,'synthetic-race-one');const competing=change(b,race,'synthetic-race-two').then(()=>({ok:true}),error=>({ok:false,error}));
 let observed=false;for(let i=0;i<100;i++){const result=await admin('select wait_event_type from pg_stat_activity where pid=$1',[b.processID]);if(result.rows[0]?.wait_event_type==='Lock'){observed=true;break;}await new Promise(resolve=>setTimeout(resolve,10));}assert.equal(observed,true,'actual lock wait required');
 await a.query('commit');const outcome=await competing;assert.equal(outcome.ok,false);assert.match(outcome.error.message,/proof invalid/);
 assert.equal((await a.query("select public.verify_secondary_password('synthetic-race-one') v")).rows[0].v,true);
 await context(a,actor,session,'anon');await rejected(change(a,race));
 console.log('PASS PostgreSQL 17 candidate: initial/change distinction, private hashed tickets, verified secondary issuance, service-only primary issuer, wrong actor/session/replay/expiry/invalid input/restricted/revoked/stale credential denial, actual concurrent single consumption. No production integration.');
}finally{await Promise.allSettled([a.query('rollback'),b.query('rollback')]);await Promise.allSettled([a.end(),b.end()]);}
