// Review only. Local create-only byte retention is NOT independent custody,
// immutable/WORM storage, source authenticity, or permission to release a pin.
import * as fs from 'node:fs/promises';
import {constants} from 'node:fs';
import {createHash,randomUUID} from 'node:crypto';
import {join,resolve} from 'node:path';

const MAX_PAYLOAD=64*1024,MAX_OBJECT=96*1024;
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const hash=x=>typeof x==='string'&&/^[a-f0-9]{64}$/.test(x);
const uuid=x=>typeof x==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(x);
const fail=()=>Error('archive byte custody unavailable');
const bindingFields=['company_id','event_id','revision','snapshot_sha256','payload_sha256'];
function own(value,fields){
 if(!value||typeof value!=='object'||![Object.prototype,null].includes(Object.getPrototypeOf(value)))throw fail();
 const descriptors=Object.getOwnPropertyDescriptors(value);
 if(Reflect.ownKeys(descriptors).length!==fields.length||fields.some(k=>!Object.hasOwn(descriptors,k)||!Object.hasOwn(descriptors[k],'value')))throw fail();
 return Object.fromEntries(fields.map(k=>[k,descriptors[k].value]));
}
function binding(value){
 const b=own(value,bindingFields);
 if(!uuid(b.company_id)||!uuid(b.event_id)||!Number.isSafeInteger(b.revision)||b.revision<1||!hash(b.snapshot_sha256)||!hash(b.payload_sha256))throw fail();
 return b;
}
function descriptor(value){
 const d=own(value,['status','schema',...bindingFields,'byte_length','object_id']);
 if(d.status!=='stored_unattested'||d.schema!==1||!hash(d.object_id)||!Number.isSafeInteger(d.byte_length)||d.byte_length<1||d.byte_length>MAX_PAYLOAD)throw fail();
 binding(Object.fromEntries(bindingFields.map(k=>[k,d[k]])));
 return Object.freeze(d);
}
function encoded(b,payload){return Buffer.from(JSON.stringify({schema:1,...b,payload_base64:payload.toString('base64')}));}

// Pure binding checks for a separately configured readback attestor. A valid
// descriptor or byte hash does not establish source authenticity or custody.
export function snapshotArchiveByteDescriptorCandidate(expected){return descriptor(expected);}
export function verifyArchiveByteReadbackCandidate(expected,bytes){
 const d=descriptor(expected);
 if(!(bytes instanceof Uint8Array)||bytes.length!==d.byte_length)throw fail();
 const payload=Buffer.from(bytes),b=Object.fromEntries(bindingFields.map(k=>[k,d[k]]));
 if(sha(payload)!==d.payload_sha256||sha(encoded(b,payload))!==d.object_id)throw fail();
 return d;
}

// `directory` and IO are trusted deployment configuration, never request input.
// The directory must already exist, be private and remain protected from rename
// and operator mutation. No namespace is created or production path selected.
export async function createArchiveByteStoreCandidate({enabled=false,directory,io=fs}={}){
 if(!enabled||typeof directory!=='string'||!directory||typeof process.getuid!=='function')throw fail();
 const ops=Object.fromEntries(['open','lstat','realpath','link','unlink'].map(k=>{
  if(typeof io[k]!=='function')throw fail();return [k,io[k].bind(io)];
 }));
 const root=resolve(directory);
 try{
  const stat=await ops.lstat(root);
  if(!stat.isDirectory()||stat.isSymbolicLink()||(stat.mode&0o077)!==0||stat.uid!==process.getuid()||await ops.realpath(root)!==root)throw fail();
 }catch{throw fail();}
 async function directorySync(){
  const handle=await ops.open(root,constants.O_RDONLY|constants.O_DIRECTORY|constants.O_NOFOLLOW);
  try{await handle.sync();}finally{await handle.close();}
 }
 async function readExact(d){
  let handle;
  try{
   handle=await ops.open(join(root,`${d.object_id}.archive`),constants.O_RDONLY|constants.O_NOFOLLOW);
   const before=await handle.stat();
   if(!before.isFile()||before.size<1||before.size>MAX_OBJECT||(before.mode&0o077)!==0||before.uid!==process.getuid())throw fail();
   const bytes=Buffer.alloc(before.size+1);let offset=0;
   while(offset<bytes.length){const {bytesRead}=await handle.read(bytes,offset,bytes.length-offset,offset);if(!bytesRead)break;offset+=bytesRead;}
   const after=await handle.stat();
   // ctime also changes when a concurrently published temporary hardlink is
   // removed. Bind content by size/mtime and the full expected SHA instead.
   if(offset!==before.size||after.size!==before.size||after.mtimeMs!==before.mtimeMs||(after.mode&0o077)!==0||after.uid!==before.uid)throw fail();
   const content=bytes.subarray(0,offset);
   if(sha(content)!==d.object_id)throw fail();
   const record=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(content));
   const fields=own(record,['schema',...bindingFields,'payload_base64']);
   if(fields.schema!==1||bindingFields.some(k=>fields[k]!==d[k])||typeof fields.payload_base64!=='string')throw fail();
   const payload=Buffer.from(fields.payload_base64,'base64');
   if(payload.length!==d.byte_length||payload.toString('base64')!==fields.payload_base64||sha(payload)!==d.payload_sha256||!encoded(Object.fromEntries(bindingFields.map(k=>[k,d[k]])),payload).equals(content))throw fail();
   return payload;
  }catch{throw fail();}finally{if(handle)await handle.close();}
 }
 return Object.freeze({
  async retain(input){
   // Snapshot metadata and bytes before the first await; never follow a mutable
   // caller's expected digest, scope or payload while the write is in flight.
   let temp,handle;
   try{
    const source=own(input,[...bindingFields,'payload']);
    const b=binding(Object.fromEntries(bindingFields.map(k=>[k,source[k]])));
    if(!(source.payload instanceof Uint8Array)||source.payload.length<1||source.payload.length>MAX_PAYLOAD)throw fail();
    const payload=Buffer.from(source.payload);
    if(sha(payload)!==b.payload_sha256)throw fail();
    const bytes=encoded(b,payload),d=descriptor({status:'stored_unattested',schema:1,...b,byte_length:payload.length,object_id:sha(bytes)});
    temp=join(root,`.pending-${randomUUID()}`);
    handle=await ops.open(temp,constants.O_CREAT|constants.O_EXCL|constants.O_WRONLY|constants.O_NOFOLLOW,0o600);
    await handle.writeFile(bytes);await handle.sync();await handle.close();handle=null;
    // link is create-only: an existing name is never replaced (unlike rename).
    try{await ops.link(temp,join(root,`${d.object_id}.archive`));}
    catch(error){if(error?.code!=='EEXIST')throw error;}
    await readExact(d);
    await ops.unlink(temp);temp=null;
    await directorySync();
    return d;
   }catch{throw fail();}finally{
    if(handle)await handle.close().catch(()=>{});
    // Only this invocation's random temporary name is cleaned up. Published
    // originals are never removed, including an uncertain directory sync.
    if(temp)await ops.unlink(temp).catch(()=>{});
   }
  },
  async restore(expected){
   try{return await readExact(descriptor(expected));}catch{throw fail();}
  },
 });
}
