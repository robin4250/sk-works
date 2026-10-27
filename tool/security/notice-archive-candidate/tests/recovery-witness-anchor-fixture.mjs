// Test-only SQLite model; the independently held checkpoint is an input.
// There is no external host, authentication, real clock, or recovery route.
import {DatabaseSync} from 'node:sqlite';
import {createHash} from 'node:crypto';
const zero='0'.repeat(64);
const valid=x=>typeof x==='string'&&/^[a-f0-9]{64}$/.test(x);
export class AnchoredWitnessFixture {
 constructor(path){this.db=new DatabaseSync(path);this.db.exec(`PRAGMA journal_mode=WAL;
 CREATE TABLE IF NOT EXISTS ledger(scope TEXT NOT NULL, nonce TEXT NOT NULL, proposal_hash TEXT NOT NULL, seq INTEGER NOT NULL, hash TEXT NOT NULL, PRIMARY KEY(scope,nonce));
 CREATE TABLE IF NOT EXISTS state(id INTEGER PRIMARY KEY CHECK(id=1),seq INTEGER NOT NULL,hash TEXT NOT NULL);
 INSERT OR IGNORE INTO state VALUES(1,0,'${zero}');`);}
 close(){this.db.close();}
 head(){return this.db.prepare('SELECT seq, hash FROM state WHERE id=1').get();}
 consume({scope,nonce,proposalHash,expected}){
  if(typeof scope!=='string'||!scope||!valid(nonce)||!valid(proposalHash)||!expected||!Number.isSafeInteger(expected.seq)||expected.seq<0||!valid(expected.hash))throw Error('invalid request');
  this.db.exec('BEGIN IMMEDIATE');try{
   const old=this.head();if(old.seq!==expected.seq||old.hash!==expected.hash)throw Error('witness checkpoint mismatch');
   if(this.db.prepare('SELECT nonce FROM ledger WHERE scope=? AND nonce=?').get(scope,nonce))throw Error('already consumed');
   const seq=old.seq+1,hash=createHash('sha256').update(JSON.stringify({v:1,previous:old.hash,seq,scope,nonce,proposalHash})).digest('hex');
   this.db.prepare('INSERT INTO ledger VALUES(?,?,?,?,?)').run(scope,nonce,proposalHash,seq,hash);
   this.db.prepare('UPDATE state SET seq=?,hash=? WHERE id=1').run(seq,hash);
   this.db.exec('COMMIT');return {seq,hash};
  }catch(error){this.db.exec('ROLLBACK');throw error;}
 }
}
