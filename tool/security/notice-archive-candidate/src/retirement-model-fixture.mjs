// TEST-ONLY model: no DB, network, production keys, authority or deletion.
// This deliberately does NOT implement authorization or genuine archive trust.
// It illustrates atomic snapshot matching, history retention, and retry rules.
import {createHash} from 'node:crypto';
const digest=x=>createHash('sha256').update(JSON.stringify(x)).digest('hex');
const clone=x=>structuredClone(x);
const uuid=x=>typeof x==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(x);
function validSnapshot(s){
 if(!s||!uuid(s.event_id)||!uuid(s.company_id)||!uuid(s.recipient_id)||!uuid(s.collector_id)||!Number.isSafeInteger(s.revision)||s.revision<2||!['resolved','false_positive'].includes(s.state)||!Number.isSafeInteger(s.reviewed_at)||!Number.isSafeInteger(s.received_at)||!Array.isArray(s.audit)||s.audit.length<1||s.audit.length>20||!s.evidence||typeof s.evidence!=='object')throw Error('source snapshot rejected');
 const commands=new Set();let rev=1;
 for(const a of s.audit){
  if(!uuid(a.command_id)||commands.has(a.command_id)||a.before_revision!==rev||a.after_revision!==rev+1||!uuid(a.actor_id)||!uuid(a.session_id)||!['read','investigating','resolved','false_positive'].includes(a.action)||typeof a.reason!=='string'||(a.action==='read'?a.reason!=='':!a.reason.trim())||!Number.isSafeInteger(a.occurred_at))throw Error('audit history rejected');
  commands.add(a.command_id);rev=a.after_revision;
 }
 if(rev!==s.revision||s.audit.at(-1).action!==s.state||s.audit.at(-1).occurred_at!==s.reviewed_at)throw Error('source revision mismatch');
 return s;
}
export class RetirementFixture {
 constructor(retentionMs){if(!Number.isSafeInteger(retentionMs)||retentionMs<7*86400000)throw Error('minimum retention');this.retentionMs=retentionMs;this.live=new Map();this.history=new Map();this.tombstones=new Map();}
 insert(snapshot){validSnapshot(snapshot);if(this.live.has(snapshot.event_id)||this.history.has(snapshot.event_id))throw Error('duplicate event');this.live.set(snapshot.event_id,clone(snapshot));}
 prepare(id,now){const s=validSnapshot(this.live.get(id));if(!Number.isSafeInteger(now)||now-s.reviewed_at<this.retentionMs||now-s.received_at<this.retentionMs)throw Error('retention not satisfied');return {snapshot:clone(s),snapshot_hash:digest(s)};}
 // `archive` is only a fixture marker. A real independent store, source MAC
 // verification, fresh authority, encrypted original and signed receipt must
 // all be enforced by a future trusted implementation before any real purge.
 retire(prepared,archive,{failBeforeCommit=false}={}){
  if(!prepared||!archive||archive.fixture_only!==true||archive.snapshot_hash!==prepared.snapshot_hash||digest(prepared.snapshot)!==prepared.snapshot_hash)throw Error('fixture archive mismatch');
  const id=prepared.snapshot.event_id,prior=this.tombstones.get(id);
  if(prior){if(prior!==prepared.snapshot_hash)throw Error('retirement retry conflict');return {replayed:true};}
  const current=validSnapshot(this.live.get(id));if(digest(current)!==prepared.snapshot_hash)throw Error('source changed');
  const nextLive=new Map(this.live),nextHistory=new Map(this.history),nextTombstones=new Map(this.tombstones);
  nextHistory.set(id,clone(prepared.snapshot));nextTombstones.set(id,prepared.snapshot_hash);nextLive.delete(id);
  if(failBeforeCommit)throw Error('fixture failure');
  this.live=nextLive;this.history=nextHistory;this.tombstones=nextTombstones;return {replayed:false};
 }
 read(id,company,recipient){const s=this.live.get(id)??this.history.get(id);if(!s||s.company_id!==company||s.recipient_id!==recipient)throw Error('not found');return clone(s);}
 retryCommand(id,company,recipient,command){const s=this.read(id,company,recipient),a=s.audit.find(x=>x.command_id===command.command_id);if(!a||digest(a)!==digest(command))throw Error('command conflict');return {replayed:true,revision:a.after_revision};}
}
