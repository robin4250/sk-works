import {readFile} from 'node:fs/promises';import assert from 'node:assert/strict';
import {sanitizePlatformRows} from './platform_log_adapter.mjs';
const {PGlite}=await import(process.argv[2]);const db=new PGlite();
await db.exec(`create role anon;create role authenticated;create role service_role;create schema private;create schema auth;
create function auth.uid() returns uuid language sql stable as $$select coalesce(nullif(current_setting('test.uid',true),''),nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid$$;
create function auth.role() returns text language sql stable as $$select coalesce(nullif(current_setting('test.role',true),''),nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role')$$;
create function private.account_access_allowed() returns boolean language sql stable as $$select coalesce(nullif(current_setting('test.account',true),'')::boolean,(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'fixture_account')::boolean,false)$$;
create function public.is_current_user_master_admin() returns boolean language sql stable as $$select coalesce(nullif(current_setting('test.master',true),'')::boolean,(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'fixture_master')::boolean,false)$$;
create table private.fixture_proofs(proof text primary key,used boolean not null default false);
create function private.consume_reauthentication_proof(operation text,target jsonb,proof text) returns void language plpgsql security definer set search_path='' as $$begin
 if operation<>'master.security_incidents.read' or target<>'{"scope":"platform"}'::jsonb then raise exception 'bad scope';end if;
 update private.fixture_proofs set used=true where fixture_proofs.proof=consume_reauthentication_proof.proof and not used;
 if not found then raise exception 'proof unavailable';end if;end$$;
grant usage on schema private,auth to authenticated,service_role,anon;`);
await db.exec(await readFile(new URL('../../supabase/migrations/20261016104838_platform_security_monitor.sql',import.meta.url),'utf8'));
const to=new Date(Date.now()-60000).toISOString(),from=new Date(Date.parse(to)-300000).toISOString();
const batch=sanitizePlatformRows({source:'edge_logs',rows:[{id:'fixture',timestamp:new Date(Date.parse(from)+60000).toISOString(),status:403,target:'/rest/v1/example?secret=x'}],from,to,hmacKey:Buffer.alloc(32,9),keyEpoch:1});
async function role(r,{master=false,account=true,uid='11111111-1111-4111-8111-111111111111'}={}){await db.exec(`reset role;select set_config('test.role','${r}',false),set_config('test.uid','${uid}',false),set_config('test.master','${master}',false),set_config('test.account','${account}',false);set role ${r}`);}
async function ingest(b=batch){return db.query('select public.service_ingest_platform_monitor($1::jsonb) n',[JSON.stringify(b)]);}
async function denied(f,re){await assert.rejects(f,re);}
try{
 await role('service_role');await denied(ingest(),/disabled/);
 await db.exec('reset role;update private.platform_monitor_control set enabled=true');
 for(const r of ['anon','authenticated']){await role(r);await denied(ingest(),/permission denied/);await denied(db.query('select * from private.platform_monitor_events'),/permission denied/);}
 await role('service_role');assert.equal((await ingest()).rows[0].n,1);assert.equal((await ingest()).rows[0].n,1);
 await denied(ingest({...batch,events:[{...batch.events[0],result:'http_success'}]}),/conflict/);
 await denied(ingest({...batch,key_epoch:2,events:[{...batch.events[0],raw_ip:'secret'}]}),/invalid platform event/);
 await denied(ingest({...batch,events:[batch.events[0],batch.events[0]]}),/invalid platform batch/);
 await denied(ingest({...batch,source:'auth_audit_logs'}),/invalid platform event/);
 await denied(ingest({...batch,source:'edge_logs',company_id:'forged'}),/invalid platform batch/);
 await denied(ingest({...batch,key_epoch:2,events:[batch.events[0],{...batch.events[0],event_key:'b'.repeat(64),raw_ip:'secret'}]}),/invalid platform event/);
 await denied(ingest({...batch,key_epoch:2,events:[{...batch.events[0],source_key:'a'.repeat(64),source_tracking:'verified'}]}),/invalid platform event/);
 await db.exec('begin');const large={...batch,key_epoch:9,events:Array.from({length:1000},(_,i)=>({...batch.events[0],event_key:i.toString(16).padStart(64,'0')}))};assert.equal((await ingest(large)).rows[0].n,1000);await db.exec('rollback');
 await db.exec('reset role');assert.equal((await db.query('select count(*)::int n from private.platform_monitor_events')).rows[0].n,1);
 for(const options of [{},{master:true,account:false}]){await role('authenticated',options);await denied(db.query("select public.master_platform_security_monitor('x')"),/unavailable/);}
 await role('authenticated',{master:true});await denied(db.query("select public.master_platform_security_monitor('x')"),/proof unavailable/);
 await db.exec("reset role;insert into private.fixture_proofs values('fixture-proof',false)");await role('authenticated',{master:true});
 const out=(await db.query("select public.master_platform_security_monitor('fixture-proof') report")).rows[0].report;assert.equal(out.source_provenance,'supabase_platform_logs');assert.equal(out.events.length,1);assert.equal(out.events[0].result,'forbidden');assert.doesNotMatch(JSON.stringify(out),/secret|raw_ip|company_id|synthetic_fixture/);
 await denied(db.query("select public.master_platform_security_monitor('fixture-proof')"),/proof unavailable/);
 await db.exec('reset role;update private.platform_monitor_control set enabled=false');await role('authenticated',{master:true});await denied(db.query("select public.master_platform_security_monitor('x')"),/disabled/);
 if(process.env.SKO_PLATFORM_POSTGREST_URL){await db.exec('reset role;update private.platform_monitor_control set enabled=true');await (await import('./platform_log_http_check.mjs')).checkHttp(db,batch);}
 console.log('PASS platform SQL default-off, service-only, strict metadata, idempotency/conflicts/atomic rollback, master/account/proof/privacy');
 console.log('LIMIT: auth/master/proof are explicit fixture stubs; real session/nonce transport is auth lane integration, not production verified.');
}finally{await db.close();}
