// Native transaction integration using synthetic scanner/context/nonce and toy
// attendance tables. The candidate common QR gate is real; auth/writer are not.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {generateKeyPairSync,randomBytes,sign} from 'node:crypto';
import {acceptQrScan} from './qr-scan-coordinator.mjs';
import {createQrScanPostgresAdapter} from './qr-scan-postgres-adapter.mjs';
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
    create table qr_scan_fixture.challenges(id uuid primary key,doc jsonb not null,consumed boolean not null default false,receipt uuid);
    create table qr_scan_fixture.attendance_receipts(id uuid primary key default gen_random_uuid(),challenge_id uuid unique not null);
    update qr_attendance_private.public_contract_rollout set enabled=true;
    update private.master_feature_settings set enabled=true where feature_key='qr_attendance';`);
  await setup.query('insert into qr_scan_fixture.challenges(id,doc) values($1,$2)',[id(3),JSON.stringify(challenge)]);
  await setup.query('reset all');
 } finally {setup.release();}
 const adapter=createQrScanPostgresAdapter({pool,
  initializeVerifiedSession:async c=>{await c.query("select set_config('fixture.actor',$1,true),set_config('fixture.session','live',true)",[id(5)]);},
  loadLockedScan:async(c,request)=>{
    const r=await c.query('select doc,consumed,receipt,(extract(epoch from clock_timestamp())*1000)::bigint as now from qr_scan_fixture.challenges where id=$1 for update',[request.challengeId]);
    if(!r.rows[0])return null;const row=r.rows[0];
    return {actor:id(5),session:id(6),sessionActive:true,scannerAuthorized:true,deviceActive:true,subjectActive:true,qrEnabled:true,
      challenge:row.doc,publicKeyDer:publicKey.export({format:'der',type:'spki'}),nowMs:Number(row.now),expiresMs:Number(row.now)+1000,
      consumed:row.consumed,receiptId:row.receipt};
  },
  // Toy insert exercises transaction coupling; it is not an existing SKO writer.
  writeRegularAttendance:async(c,{lockedState})=>{
    assert.equal(lockedState.challenge.sourceClockInId,id(4));
    return (await c.query('insert into qr_scan_fixture.attendance_receipts(challenge_id) values($1) returning id',[lockedState.challenge.challengeId])).rows[0].id;
  },
  consumeWithReceipt:async(c,{challengeId,receiptId})=>{
    if(failConsume)return false;
    return (await c.query('update qr_scan_fixture.challenges set consumed=true,receipt=$2 where id=$1 and not consumed returning id',[challengeId,receiptId])).rowCount===1;
  }});
 failConsume=true;await assert.rejects(acceptQrScan({...args,adapter}),/not_accepted/);failConsume=false;
 assert.equal(Number((await pool.query('select count(*) n from qr_scan_fixture.attendance_receipts')).rows[0].n),0);
 assert.equal((await pool.query('select consumed from qr_scan_fixture.challenges')).rows[0].consumed,false);
 const concurrent=await Promise.allSettled([acceptQrScan({...args,adapter}),acceptQrScan({...args,adapter})]);
 assert.ok(concurrent.some(r=>r.status==='fulfilled'));
 for(const r of concurrent)if(r.status==='rejected')assert.equal(r.reason.code,'40001');
 const retry=await acceptQrScan({...args,adapter});assert.equal(retry.alreadyRecorded,true);
 assert.equal(Number((await pool.query('select count(*) n from qr_scan_fixture.attendance_receipts')).rows[0].n),1);
 assert.equal(retry.receiptId,(await pool.query('select receipt from qr_scan_fixture.challenges')).rows[0].receipt);
 // Gate runs before challenge reads/writes, including receipt retries.
 await pool.query("update private.master_feature_settings set enabled=false where feature_key='qr_attendance'");
 await assert.rejects(acceptQrScan({...args,adapter}),e=>e.code==='42501');
 // Transaction-local auth claims must not survive in pooled connections.
 for(let i=0;i<4;i++){
   const c=await pool.connect();try{const r=await c.query("select nullif(current_setting('fixture.actor',true),'') as actor");assert.equal(r.rows[0].actor,null);}finally{c.release();}
 }
 console.log('Native QR coordinator: gate, transactional rollback, concurrent single receipt, explicit retry and pool cleanup passed (synthetic auth/writer)');
} finally {
 if(pool)await pool.end();if(created)await admin.query(`drop database ${db}`);await admin.end();
}
