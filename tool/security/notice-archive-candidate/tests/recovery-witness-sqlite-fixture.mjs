// Synthetic file-backed witness for tests. NOT isolated custody or an endpoint.
import {DatabaseSync} from 'node:sqlite';
import {sign} from 'node:crypto';
import {receiptBytes} from '../src/recovery-witness-model.mjs';
const valid=x=>typeof x==='string'&&/^[a-f0-9]{64}$/.test(x);
export class TestWitness {
 constructor(path,privateKey){
  this.key=privateKey;this.db=new DatabaseSync(path);
  this.db.exec('PRAGMA journal_mode=WAL; CREATE TABLE IF NOT EXISTS consumed(scope TEXT NOT NULL, nonce TEXT NOT NULL, proposal_hash TEXT NOT NULL, sequence INTEGER NOT NULL, PRIMARY KEY(scope,nonce)); CREATE TABLE IF NOT EXISTS head(id INTEGER PRIMARY KEY CHECK(id=1), sequence INTEGER NOT NULL); INSERT OR IGNORE INTO head VALUES(1,0);');
 }
 close(){this.db.close();}
 consume({scope,nonce,proposalHash,challenge,now,failBeforeCommit=false,loseAfterCommit=false}){
  if(typeof scope!=='string'||!scope||!valid(nonce)||!valid(proposalHash)||!valid(challenge)||!Number.isSafeInteger(now))throw Error('bad request');
  this.db.exec('BEGIN IMMEDIATE');let seq;
  try {
   if(this.db.prepare('SELECT nonce FROM consumed WHERE scope=? AND nonce=?').get(scope,nonce))throw Error('already consumed');
   seq=this.db.prepare('SELECT sequence FROM head WHERE id=1').get().sequence+1;
   this.db.prepare('INSERT INTO consumed VALUES(?,?,?,?)').run(scope,nonce,proposalHash,seq);
   this.db.prepare('UPDATE head SET sequence=? WHERE id=1').run(seq);
   if(failBeforeCommit)throw Error('simulated failure');
   this.db.exec('COMMIT');
  }catch(e){this.db.exec('ROLLBACK');throw e;}
  if(loseAfterCommit)throw Error('unknown outcome');
  return this.lookup({scope,nonce,proposalHash,challenge,now});
 }
 lookup({scope,nonce,proposalHash,challenge,now}){
  if(typeof scope!=='string'||!scope||!valid(nonce)||!valid(proposalHash)||!valid(challenge)||!Number.isSafeInteger(now))throw Error('bad request');
  const row=this.db.prepare('SELECT proposal_hash,sequence FROM consumed WHERE scope=? AND nonce=?').get(scope,nonce);
  if(!row||row.proposal_hash!==proposalHash)throw Error('no matching receipt');
  const payload={v:1,scope,challenge,nonce,proposal_hash:proposalHash,sequence:row.sequence,issued:now};
  return {payload,signature:sign(null,receiptBytes(payload),this.key).toString('hex')};
 }
}
