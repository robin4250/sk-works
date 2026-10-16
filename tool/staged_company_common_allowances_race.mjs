// Native PostgreSQL lock waits; strictly disposable localhost fixture only.
import {pathToFileURL} from 'node:url';import path from 'node:path';import assert from 'node:assert/strict';
const url=new URL(process.env.SKO_COMMON_ALLOWANCE_FIXTURE_URL??'');assert.equal(url.hostname,'127.0.0.1');assert.equal(url.pathname,'/sko_common_allowance_fixture');
const mod=await import(pathToFileURL(path.resolve(process.argv[2])).href);const Client=mod.Client??mod.default.Client;
const a=new Client({connectionString:url.href}),b=new Client({connectionString:url.href});await a.connect();await b.connect();
const cid='10000000-0000-0000-0000-000000000001',admin='20000000-0000-0000-0000-000000000001',sid=admin.replace(/^2/,'7');let req=0;
const rid=()=>`60000000-0000-4000-8000-${String(++req).padStart(12,'0')}`;
const actor=async client=>{await client.query('reset role');await client.query("select set_config('request.jwt.claim.sub',$1,false),set_config('fixture.account_blocked','',false),set_config('request.jwt.claims',$2,false)",[admin,JSON.stringify({role:'authenticated',sub:admin,session_id:sid})]);await client.query('set role authenticated');};
const state=async client=>(await client.query('select public.read_company_common_allowances_admin($1) v',[cid])).rows[0].v;
const legacy=s=>s.legacy_refs.map(({slot,id,generation,name,source_unit,amount_yen})=>({slot,id,generation,name,source_unit,amount_yen}));
const save=(client,s,request=rid())=>client.query("select public.save_company_common_allowances($1,'monthly',$2,$3::jsonb,$4,'[]'::jsonb,$5::jsonb,true) v",[cid,s.version,JSON.stringify(s.expected_source),request,JSON.stringify(legacy(s))]);
const oldSave=client=>client.query("select public.save_company_rate_settings_with_units(10,0,0,0,0,0,'native-old-writer',950,'既存手当',800,null,0,'回','回','回')");
const outcome=promise=>promise.then(r=>({ok:true,result:r.rows[0]?.v}),e=>({code:e.code}));
async function waited(pid){for(let n=0;n<100;n++){if((await a.query("select wait_event_type from pg_stat_activity where pid=$1",[pid])).rows[0]?.wait_event_type==='Lock')return;await new Promise(r=>setTimeout(r,20));}throw Error('fixture did not observe a real PostgreSQL lock wait');}
const lockCompany=async()=>{await a.query('reset role');await a.query('begin');await a.query('select 1 from public.companies where id=$1 for update',[cid]);};
try{
 await actor(a);await actor(b);let s=await state(a);const pid=(await b.query('select pg_backend_pid() pid')).rows[0].pid;
 await lockCompany();let pending=outcome(save(b,s));await waited(pid);await a.query('set local role authenticated');await save(a,s);await a.query('commit');assert.deepEqual(await pending,{code:'40001'});
 // Old combined saver first: its actual +2 legacy version invalidates new source.
 await actor(a);s=await state(a);await lockCompany();pending=outcome(save(b,s));await waited(pid);await a.query('set local role authenticated');await oldSave(a);await a.query('commit');assert.deepEqual(await pending,{code:'40001'});await actor(a);let after=await state(a);assert.equal(after.version,s.version);assert.equal(after.expected_source.legacy_version,s.expected_source.legacy_version+2);
 // New first then old: old writer may legitimately finish, but one canonical
 // legacy source remains and the next stale new snapshot is rejected.
 s=after;await a.query('begin');await save(a,s);pending=outcome(oldSave(b));await a.query('reset role');await waited(pid);await a.query('commit');assert.equal((await pending).ok,true);await actor(a);after=await state(a);assert.equal(after.legacy_refs[0].name,'native-old-writer');assert.equal(after.legacy_refs[0].id,s.legacy_refs[0].id);await assert.rejects(save(a,s),e=>e.code==='40001');
 // Membership downgrade commits while a writer waits: no unauthorized write.
 s=after;await lockCompany();const deniedRid=rid();pending=outcome(save(b,s,deniedRid));await waited(pid);await a.query("update public.company_members set role='manager' where company_id=$1 and user_id=$2",[cid,admin]);await a.query('commit');assert.deepEqual(await pending,{code:'42501'});await a.query("update public.company_members set role='admin' where company_id=$1 and user_id=$2",[cid,admin]);await actor(a);assert.equal((await state(a)).version,s.version);assert.equal((await a.query('select public.read_company_common_allowance_request($1,$2) v',[cid,deniedRid])).rows[0].v.found,false);
 // Session expires while waiting: the post-lock check must reject it.
 s=await state(a);await lockCompany();pending=outcome(save(b,s));await waited(pid);await a.query("update auth.sessions set not_after=now()-interval '1 second' where id=$1",[sid]);await a.query('commit');assert.deepEqual(await pending,{code:'42501'});await a.query('update auth.sessions set not_after=null where id=$1',[sid]);await actor(a);assert.equal((await state(a)).version,s.version);
 console.log('PASS native PG17: five observed real row-lock waits; new/new CAS, old→new +2 source conflict, new→old canonical identity, waiting role downgrade and session expiry denied without unauthorized version/receipt mutation. Synthetic JWT claims only.');
}finally{await a.query('rollback');await a.end();await b.end();}
