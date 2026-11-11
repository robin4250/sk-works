// PGlite boundary fixture only. Live Auth/HMAC/concurrency are NOT proved here.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const {PGlite}=await import(process.env.PGLITE_PACKAGE||'../../fixture_dependencies/node_modules/@electric-sql/pglite/dist/index.js');
const sql=await readFile(new URL('../src/archive-source-export.sql.review-only',import.meta.url),'utf8');
test('private source export binds persisted owner, terminal revision, evidence and complete history',async()=>{
 const db=new PGlite();
 const actor='00000000-0000-0000-0000-000000000001',company='00000000-0000-0000-0000-000000000002',event='00000000-0000-0000-0000-000000000003',collector='00000000-0000-0000-0000-000000000004';
 try{
 await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;create schema private;create schema security_management_issuer_private;create schema security_observation_notice_private;
 create function auth.uid()returns uuid language sql as $$select current_setting('fixture.actor')::uuid$$;
 create function private.require_reauthentication_session()returns uuid language plpgsql as $$begin if current_setting('fixture.live')<>'true'then raise exception 'expired';end if;return '00000000-0000-0000-0000-000000000005';end$$;
 create function security_management_issuer_private.binding(uuid,uuid,uuid,text,boolean)returns jsonb language plpgsql as $$begin if current_setting('fixture.owner')<>'true'or $4<>'deployment'then raise exception 'owner mismatch';end if;return '{}'::jsonb;end$$;
 create table security_observation_notice_private.config(singleton boolean,enabled boolean,collector_id uuid,company_id uuid,master_id uuid,revision bigint);
 create table security_observation_notice_private.outbox(event_id uuid,collector_id uuid,company_id uuid,recipient_id uuid,config_revision bigint,state text);
 create table security_observation_notice_private.inbox(event_id uuid,company_id uuid,recipient_id uuid,event_kind text,generation integer,occurred_at timestamptz,review_state text,review_reason text,revision bigint);
 create table security_observation_notice_private.audit(audit_id bigint,event_id uuid,action text,before_revision bigint,after_revision bigint,reason text);
 create table private.security_collector_events(event_id uuid,collector_id uuid,event_kind text,generation integer,occurred_at timestamptz);
 create table private.security_collector_evidence(event_id uuid,collector_id uuid,key_version integer,transport_timestamp bigint,original_body bytea,signature bytea);
 create table private.security_collector_keys(collector_id uuid,key_version integer,hmac_key bytea);
 create function private.verify_collector_event_evidence(uuid)returns boolean language sql as $$select current_setting('fixture.evidence')='true'$$;
 set fixture.actor='${actor}';set fixture.live='true';set fixture.owner='true';set fixture.evidence='true';
 insert into security_observation_notice_private.config values(true,true,'${collector}','${company}','${actor}',1);
 insert into security_observation_notice_private.outbox values('${event}','${collector}','${company}','${actor}',1,'available');
 insert into security_observation_notice_private.inbox values('${event}','${company}','${actor}','current_lure_touched',1,'2026-10-30Z','resolved','checked',2);
 insert into security_observation_notice_private.audit values(1,'${event}','queued',null,null,null),(2,'${event}','available',null,null,null),(3,'${event}','resolved',1,2,'checked');
 insert into private.security_collector_events values('${event}','${collector}','current_lure_touched',1,'2026-10-30Z');
 insert into private.security_collector_evidence values('${event}','${collector}',1,1793318400000,'original bytes','signature');
 insert into private.security_collector_keys values('${collector}',1,'SECRET_NEVER_EXPORT');`);
 await db.exec(await readFile(new URL('../src/archive-readback-registry.sql.review-only',import.meta.url),'utf8'));
 await db.exec(sql);
 await db.exec(await readFile(new URL('../src/archive-source-register.sql.review-only',import.meta.url),'utf8'));
 const call=()=>db.query('select archive_readback_private.lock_source_export($1,$2,$3) result',[event,2,'deployment']);
 const output=(await call()).rows[0].result;
 assert.equal(output.status,'source_locked_unattested');
 assert.equal(output.snapshot_sha256,createHash('sha256').update(output.snapshot_body).digest('hex'));
 const body=JSON.parse(output.snapshot_body);assert.equal(body.company_id,company);assert.equal(body.owner_id,actor);
 assert.equal(Buffer.from(body.source_envelope.body_base64,'base64').toString(),'original bytes');
 assert.equal(output.snapshot_body.includes('SECRET_NEVER_EXPORT'),false);
 assert.equal(body.review_history.length,3);
 const payload=Buffer.from('synthetic encrypted fixture only'),payloadHash=createHash('sha256').update(payload).digest('hex');
 const encoded=Buffer.from(JSON.stringify({schema:1,company_id:company,event_id:event,revision:2,snapshot_sha256:output.snapshot_sha256,payload_sha256:payloadHash,payload_base64:payload.toString('base64')}));
 const objectId=createHash('sha256').update(encoded).digest('hex');
 const register=(bytes=payload,id=objectId)=>db.query('select archive_readback_private.register_locked_source($1,$2,$3,$4,$5,$6,$7) r',
  [event,2,'deployment','00000000-0000-0000-0000-000000000006',output.snapshot_sha256,bytes,id]);
 const registered=(await register()).rows[0].r;
 assert.equal(registered.status,'registered_unattested');assert.equal(registered.descriptor.object_id,objectId);
 assert.deepEqual((await register()).rows[0].r,registered);
 await assert.rejects(register(Buffer.from('wrong bytes')));
 await assert.rejects(db.query('update archive_readback_private.authority_records set byte_length=1'));

 for(const role of ['anon','authenticated','service_role']){
  await db.exec(`set role ${role}`);await assert.rejects(call);await db.exec('reset role');
 }
 async function negative(change){await db.exec('begin');try{await db.exec(change);await assert.rejects(call);}finally{await db.exec('rollback');}}
 for(const change of [
  "set fixture.live='false'","set fixture.owner='false'","set fixture.evidence='false'",
  "set fixture.actor='00000000-0000-0000-0000-000000000099'",
  'update security_observation_notice_private.config set enabled=false',
  'update security_observation_notice_private.config set revision=2',
  "update security_observation_notice_private.outbox set state='pending'",
  'update security_observation_notice_private.inbox set revision=3',
  "update security_observation_notice_private.inbox set review_state='investigating'",
  "update security_observation_notice_private.inbox set review_reason=''",
  "update security_observation_notice_private.inbox set company_id='00000000-0000-0000-0000-000000000099'",
  'delete from security_observation_notice_private.audit',
  "delete from security_observation_notice_private.audit where action='queued'",
  'update security_observation_notice_private.audit set before_revision=0 where after_revision=2',
  "update security_observation_notice_private.audit set reason='changed'",
  'delete from private.security_collector_keys',
  'update private.security_collector_events set generation=2'
 ])await negative(change);
 assert.deepEqual((await call()).rows[0].result,output);
 assert.equal((await db.query('select count(*)::int n from private.security_collector_evidence')).rows[0].n,1);
 }finally{await db.close();}
});
