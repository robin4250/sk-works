import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {schema,A,U,R,S1,ST1,ST2} from './route_atomic_fixture.mjs';
const mod=await import(pathToFileURL(process.argv[2]).href);
const {Client}=mod.default??mod;
const raw=process.env.SKO_ROUTE_ATOMIC_DATABASE_URL;
const url=new URL(raw);
if(!['postgres:','postgresql:'].includes(url.protocol)||!['localhost','127.0.0.1','[::1]'].includes(url.hostname)||url.search||!url.pathname.includes('fixture'))throw Error('localhost disposable fixture database only');
const name=`sko_route_atomic_fixture_${process.pid}_${Date.now()}`;
const admin=new Client({connectionString:raw}),clients=[];
let created=false;
const outcome=p=>p.then(value=>({value}),error=>({error}));
async function connect(){const u=new URL(raw);u.pathname='/'+name;const c=new Client({connectionString:u.href});await c.connect();clients.push(c);await c.query("set statement_timeout='15s';set lock_timeout='12s'");await c.query(`set test.actor='${U}'`);return c;}
async function blocked(observer,pid,holder){const end=Date.now()+5000;while(Date.now()<end){const r=await observer.query('select $2::int=any(pg_blocking_pids($1::int)) b',[pid,holder]);if(r.rows[0].b)return;await new Promise(r=>setTimeout(r,25));}throw Error('expected real lock wait not observed');}
const stops=[{id:ST1,site_id:S1,address:'old A',source_kind:'site',source_id:S1},{id:ST2,address:'old B',source_kind:'address'}];
const cmd=n=>`00000000-0000-4000-9000-${String(n).padStart(12,'0')}`;
try{
await admin.connect();await admin.query(`create database "${name}"`);created=true;
const ctl=await connect(),a=await connect(),b=await connect();
await ctl.query(schema);
await ctl.query(await fs.readFile(new URL('./staged/route_atomic_save.sql',import.meta.url),'utf8'));
await ctl.query('insert into route_atomic_private.rollout values($1,true)',[A]);
const pidA=(await a.query('select pg_backend_pid() p')).rows[0].p,pidB=(await b.query('select pg_backend_pid() p')).rows[0].p;
const snapshot=async(c=ctl)=>(await c.query('select route_atomic_private.snapshot($1,$2) s',[A,R])).rows[0].s;
const save=async(c,p,n,data={route_name:'atomic name',notes:'atomic'})=>(await c.query('select route_atomic_private.save($1,$2,$3,$4,$5,$6) s',[A,cmd(n),R,p,data,stops])).rows[0].s;
// New API starts first; direct legacy metadata writer waits then is denied.
let p=await snapshot();
await a.query('begin');await save(a,p,1);
const legacy=outcome(b.query('update route_assignments set notes=$1 where id=$2',['legacy bad',R]));
await blocked(ctl,pidB,pidA);await a.query('commit');
assert.equal((await legacy).error?.code,'55000');assert.equal((await snapshot()).route.notes,'atomic');
// Two API commands from the same exact revision: only one result commits.
p=await snapshot();await a.query('begin');await save(a,p,2,{route_name:'winner',notes:'winner'});
const loser=outcome(save(b,p,3,{route_name:'loser',notes:'loser'}));
await blocked(ctl,pidB,pidA);await a.query('commit');assert.equal((await loser).error?.code,'40001');
assert.equal((await snapshot()).route.route_name,'winner');
// Legacy OFF begins first. ON waits for its shared rollout row and cannot
// expose a partially overlapping old transaction as an atomic write.
await ctl.query('update route_atomic_private.rollout set enabled=false');
const stale=await snapshot();
await a.query('begin');await a.query('update route_assignments set notes=$1 where id=$2',['legacy committed',R]);
const enable=outcome(b.query('update route_atomic_private.rollout set enabled=true'));
await blocked(ctl,pidB,pidA);await a.query('commit');assert.ok((await enable).value);
const staleResult=await outcome(save(b,stale,4));
assert.equal(staleResult.error?.code,'40001');assert.equal((await snapshot()).route.notes,'legacy committed');
// Source IDs and every stop survive a late insert/update failure after body UPDATE.
p=await snapshot();const before=JSON.stringify(p);
await a.query("set test.fail_stop='yes'");
const late=await outcome(a.query('select route_atomic_private.save($1,$2,$3,$4,$5,$6)',[A,cmd(5),R,p,{route_name:'must rollback'},[{...stops[0],address:'changed'},stops[1]]]));
assert.equal(late.error?.code,'P0001');assert.equal(JSON.stringify(await snapshot()),before);
await a.query("set test.fail_stop='no'");
// ON legacy stop insert is rejected even with a forged custom setting.
await b.query("set route_atomic.context='yes'");
const bypass=await outcome(b.query("insert into route_stops(company_id,route_assignment_id,stop_order,address) values($1,$2,2,'bad')",[A,R]));
assert.equal(bypass.error?.code,'55000');assert.equal(JSON.stringify(await snapshot()),before);
assert.equal((await ctl.query('select count(*)::int n from route_atomic_private.context')).rows[0].n,0);
console.log('real PG17 atomic route: observed API/legacy and API/API waits, OFF legacy→ON barrier, CAS loser, late failure rollback and nonforgeable context passed; no timeout/deadlock accepted');
}finally{
for(const c of clients){try{await c.query('rollback');await c.end();}catch{}}
if(created)await admin.query(`drop database "${name}" with(force)`);
await admin.end();
}

