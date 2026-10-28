// Native transaction integration using real candidate nonce ledger, candidate scanner/context SQL and toy
// attendance tables. The candidate common QR gate is real; auth/writer are not.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {generateKeyPairSync,randomBytes,sign} from 'node:crypto';
import {acceptQrScan} from './qr-scan-coordinator.mjs';
import {createQrScanPostgresAdapter} from './qr-scan-postgres-adapter.mjs';
import {loadQrScannerContext} from './qr-scanner-context-loader.mjs';
import {createQrScanLedgerHooks} from './qr-scan-ledger-hooks.mjs';
import {qrDeviceSigningBytes,qrTokenHash} from './qr-device-verification.mjs';
if(process.env.CI!=='true'||process.env.PGHOST!=='127.0.0.1')throw Error('disposable loopback CI only');
const pg=(await import(resolve('tool/security/fixture_dependencies/node_modules/pg/lib/index.js'))).default;
const db='qr_scan_'+randomBytes(8).toString('hex'),admin=new pg.Client();let pool,created=false;
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const expand=p=>readFileSync(p,'utf8').split('\n').filter(x=>!x.startsWith('\\set')).map(x=>x.startsWith('\\ir ')?expand(resolve(dirname(p),x.slice(4))):x).join('\n');
const {privateKey,publicKey}=generateKeyPairSync('ed25519'),token=randomBytes(32).toString('base64url');
const challenge={companyId:id(1),deviceId:id(2),challengeId:id(3),tokenHash:qrTokenHash(token),action:'clock_out',sourceClockInId:id(4)};
const args={actor:id(5),session:id(6),challengeId:id(3),rawToken:token,signature:sign(null,qrDeviceSigningBytes(challenge),privateKey)};
let failConsume=false;
try {
 await admin.connect();await admin.query(`create database ${db}`);created=true;pool=new pg.Pool({database:db,max:4});
 const setup=await pool.connect();
 try {
  await setup.query(expand(resolve('docs/review/qr-master-gate/qr-common-public-contract-test.sql')));
  await setup.query(`create schema qr_scan_fixture;
    
    create table qr_scan_fixture.attendance_receipts(id uuid primary key default gen_random_uuid(),challenge_id uuid unique not null);
    update qr_attendance_private.public_contract_rollout set enabled=true;
    update private.master_feature_settings set enabled=true where feature_key='qr_attendance';`);
  await setup.query(readFileSync(resolve('tool/qr-attendance/qr-scan-ledger.sql.review-only'),'utf8'));
  await setup.query(`create table auth.users(id uuid primary key,deleted_at timestamptz,banned_until timestamptz,is_anonymous boolean default false);
    create table auth.sessions(id uuid primary key,user_id uuid references auth.users);
    create table public.companies(id uuid primary key);
    create table public.company_members(company_id uuid,user_id uuid);
    create table public.workers(id uuid primary key,company_id uuid,user_id uuid,status text);
    create or replace function private.require_reauthentication_session() returns uuid language plpgsql as $f$begin
      if current_setting('fixture.session',true) is distinct from 'live' then raise sqlstate '42501';end if;
      return nullif(current_setting('fixture.sid',true),'')::uuid;end$f$;
    create function private.has_company_feature(uuid,text) returns boolean language sql as $f$select current_setting('fixture.manage',true)='yes'$f$;`);
  await setup.query(readFileSync(resolve('tool/qr-attendance/qr-scanner-context.sql.review-only'),'utf8'));
  await setup.query('insert into auth.users(id) values($1),($2)',[id(5),id(8)]);
  await setup.query('insert into auth.sessions values($1,$2)',[id(6),id(5)]);
  await setup.query('insert into public.companies values($1)',[id(1)]);
  await setup.query('insert into public.company_members values($1,$2)',[id(1),id(5)]);
  await setup.query("insert into public.workers values($1,$2,$3,'active')",[id(7),id(1),id(8)]);
  await setup.query('insert into qr_attendance_private.registered_scanners(device_id,company_id,actor_id,public_key_der) values($1,$2,$3,$4)',[id(2),id(1),id(5),publicKey.export({format:'der',type:'spki'})]);
  await setup.query(`insert into qr_attendance_private.scan_challenges(id,company_id,device_id,scanner_actor,scanner_session,subject_worker_id,subject_user_id,action,source_clock_in_id,token_hash,expires_at) values($1,$2,$3,$4,$5,$6,$7,'clock_out',$8,$9,clock_timestamp()+interval '90 seconds')`,[id(3),id(1),id(2),id(5),id(6),id(7),id(8),id(4),challenge.tokenHash]);
  await setup.query('reset all');
 } finally {setup.release();}
 const adapter=createQrScanPostgresAdapter({pool,
  initializeVerifiedSession:async c=>{await c.query("select set_config('fixture.actor',$1,true),set_config('fixture.sid',$2,true),set_config('fixture.session','live',true),set_config('fixture.manage','yes',true)",[id(5),id(6)]);},
  ...createQrScanLedgerHooks({actor:id(5),session:id(6),loadAuthorizedContext:loadQrScannerContext}),
  // Toy insert exercises transaction coupling; it is not an existing SKO writer.
  writeRegularAttendance:async(c,{lockedState})=>{
    assert.equal(lockedState.challenge.sourceClockInId,id(4));
    return (await c.query('insert into qr_scan_fixture.attendance_receipts(challenge_id) values($1) returning id',[lockedState.challenge.challengeId])).rows[0].id;
  },
  consumeWithReceipt:async(c,args)=>{
    if(failConsume)return false;
    return createQrScanLedgerHooks({actor:id(5),session:id(6),loadAuthorizedContext:async()=>null}).consumeWithReceipt(c,args);
  }});
 await assert.rejects(pool.query('update qr_attendance_private.scan_challenges set company_id=$1,receipt_id=$2,consumed_at=clock_timestamp()',[id(9),id(90)]),e=>e.code==='42501');
 failConsume=true;await assert.rejects(acceptQrScan({...args,adapter}),/not_accepted/);failConsume=false;
 assert.equal(Number((await pool.query('select count(*) n from qr_scan_fixture.attendance_receipts')).rows[0].n),0);
 assert.equal((await pool.query('select (receipt_id is not null) consumed from qr_attendance_private.scan_challenges')).rows[0].consumed,false);
 const concurrent=await Promise.allSettled([acceptQrScan({...args,adapter}),acceptQrScan({...args,adapter})]);
 assert.ok(concurrent.some(r=>r.status==='fulfilled'));
 for(const r of concurrent)if(r.status==='rejected')assert.equal(r.reason.code,'40001');
 const retry=await acceptQrScan({...args,adapter});assert.equal(retry.alreadyRecorded,true);
 assert.equal(Number((await pool.query('select count(*) n from qr_scan_fixture.attendance_receipts')).rows[0].n),1);
 assert.equal(retry.receiptId,(await pool.query('select receipt_id receipt from qr_attendance_private.scan_challenges')).rows[0].receipt);
 await assert.rejects(acceptQrScan({...args,adapter,actor:id(9)}),/not_accepted/);
 await assert.rejects(acceptQrScan({...args,adapter,session:id(9)}),/not_accepted/);
 await assert.rejects(pool.query('update qr_attendance_private.scan_challenges set subject_user_id=$1',[id(9)]),e=>e.code==='42501');
 await assert.rejects(pool.query('update qr_attendance_private.scan_challenges set receipt_id=$1,consumed_at=clock_timestamp()',[id(10)]),e=>e.code==='42501');
 assert.equal((await pool.query("select has_table_privilege('authenticated','qr_attendance_private.scan_challenges','select') as allowed")).rows[0].allowed,false);
 // Gate runs before challenge reads/writes, including receipt retries.
 await pool.query("update private.master_feature_settings set enabled=false where feature_key='qr_attendance'");
 await assert.rejects(acceptQrScan({...args,adapter}),e=>e.code==='42501');
 // Transaction-local auth claims must not survive in pooled connections.
 for(let i=0;i<4;i++){
   const c=await pool.connect();try{const r=await c.query("select nullif(current_setting('fixture.actor',true),'') as actor");assert.equal(r.rows[0].actor,null);}finally{c.release();}
 }
 console.log('Native QR coordinator: gate, transactional rollback, concurrent single receipt, explicit retry and pool cleanup passed (candidate nonce/context SQL; synthetic auth/permission and attendance writer)');
} finally {
 if(pool)await pool.end();if(created)await admin.query(`drop database ${db}`);await admin.end();
}
