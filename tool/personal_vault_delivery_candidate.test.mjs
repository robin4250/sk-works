import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {downloadOwnVaultPdf} from './personal_vault_delivery_candidate.mjs';
const {PGlite} = await import(process.env.VAULT_PGLITE_MODULE || '@electric-sql/pglite');
const root = process.env.VAULT_FIXTURE_ROOT || 'docs/review/personal-vault24';
async function expand(name) {
 const text=await readFile(`${root}/${name}`,'utf8');let out='';
 for(const line of text.split('\n')) {if(line.startsWith('\\set')) continue;
  if(line.startsWith('\\i ')) out+=await expand(line.slice(3).replace('docs/review/personal-vault24/',''))+'\n';else out+=line+'\n';}
 return out;
}
const owner='00000000-0000-0000-0000-000000000001', other='00000000-0000-0000-0000-000000000002',sid='90000000-0000-0000-0000-000000000001',mid='10000000-0000-0000-0000-000000000001',key='a'.repeat(64),bytes=Buffer.from('%PDF-1.7\nsynthetic only\n%%EOF\n'),digest=createHash('sha256').update(bytes).digest('hex');
async function fixture(){
 const db=new PGlite();await db.exec(await expand('read-api-test.sql'));
 await db.query(`update personal_vault24_candidate.items set pdf_hash=$1,byte_length=$2 where manifest_id=$3::uuid`,[digest,bytes.length,mid]);
 await db.exec(`set fixture.live='true';set fixture.enabled='false';set fixture.actor='${owner}';set role authenticated`);
 let calls=0;
 const services={
  liveActor:async()=>{const r=await db.query('select auth.uid()::text as id'); if((await db.query("select current_setting('fixture.live') as live")).rows[0].live!=='true')throw Error('expired');return {ownerId:r.rows[0].id,sessionId:sid};},
  listMine:async()=>(await db.query('select * from public.personal_vault24_list_mine()')).rows,
  itemMine:async(m,a)=>(await db.query('select * from public.personal_vault24_item_mine($1::uuid,$2)',[m,a])).rows.map(x=>({...x,byte_length:Number(x.byte_length)})),
  storageMetadata:async(path,version)=>{const r=await db.query("select name,version from storage.objects where bucket_id='personal-pdf-vault' and name=$1 and version=$2",[path,version]);return r.rows.length===1?{objectPath:r.rows[0].name,version:r.rows[0].version,contentType:'application/pdf'}:null;},
  download:async()=>{calls++;return Buffer.from(bytes);},
  trustedPrivacyProof:async()=>({passed:true,policy:'own-snapshot-v1',ownerId:owner,manifestId:mid,artifactKey:key,kind:'own_payroll',pdfSha256:digest}),
 };
 return {db,services,calls:()=>calls};
}
test('real candidate RPC/RLS with owner and OFF gate returns verified own PDF',async()=>{const f=await fixture();try{assert.deepEqual(await downloadOwnVaultPdf({manifestId:mid,artifactKey:key},f.services),bytes);}finally{await f.db.close();}});
test('other person and expired session are rejected before bytes leave storage',async()=>{const f=await fixture();try{await f.db.exec(`set fixture.actor='${other}'`);await assert.rejects(downloadOwnVaultPdf({manifestId:mid,artifactKey:key},f.services));assert.equal(f.calls(),0);await f.db.exec(`set fixture.actor='${owner}';set fixture.live='false'`);await assert.rejects(downloadOwnVaultPdf({manifestId:mid,artifactKey:key},f.services));assert.equal(f.calls(),0);}finally{await f.db.close();}});
test('missing, forged or wrong-person privacy proof rejects before return',async()=>{const f=await fixture();try{for(const v of [null,{passed:true,policy:'own-snapshot-v1',ownerId:other,manifestId:mid,artifactKey:key,kind:'own_payroll',pdfSha256:digest}]){f.services.trustedPrivacyProof=async()=>v;await assert.rejects(downloadOwnVaultPdf({manifestId:mid,artifactKey:key},f.services));}}finally{await f.db.close();}});
test('corrupt bytes or session revoked during download cannot be returned',async()=>{const f=await fixture();try{f.services.download=async()=>Buffer.from('%PDF-1.7\nwrong value\n%%EOF\n');await assert.rejects(downloadOwnVaultPdf({manifestId:mid,artifactKey:key},f.services));f.services.download=async()=>{await f.db.exec("set fixture.live='false'");return Buffer.from(bytes);};await assert.rejects(downloadOwnVaultPdf({manifestId:mid,artifactKey:key},f.services));}finally{await f.db.close();}});

test('storage cannot mutate already checked bytes while awaiting privacy proof',async()=>{const f=await fixture();try{const shared=Buffer.from(bytes);f.services.download=async()=>shared;const original=f.services.trustedPrivacyProof;f.services.trustedPrivacyProof=async(...x)=>{shared.fill(0);return original(...x);};assert.deepEqual(await downloadOwnVaultPdf({manifestId:mid,artifactKey:key},f.services),bytes);}finally{await f.db.close();}});
