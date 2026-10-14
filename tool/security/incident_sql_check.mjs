process.on('uncaughtException',e=>{console.error(e.message,e.code);process.exit(1);});
import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import {IncidentCollector} from './incident_collector.mjs';
const {PGlite}=await import(process.argv[2]);const db=new PGlite();
await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;create schema private;create table auth.users(id uuid primary key);create table public.companies(id uuid primary key);create table company_members(company_id uuid,user_id uuid);create table app_notifications(id uuid primary key default gen_random_uuid(),company_id uuid,recipient_user_id uuid,kind text,title text,body text,action_key text,action_id uuid);
create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
create function private.account_access_allowed() returns boolean language sql as $$select coalesce(current_setting('test.blocked',true),'false')<>'true'$$;
create function public.is_current_user_master_admin() returns boolean language sql as $$select current_setting('test.master',true)='true'$$;
create function private.enqueue_notification(uuid,uuid,text,text,text,text,uuid) returns uuid language plpgsql as $$declare i uuid;begin insert into public.app_notifications(company_id,recipient_user_id,kind,title,body,action_key,action_id)values($1,$2,$3,$4,$5,$6,$7)returning id into i;return i;end$$;
grant usage on schema public,auth to anon,authenticated;grant execute on all functions in schema auth to authenticated;`);
const uid=crypto.randomUUID(),other=crypto.randomUUID(),cid=crypto.randomUUID(),othercid=crypto.randomUUID();
await db.exec(`insert into auth.users values('${uid}'),('${other}');insert into companies values('${cid}'),('${othercid}');insert into company_members values('${cid}','${uid}'),('${othercid}','${other}');select set_config('test.uid','${uid}',false);select set_config('test.master','true',false);`);
await db.exec(await readFile(new URL('../../supabase/migrations/20261013223123_master_security_incident_records.sql',import.meta.url),'utf8'));
let now=Date.now()-10000;const c=new IncidentCollector({clock:()=>now,beforeMs:0,afterMs:0});const e={event_id:crypto.randomUUID(),at:now,kind:'current_lure_touched',generation:1};c.ingest(e);const report=c.detect({event_id:e.event_id});
const save=(r=report,v=1)=>db.query('select public.save_master_security_incident($1::jsonb,$2::int)',[JSON.stringify(r),v]);const read=()=>db.query('select public.master_security_incidents() v');
await db.exec('set role authenticated');await save();await save();assert.equal((await read()).rows[0].v.incidents.length,1);
await assert.rejects(db.query('select * from private.security_incident_records'));
await assert.rejects(save({...report,secret:'synthetic-secret'}));await assert.rejects(save({...report,incident_id:'synthetic-secret'}),e=>!e.message.includes('synthetic-secret'));await assert.rejects(save({...report,event_count:null}));await assert.rejects(save({...report,events:[{...report.events[0],kind:null}]}));await assert.rejects(save({...report,collection_status:'collecting'}));
const empty={...report,incident_id:crypto.randomUUID(),event_count:0,events:[],first_seen:null,last_seen:null,collection_status:'partial',missing_before:true};await save(empty);await assert.rejects(save({...empty,incident_id:crypto.randomUUID(),missing_before:false}));
await save(report,2);assert.equal((await read()).rows[0].v.incidents[0].record_version,2);assert.equal((await read()).rows[0].v.incidents[0].audit.length,2);await assert.rejects(save(report,4));await assert.rejects(save({...report,correlation_id:crypto.randomUUID()},3));
await db.exec(`select set_config('test.master','false',false)`);await assert.rejects(read());await assert.rejects(save());await db.exec(`select set_config('test.master','true',false);select set_config('test.blocked','true',false)`);await assert.rejects(read());await db.exec(`select set_config('test.blocked','false',false);select set_config('test.uid','${other}',false)`);assert.deepEqual((await read()).rows[0].v.incidents,[]);await assert.rejects(save());await db.exec('reset role');
assert.equal((await db.query('select count(*)::int n from app_notifications')).rows[0].n,2);assert.equal((await db.query('select count(*)::int n from private.security_incident_notification_outbox')).rows[0].n,2);
await db.exec(`create or replace function private.enqueue_notification(uuid,uuid,text,text,text,text,uuid) returns uuid language plpgsql as $$begin raise exception 'synthetic notification failure';end$$;select set_config('test.uid','${uid}',false)`);
const before=(await db.query('select count(*)::int n from private.security_incident_records')).rows[0].n;await assert.rejects(save({...report,incident_id:crypto.randomUUID()}));assert.equal((await db.query('select count(*)::int n from private.security_incident_records')).rows[0].n,before);
await db.exec('set role anon');await assert.rejects(read());await assert.rejects(save());await db.exec('reset role');
await db.exec(`select set_config('test.uid','${uid}',false)`);
for(const invalid of [
 {...report,events:[{...report.events[0],sequence:'synthetic-private-value'}]},
 {...report,detected_at:'2026-99-99T00:00:00.000Z'},
 {...report,events:[{...report.events[0],generation:999999999999999999999}]},
])await assert.rejects(save(invalid),e=>!e.message.includes('synthetic-private-value')&&!e.message.includes('2026-99-99'));
if(db.concurrent){
 await db.exec(`create or replace function private.enqueue_notification(uuid,uuid,text,text,text,text,uuid) returns uuid language plpgsql as $$declare i uuid;begin insert into public.app_notifications(company_id,recipient_user_id,kind,title,body,action_key,action_id)values($1,$2,$3,$4,$5,$6,$7)returning id into i;return i;end$$;`);
 const concurrent={...report,incident_id:crypto.randomUUID()};
 await db.concurrent(uid,concurrent);
 const result=await db.query('select (select count(*) from private.security_incident_records where incident_id=$1)::int records,(select count(*) from private.security_incident_notification_outbox where incident_id=$1)::int notifications',[concurrent.incident_id]);
 assert.deepEqual(result.rows[0],{records:1,notifications:1});
 console.log('native PG concurrent identical saves: one immutable record and one notification');
}
if(process.env.SKO_INCIDENT_POSTGREST_URL){const {checkHttp}=await import('./incident_http_check.mjs');await checkHttp(db,{uid,other,cid,report});}
console.log('incident SQL boundary tests passed: master/account/owner/company, private grants, idempotency, version immutability, metadata validation, one notification');await db.close();

