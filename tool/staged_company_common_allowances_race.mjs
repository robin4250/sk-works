// Native two-connection row-lock / stale-write / role-change fixture only.
import {pathToFileURL} from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';
const url=new URL(process.env.SKO_COMMON_ALLOWANCE_FIXTURE_URL??'');
assert.equal(url.hostname,'127.0.0.1');assert.equal(url.pathname,'/sko_common_allowance_fixture');
const mod=await import(pathToFileURL(path.resolve(process.argv[2])).href);const Client=mod.Client??mod.default.Client;
const a=new Client({connectionString:url.href}),b=new Client({connectionString:url.href});await a.connect();await b.connect();
const cid='10000000-0000-0000-0000-000000000001',admin='20000000-0000-0000-0000-000000000001';
const actor=async client=>{await client.query("select set_config('request.jwt.claim.sub',$1,false),set_config('fixture.account_blocked','',false)",[admin]);await client.query('set role authenticated');};
const state=async client=>(await client.query('select public.read_company_common_allowances_admin($1) v',[cid])).rows[0].v;
const save=(client,v,rid)=>client.query("select public.save_company_common_allowances($1,'monthly',$2,$3,'[]'::jsonb) v",[cid,v,rid]);
async function waited(pid){for(let n=0;n<100;n++){if((await a.query("select wait_event_type from pg_stat_activity where pid=$1",[pid])).rows[0]?.wait_event_type==='Lock')return;await new Promise(r=>setTimeout(r,20));}throw Error('fixture did not observe a real PostgreSQL lock wait');}
try{
 await actor(a);await actor(b);const version=(await state(a)).version;
 await a.query('reset role');await a.query('begin');await a.query('select 1 from public.companies where id=$1 for update',[cid]);
 const pid=(await b.query('select pg_backend_pid() pid')).rows[0].pid;
 const pending=save(b,version,'60000000-0000-4000-8000-000000000001').then(()=>({ok:true}),e=>({code:e.code}));
 await waited(pid);await a.query('set local role authenticated');await save(a,version,'60000000-0000-4000-8000-000000000002');await a.query('commit');
 assert.deepEqual(await pending,{code:'40001'});await actor(a);assert.equal((await state(a)).version,version+1);
 // Waiting writer must recheck a committed membership downgrade before mutation.
 await a.query('reset role');await a.query('begin');await a.query('select 1 from public.companies where id=$1 for update',[cid]);
 const denied=save(b,version+1,'60000000-0000-4000-8000-000000000003').then(()=>({ok:true}),e=>({code:e.code}));
 await waited(pid);await a.query("update public.company_members set role='manager' where company_id=$1 and user_id=$2",[cid,admin]);await a.query('commit');
 assert.deepEqual(await denied,{code:'42501'});
 await a.query("update public.company_members set role='admin' where company_id=$1 and user_id=$2",[cid,admin]);await actor(a);assert.equal((await state(a)).version,version+1);
 const r=(await a.query('select public.read_company_common_allowance_request($1,$2) v',[cid,'60000000-0000-4000-8000-000000000003'])).rows[0].v;assert.equal(r.found,false);
 console.log('PASS native PG17: observed two real row-lock waits; concurrent stale version rejected and role downgrade after initial authorization rejected without version/receipt mutation. Synthetic actor claims only.');
}finally{await a.query('rollback');await a.end();await b.end();}
