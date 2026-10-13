import assert from 'node:assert/strict';
import {setup,id} from './line_shared_factory_fixture.mjs';
process.on('uncaughtException',e=>{console.error(e.message,e.code);process.exit(1);});
const pg=(await import(process.argv[2])).default;
const url=new URL(process.env.SKO_LINE_FACTORY_FIXTURE_URL??'');
if(!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.pathname!='/sko_line_factory_fixture') throw Error('Disposable loopback LINE factory fixture only');
const a=new pg.Client({connectionString:url.href}),b=new pg.Client({connectionString:url.href});await Promise.all([a.connect(),b.connect()]);
const factory=(client,source,origin='line')=>client.query('select public.create_line_shared_chat_group($1,$2,$3,$4) v',[id(source),'Name',origin,id(10)]).then(r=>r.rows[0].v);
const waitLock=async()=>{for(let n=0;n<100;n++){if((await a.query('select wait_event_type from pg_stat_activity where pid=$1',[b.processID])).rows[0]?.wait_event_type==='Lock')return;await new Promise(r=>setTimeout(r,10));}throw Error('Expected actual lock wait');};
try {
 await setup({exec:sql=>a.query(sql)});
 for(const c of[a,b])await c.query("select set_config('test.uid',$1,false),set_config('statement_timeout','8s',false),set_config('lock_timeout','6s',false)",[id(1)]);
 // Factory → factory: directory lock serializes one canonical group.
 await a.query('begin');const canonical=await factory(a,20);const again=factory(b,20,'sko');await waitLock();await a.query('commit');assert.equal(await again,canonical);
 // Legacy linking → factory: reuse the active primary, no new group.
 const legacy=(await a.query("select private.create_custom_chat_group('Legacy') v")).rows[0].v;
 await a.query('begin');await a.query('select private.link_line_source_to_chat($1,$2)',[legacy,id(21)]);const reuse=factory(b,21);await waitLock();await a.query('commit');assert.equal(await reuse,legacy);
 // Factory → legacy linking: old multi-target link is retained; no deadlock.
 await a.query(`insert into private.line_joined_groups values('${id(23)}','source-c','Group C',true)`);
 const oldTarget=(await a.query("select private.create_custom_chat_group('Existing target') v")).rows[0].v;
 await a.query('begin');const third=await factory(a,23);const linking=b.query('select private.link_line_source_to_chat($1,$2)',[oldTarget,id(23)]);await waitLock();await a.query('commit');await linking;
 assert.equal((await a.query('select count(*)::int n from private.line_chat_source_links where directory_id=$1',[id(23)])).rows[0].n,2);
 assert.equal(await factory(b,23),third);
 assert.equal((await a.query('select count(*)::int n from communication_groups')).rows[0].n,4);
 console.log('PostgreSQL 17 actual lock waits passed: factory/factory, legacy/factory, factory/legacy; no duplicate canonical groups, no deadlocks, legacy multi-target links retained.');
}finally {await Promise.allSettled([a.query('rollback'),b.query('rollback')]);await Promise.allSettled([a.end(),b.end()]);}
