// Candidate only. Call with server-verified identity and immutable own-record
// inventory; this validator does not authenticate or create Storage objects.
import {createHash} from 'node:crypto';
const digest=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
const day=v=>typeof v==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(v)&&!Number.isNaN(Date.parse(v+'T00:00:00Z'))&&new Date(v+'T00:00:00Z').toISOString().slice(0,10)===v;
export function planOwnArchive(context, inventory){
  if(context?.enabled!==true||context?.sessionVerified!==true||!id(context.personId)||!id(context.sourceCompanyId)||!day(context.cutoff)) throw Error('archive_context_rejected');
  if(inventory?.complete!==true||inventory.personId!==context.personId||inventory.sourceCompanyId!==context.sourceCompanyId||inventory.cutoff!==context.cutoff||!Array.isArray(inventory.records)) throw Error('archive_inventory_incomplete');
  const seen=new Set(); const records=inventory.records.map(r=>{
    if(!['own_attendance','own_payroll'].includes(r.kind)||r.personId!==context.personId||r.sourceCompanyId!==context.sourceCompanyId||!id(r.sourceId)||!id(r.revision)||!day(r.periodStart)||!day(r.periodEnd)||r.periodStart>r.periodEnd||r.periodEnd>context.cutoff||r.immutable!==true||r.finalized!==true||!/^\w{64}$/.test(r.snapshotSha256)||!/^[a-f0-9]{64}$/.test(r.snapshotSha256)) throw Error('archive_record_rejected');
    const logical=[r.kind,r.sourceId]; const logicalKey=JSON.stringify(logical);
    if(seen.has(logicalKey)) throw Error('archive_duplicate_source'); seen.add(logicalKey);
    const artifactKey=digest([1,context.personId,context.sourceCompanyId,r.kind,r.sourceId,r.revision,r.snapshotSha256]);
    return {kind:r.kind,sourceId:r.sourceId,revision:r.revision,snapshotSha256:r.snapshotSha256,periodStart:r.periodStart,periodEnd:r.periodEnd,artifactKey};
  }).sort((a,b)=>a.artifactKey.localeCompare(b.artifactKey));
  const manifest={version:1,personId:context.personId,sourceCompanyId:context.sourceCompanyId,cutoff:context.cutoff,records};
  return {...manifest,manifestHash:digest(manifest)};
}
export function verifyArchiveCompletion(plan, receipts){
  if(!plan||!Array.isArray(plan.records)||!Array.isArray(receipts)||receipts.length!==plan.records.length) throw Error('archive_not_complete');
  const expected=new Map(plan.records.map(r=>[r.artifactKey,r])); const consumed=new Set();
  for(const r of receipts){
    const source=expected.get(r.artifactKey);
    if(!source||consumed.has(r.artifactKey)||r.personId!==plan.personId||r.sourceCompanyId!==plan.sourceCompanyId||r.snapshotSha256!==source.snapshotSha256||r.status!=='verified'||r.contentType!=='application/pdf'||!Number.isSafeInteger(r.byteLength)||r.byteLength<1||!/^[a-f0-9]{64}$/.test(r.pdfSha256)||!id(r.immutableVersion)) throw Error('archive_receipt_rejected');
    consumed.add(r.artifactKey);
  }
  return {manifestHash:plan.manifestHash,complete:true,count:consumed.size};
}
