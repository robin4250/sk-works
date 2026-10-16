// Actual PostgreSQL 16 sessions. No production connection is permitted.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
const url=new URL(process.env.SKO_SITE_IDENTITY_ROLLOUT_FIXTURE_URL??'postgres://invalid');
if(url.protocol!=='postgres:'||url.hostname!=='127.0.0.1'||url.port!=='5432'||
 url.pathname!=='/sko_site_identity_rollout_fixture'||url.username!=='postgres'||url.search||url.hash)
 throw Error('Only the explicit disposable localhost rollout fixture is permitted');
const pg=await import(pathToFileURL(path.resolve(process.argv[2])).href);
const Client=pg.Client??pg.default?.Client;
const clients=[];
async function connect(name){
 const c=new Client({connectionString:url.href,application_name:name});
 assert.equal(c.connectionParameters.host,'127.0.0.1');
 assert.equal(c.connectionParameters.database,'sko_site_identity_rollout_fixture');
 await c.connect();clients.push(c);
 await c.query("set statement_timeout='20s';set lock_timeout='10s'");
 return c;
}
const id=n=>'00000000-0000-0000-0000-'+String(n).padStart(12,'0');
const actor=async(c,n)=>{await c.query("select set_config('test.uid',$1,false)",[id(100+n)]);await c.query('set role authenticated');};
const setRollout=(c,n,value)=>c.query('select site_identity_private.set_rollout($1,$2) v',[id(n),value]);
const change=(c,revision=0,unlink=false)=>c.query('select public.site_identity_change_link($1,$2,$3,$4,$5) v',[id(2),id(12),unlink?null:id(301),revision,unlink]);
const watch=p=>{p.catch(()=>{});return p;};
let admin,writer,toggler,observer;
async function blocked(name){
 const end=Date.now()+8000;
 while(Date.now()<end){
  await observer.query('select pg_stat_clear_snapshot()');
  const r=await observer.query("select count(*)::int n from pg_stat_activity where application_name=$1 and wait_event_type='Lock' and wait_event='advisory'",[name]);
  if(r.rows[0].n===1)return;
  await new Promise(resolve=>setTimeout(resolve,25));
 }
 throw Error('Expected actual advisory-lock wait was not observed: '+name);
}
const read=p=>fs.readFileSync(p,'utf8');
async function snapshot(){
 return JSON.stringify((await admin.query("select jsonb_build_object('roots',(select jsonb_agg(to_jsonb(r) order by id) from site_identity_private.roots r),'selections',(select jsonb_agg(to_jsonb(s) order by site_id) from site_identity_private.selections s),'events',(select jsonb_agg(to_jsonb(e) order by id) from site_identity_private.events e),'sites',(select jsonb_agg(to_jsonb(s) order by id) from public.sites s),'attendance',(select jsonb_agg(to_jsonb(a) order by id) from public.attendance_entries a)) v")).rows[0].v);
}
try{
 [admin,writer,toggler,observer]=await Promise.all([
 connect('site-rollout-admin'),connect('site-rollout-writer'),connect('site-rollout-toggler'),connect('site-rollout-observer')]);
 const version=Number((await admin.query('show server_version_num')).rows[0].server_version_num);
 assert.ok(version>=160000&&version<170000);console.log('PostgreSQL server_version_num',version);
 assert.equal((await admin.query("select count(*)::int n from pg_namespace where nspname in ('private','auth','site_identity_private')")).rows[0].n,0);
 assert.equal((await admin.query("select count(*)::int n from pg_tables where schemaname='public'")).rows[0].n,0,'Never reset a nonempty fixture');
 await admin.query(read('tool/fixtures/site_identity_rollout/schema.sql'));
 for(let n=1;n<=3;n++){
  await admin.query("insert into company_members values($1,$2,'admin')",[id(n),id(100+n)]);
  await admin.query("insert into sites values($1,$2,'same','正式名')",[id(10+n),id(n)]);
 }
 await admin.query('insert into attendance_entries values($1,$2,321)',[id(501),id(12)]);
 await admin.query('insert into private.document_deliveries values($1,$2,$3)',[id(201),id(1),id(2)]);
 await admin.query("insert into private.company_data_delivery_items values($1,$2,'site_share',$3::jsonb)",[id(301),id(201),JSON.stringify({source_site_id:id(11)})]);
 await admin.query("insert into private.site_share_inbox values($1,$2,'pending')",[id(301),id(2)]);
 await admin.query(read('tool/staged/site_identity_links.sql'));
 await admin.query(read('tool/staged/site_identity_company_rollout.sql'));
 for(let n=1;n<=3;n++){
  await admin.query("select set_config('test.uid',$1,false)",[id(100+n)]);
  await setRollout(admin,n,true);
 }
 await actor(writer,2);await actor(toggler,2);
 // OFF commits while an already-started change waits. The stable helper must
 // see OFF when the volatile change resumes after acquiring its registry lock.
 const initial=await snapshot();
 await toggler.query('begin');await setRollout(toggler,2,false);
 const waitingChange=watch(change(writer));await blocked('site-rollout-writer');
 await toggler.query('commit');
 await assert.rejects(waitingChange,e=>e.code==='55000');
 assert.equal(await snapshot(),initial,'change waiting behind OFF writes no identity/legacy state');
 assert.equal((await admin.query('select enabled from site_identity_private.company_rollout where company_id=$1',[id(2)])).rows[0].enabled,false);
 console.log('PASS started change waits behind OFF; after OFF commit it rejects with no registry or legacy writes');
 // Change commits first while OFF waits; OFF freezes the committed selection.
 await setRollout(toggler,2,true);
 await writer.query('begin');const linked=(await change(writer)).rows[0].v;
 assert.equal(linked.revision,1);
 const beforeOffEvents=(await admin.query('select count(*)::int n from site_identity_private.rollout_events')).rows[0].n;
 const waitingOff=watch(setRollout(toggler,2,false));await blocked('site-rollout-toggler');
 await writer.query('commit');await waitingOff;
 const committed=await snapshot();
 assert.equal((await admin.query('select enabled from site_identity_private.company_rollout where company_id=$1',[id(2)])).rows[0].enabled,false);
 assert.equal((await admin.query('select count(*)::int n from site_identity_private.events')).rows[0].n,1);
 assert.equal((await admin.query('select count(*)::int n from site_identity_private.rollout_events')).rows[0].n,beforeOffEvents+1);
 await assert.rejects(change(writer,1,true),e=>e.code==='55000');
 assert.equal(await snapshot(),committed,'OFF keeps committed link and prevents unlink');
 await setRollout(toggler,2,true);
 assert.equal(await snapshot(),committed,'re-enable retains the exact committed selection/revision');
 const senderBefore=(await admin.query('select to_jsonb(s) v from site_identity_private.selections s where company_id=$1',[id(1)])).rows[0].v;
 const detached=(await change(writer,1,true)).rows[0].v;
 assert.notEqual(detached.display_group,linked.display_group);
 assert.deepEqual((await admin.query('select to_jsonb(s) v from site_identity_private.selections s where company_id=$1',[id(1)])).rows[0].v,senderBefore);
 console.log('PASS change holds registry lock; OFF waits, freezes committed state, and re-enable preserves unlink CAS/other company');
 // Sender OFF is covered by the same lock order and cannot leave receiving roots.
 await toggler.query('reset role');await actor(toggler,1);
 await toggler.query('begin');await setRollout(toggler,1,false);
 const beforeSenderOff=await snapshot();
 const senderBlocked=watch(change(writer,2));await blocked('site-rollout-writer');
 await toggler.query('commit');
 await assert.rejects(senderBlocked,e=>e.code==='55000');
 assert.equal(await snapshot(),beforeSenderOff,'sender OFF must not leak partial receiving changes');
 assert.equal((await admin.query('select site_id,amount from attendance_entries where id=$1',[id(501)])).rows[0].site_id,id(12));
 assert.equal((await admin.query('select amount from attendance_entries where id=$1',[id(501)])).rows[0].amount,321);
 console.log('PASS sender OFF after wait rejects atomically; old site IDs and attendance retained');
 console.log('PASS no deadlock, lock timeout or statement timeout accepted as success');
}finally{
 await Promise.allSettled(clients.map(async c=>{try{await c.query('rollback');}finally{await c.end();}}));
}
