import {createHash} from 'node:crypto';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const maxBytes=20*1024*1024;
const isUuid=value=>typeof value==='string'&&uuid.test(value);

// The parser is the existing createDocumentFileValidator({sharp,pdfjs}). A
// trusted immutable reader and transaction-bound DB adapter are still required.
export function createQualificationUploadInspector({verifySession,db,storage,validateFile}){
 if(typeof verifySession!=='function'||typeof validateFile!=='function'||!db||!storage)throw Error('inspection_unavailable');
 return async function inspect({bearerToken,requestId,slotId}){
  if(typeof bearerToken!=='string'||!bearerToken||!isUuid(requestId)||!isUuid(slotId))throw Error('inspection_unavailable');
  const verifiedSession=await verifySession(bearerToken);
  const session=verifiedSession&&typeof verifiedSession==='object'?Object.freeze({...verifiedSession}):null;
  if(!session||session.active!==true||session.anonymous!==false||!isUuid(session.actorId)||!isUuid(session.sessionId))throw Error('inspection_unavailable');
  const pending=await db.authorizedPendingSlot({actorId:session.actorId,sessionId:session.sessionId,requestId,slotId});
  const p=pending&&typeof pending==='object'?Object.freeze({...pending}):null;
  if(!p||p.contract!=='qualification_management_upload_v1'||p.requestId!==requestId||p.slotId!==slotId||p.actorId!==session.actorId||p.sessionId!==session.sessionId||p.state!=='prepared')throw Error('inspection_unavailable');
  for(const key of ['companyId','workerId','qualificationMasterId','targetId','objectId'])if(!isUuid(p[key]))throw Error('inspection_unavailable');
  const prefix=`${p.companyId}/${p.workerId}/${p.targetId}/management/${requestId}/`;
  if(p.bucket!=='qualification-certificates'||typeof p.path!=='string'||p.path.length>1024||!p.path.startsWith(prefix)||p.path.length===prefix.length||p.path.includes('..')||p.path.includes('\\')||p.path.includes('//')||typeof p.objectVersion!=='string'||!p.objectVersion||p.objectVersion.length>256)throw Error('inspection_unavailable');
  const o=await storage.readImmutableVersion({bucket:p.bucket,path:p.path,objectId:p.objectId,version:p.objectVersion,maxBytes});
  if(!o||o.objectId!==p.objectId||o.version!==p.objectVersion||!(o.bytes instanceof Uint8Array)||o.bytes.length<8||o.bytes.length>maxBytes)throw Error('invalid_file');
  const bytes=Uint8Array.from(o.bytes),ascii=(a,b)=>String.fromCharCode(...bytes.slice(a,b));
  const mime=ascii(0,5)==='%PDF-'?'application/pdf':bytes[0]===255&&bytes[1]===216&&bytes[2]===255?'image/jpeg':[137,80,78,71,13,10,26,10].every((v,i)=>bytes[i]===v)?'image/png':ascii(4,8)==='ftyp'&&['heic','heix','hevc','hevx','mif1','msf1'].includes(ascii(8,12))?'image/heic':null;
  if(!mime||mime!==p.mime||bytes.length!==p.declaredBytes)throw Error('invalid_file');
  const sha256=createHash('sha256').update(bytes).digest('hex');
  if(typeof p.declaredSha256!=='string'||p.declaredSha256!==sha256)throw Error('invalid_file');
  if(await validateFile({bytes,mime})!==true||createHash('sha256').update(bytes).digest('hex')!==sha256||!(o.bytes instanceof Uint8Array)||o.bytes.length!==bytes.length||createHash('sha256').update(o.bytes).digest('hex')!==sha256||o.objectId!==p.objectId||o.version!==p.objectVersion)throw Error('invalid_file');
  const proof={contract:p.contract,companyId:p.companyId,workerId:p.workerId,qualificationMasterId:p.qualificationMasterId,targetId:p.targetId,actorId:p.actorId,sessionId:p.sessionId,requestId,slotId,bucket:p.bucket,path:p.path,objectId:p.objectId,objectVersion:p.objectVersion,mime,bytes:bytes.length,sha256};
  if(await db.commitReceiptAtomically({proof,expectedState:'prepared'})!==true)throw Error('inspection_conflict');
  return {inspected:true,requestId,slotId};
 };
}
