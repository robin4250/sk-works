import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createQrScanLedgerHooks} from './qr-scan-ledger-hooks.mjs';
const {PGlite}=await import(resolve(process.env.PGLITE_PATH||'tool/security/fixture_dependencies/node_modules/@electric-sql/pglite/dist/index.js'));
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
test('candidate ledger binds scope, expires consumption, commits once, and preserves rollback',async()=>{
 const db=new PGlite();
 try{
  await db.exec('create role anon;create role authenticated;create schema qr_attendance_private;');
  await db.exec(readFileSync(new URL('./qr-scan-ledger.sql.review-only',import.meta.url),'utf8'));
  const c={query:async(sql,args)=>{const r=await db.query(sql,args);return {...r,rowCount:r.affectedRows};}};
  const insert=async(n,expires="clock_timestamp()+interval '90 seconds'")=>db.query(`insert into qr_attendance_private.scan_challenges(id,company_id,device_id,scanner_actor,scanner_session,subject_worker_id,subject_user_id,action,source_clock_in_id,token_hash,created_at,expires_at) values($1,$2,$3,$4,$5,$6,$7,'clock_out',$8,$9,clock_timestamp()-interval '1 second',${expires})`,[id(n),id(1),id(2),id(5),id(6),id(7),id(8),id(4),String(n).padStart(64,'a')]);
  await insert(3);
  const hooks=createQrScanLedgerHooks({actor:id(5),session:id(6),loadAuthorizedContext:async(_c,{lockedChallenge})=>{
    assert.equal(lockedChallenge.subjectWorkerId,id(7));assert.equal(Object.isFrozen(lockedChallenge),true);
    return {actor:id(99),session:id(99),challenge:{tokenHash:'tampered'},nowMs:0,expiresMs:0,consumed:true,receiptId:id(99),sessionActive:true};
  }});
  await assert.rejects(db.query('update qr_attendance_private.scan_challenges set subject_user_id=$1,receipt_id=$2,consumed_at=clock_timestamp()',[id(9),id(90)]),e=>e.code==='42501');
  await db.exec('begin');
  const state=await hooks.loadLockedScan(c,{actor:id(5),session:id(6),challengeId:id(3)});
  assert.equal(state.actor,id(5));assert.equal(state.session,id(6));assert.equal(state.challenge.challengeId,id(3));
  assert.equal(state.consumed,false);assert.equal(state.receiptId,null);assert.ok(state.expiresMs>state.nowMs);
  assert.equal(await hooks.loadLockedScan(c,{actor:id(9),session:id(6),challengeId:id(3)}),null);
  assert.equal(await createQrScanLedgerHooks({actor:id(5),session:id(9),loadAuthorizedContext:async()=>({})}).loadLockedScan(c,{actor:id(5),session:id(9),challengeId:id(3)}),null);
  assert.equal(await hooks.consumeWithReceipt(c,{challengeId:id(3),receiptId:id(10)}),true);
  await db.exec('rollback');
  assert.equal((await db.query('select receipt_id from qr_attendance_private.scan_challenges')).rows[0].receipt_id,null);
  await db.exec('begin');assert.equal(await hooks.consumeWithReceipt(c,{challengeId:id(3),receiptId:id(10)}),true);await db.exec('commit');
  assert.equal(await hooks.consumeWithReceipt(c,{challengeId:id(3),receiptId:id(11)}),false);
  await assert.rejects(db.query('update qr_attendance_private.scan_challenges set subject_user_id=$1',[id(9)]),e=>e.code==='42501');
  await assert.rejects(db.query('update qr_attendance_private.scan_challenges set receipt_id=null,consumed_at=null'),e=>e.code==='42501');
  await insert(12,"clock_timestamp()-interval '0.5 seconds'");
  assert.equal(await hooks.consumeWithReceipt(c,{challengeId:id(12),receiptId:id(13)}),false);
  assert.equal((await db.query("select has_table_privilege('authenticated','qr_attendance_private.scan_challenges','select') allowed")).rows[0].allowed,false);
 }finally{await db.close();}
});
