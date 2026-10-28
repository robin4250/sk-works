import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {downloadOwnVaultPdf} from './personal_vault_delivery_candidate.mjs';
import {createVaultStorageDownload} from './storage_download_transport.mjs';
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
 await db.exec(await readFile(process.env.VAULT_SOURCE_BINDING_SQL || 'docs/review/personal-vault25-delivery/source-binding.sql.review-only','utf8'));
 await db.query(`update personal_vault24_candidate.items set pdf_hash=$1,byte_length=$2 where manifest_id=$3::uuid`,[digest,bytes.length,mid]);
 await db.exec(`set fixture.live='true';set fixture.enabled='false';set fixture.actor='${owner}';set role authenticated`);
 let calls=0;
 const services={
  liveActor:async()=>{const r=await db.query('select auth.uid()::text as id'); if((await db.query("select current_setting('fixture.live') as live")).rows[0].live!=='true')throw Error('expired');return {ownerId:r.rows[0].id,sessionId:sid};},
  listMine:async()=>(await db.query('select * from public.personal_vault24_list_mine()')).rows,
  sourceMine:async(m,a)=>(await db.query('select * from public.personal_vault25_source_mine($1::uuid,$2)',[m,a])).rows,
  itemMine:async(m,a)=>(await db.query('select * from public.personal_vault24_item_mine($1::uuid,$2)',[m,a])).rows.map(x=>({...x,byte_length:Number(x.byte_length)})),
  storageMetadata:async(path,version)=>{const r=await db.query("select name,version from storage.objects where bucket_id='personal-pdf-vault' and name=$1 and version=$2",[path,version]);return r.rows.length===1?{objectPath:r.rows[0].name,version:r.rows[0].version,contentType:'application/pdf',byteLength:bytes.length}:null;},
  download:async()=>{calls++;return Buffer.from(bytes);},
  trustedPrivacyProof:async()=>({passed:true,policy:'own-snapshot-v2',sourceBinding:(await services.sourceMine(mid,key))[0],ownerId:owner,manifestId:mid,artifactKey:key,kind:'own_payroll',pdfSha256:digest}),
 };
 return {db,services,calls:()=>calls};
}
test('real candidate RPC/RLS with owner and OFF gate returns verified own PDF',async()=>{const f=await fixture();try{assert.deepEqual(await downloadOwnVaultPdf({manifestId:mid,artifactKey:key},f.services),bytes);}finally{await f.db.close();}});
test('other person and expired session are rejected before bytes leave storage',async()=>{const f=await fixture();try{await f.db.exec(`set fixture.actor='${other}'`);await assert.rejects(downloadOwnVaultPdf({manifestId:mid,artifactKey:key},f.services));assert.equal(f.calls(),0);await f.db.exec(`set fixture.actor='${owner}';set fixture.live='false'`);await assert.rejects(downloadOwnVaultPdf({manifestId:mid,artifactKey:key},f.services));assert.equal(f.calls(),0);}finally{await f.db.close();}});
test('missing, forged or wrong-person privacy proof rejects before return',async()=>{const f=await fixture();try{for(const v of [null,{passed:true,policy:'own-snapshot-v1',ownerId:other,manifestId:mid,artifactKey:key,kind:'own_payroll',pdfSha256:digest}]){f.services.trustedPrivacyProof=async()=>v;await assert.rejects(downloadOwnVaultPdf({manifestId:mid,artifactKey:key},f.services));}}finally{await f.db.close();}});
test('corrupt bytes or session revoked during download cannot be returned',async()=>{const f=await fixture();try{f.services.download=async()=>Buffer.from('%PDF-1.7\nwrong value\n%%EOF\n');await assert.rejects(downloadOwnVaultPdf({manifestId:mid,artifactKey:key},f.services));f.services.download=async()=>{await f.db.exec("set fixture.live='false'");return Buffer.from(bytes);};await assert.rejects(downloadOwnVaultPdf({manifestId:mid,artifactKey:key},f.services));}finally{await f.db.close();}});

test('storage cannot mutate already checked bytes while awaiting privacy proof',async()=>{const f=await fixture();try{const shared=Buffer.from(bytes);f.services.download=async()=>shared;const original=f.services.trustedPrivacyProof;f.services.trustedPrivacyProof=async(...x)=>{shared.fill(0);return original(...x);};assert.deepEqual(await downloadOwnVaultPdf({manifestId:mid,artifactKey:key},f.services),bytes);}finally{await f.db.close();}});

test('oversized receipt and mismatched storage size are rejected before download',async()=>{const f=await fixture();try{const original=f.services.itemMine;f.services.itemMine=async(...x)=>(await original(...x)).map(row=>({...row,byte_length:50*1024*1024+1}));await assert.rejects(downloadOwnVaultPdf({manifestId:mid,artifactKey:key},f.services));assert.equal(f.calls(),0);f.services.itemMine=original;const meta=f.services.storageMetadata;f.services.storageMetadata=async(...x)=>({...await meta(...x),byteLength:bytes.length+1});await assert.rejects(downloadOwnVaultPdf({manifestId:mid,artifactKey:key},f.services));assert.equal(f.calls(),0);}finally{await f.db.close();}});
test('download adapter receives strict byte cap and changed metadata rejects delivery',async()=>{const f=await fixture();try{let limit;f.services.download=async(_path,_version,opts)=>{limit=opts.maxBytes;return Buffer.from(bytes)};assert.deepEqual(await downloadOwnVaultPdf({manifestId:mid,artifactKey:key},f.services),bytes);assert.equal(limit,bytes.length);let calls=0;const meta=f.services.storageMetadata;f.services.storageMetadata=async(...x)=>{const result=await meta(...x);return {...result,byteLength:++calls===1?bytes.length:bytes.length+1}};await assert.rejects(downloadOwnVaultPdf({manifestId:mid,artifactKey:key},f.services));}finally{await f.db.close();}});

test('downloaded buffers with an unexpected size are rejected before privacy inspection',async()=>{const f=await fixture();try{let inspected=0;f.services.trustedPrivacyProof=async()=>{inspected++;throw Error('unexpected inspection')};for(const size of [bytes.length-1,bytes.length+1]){f.services.download=async()=>Buffer.alloc(size);await assert.rejects(downloadOwnVaultPdf({manifestId:mid,artifactKey:key},f.services),/vault_download_invalid/);}assert.equal(inspected,0);}finally{await f.db.close();}});

test('coordinator passes trusted receipt hash to bounded private Storage GET',async()=>{
  const f=await fixture();try{
    let calls=0;
    f.services.download=createVaultStorageDownload({origin:'https://synthetic.supabase.co',
      bucket:'personal-documents',publishableKey:'sb_publishable_fixture',
      authorizationHeader:async()=> 'Bearer synthetic.jwt.fixture',fetchImpl:async()=>{
        calls++;return new Response(bytes,{headers:{'content-type':'application/pdf'}});
      }});
    assert.deepEqual(await downloadOwnVaultPdf({manifestId:mid,artifactKey:key},f.services),bytes);
    assert.equal(calls,1);
  }finally{await f.db.close();}
});

test('privacy proof must bind the exact saved source snapshot and revision',async()=>{
 const f=await fixture();try{
  const original=f.services.trustedPrivacyProof;
  for(const field of ['source_company_id','source_worker_id','source_id','source_revision','snapshot_hash','manifest_hash','kind']) {
   f.services.trustedPrivacyProof=async()=>{const proof=await original();return {...proof,sourceBinding:{...proof.sourceBinding,[field]:'different'}}};
   await assert.rejects(downloadOwnVaultPdf({manifestId:mid,artifactKey:key},f.services),/vault_privacy_proof_rejected/);
  }
  f.services.trustedPrivacyProof=async()=>({...await original(),policy:'own-snapshot-v1'});
  await assert.rejects(downloadOwnVaultPdf({manifestId:mid,artifactKey:key},f.services),/vault_privacy_proof_rejected/);
 }finally{await f.db.close();}
});
test('catalog source binding changes during inspection reject delivery',async()=>{
 const f=await fixture();try{
  const original=f.services.sourceMine;let count=0;
  f.services.sourceMine=async(...args)=>{const rows=await original(...args);count++;return rows.map(row=>({...row,source_revision:count<3?row.source_revision:'new-revision'}))};
  await assert.rejects(downloadOwnVaultPdf({manifestId:mid,artifactKey:key},f.services),/vault_source_changed/);
 }finally{await f.db.close();}
});
test('source binding RPC rejects foreign and expired sessions and anonymous ACL',async()=>{
 const f=await fixture();try{
  await f.db.exec(`set fixture.actor='${other}'`);
  await assert.rejects(f.services.sourceMine(mid,key),/vault_owner_rejected/);
  await f.db.exec(`set fixture.actor='${owner}';set fixture.live='false'`);
  await assert.rejects(f.services.sourceMine(mid,key));
  await f.db.exec('reset role');
  const privileges=await f.db.query("select has_function_privilege('anon','public.personal_vault25_source_mine(uuid,text)','EXECUTE') as anon,has_function_privilege('service_role','public.personal_vault25_source_mine(uuid,text)','EXECUTE') as service");
  assert.equal(privileges.rows[0].anon,false);assert.equal(privileges.rows[0].service,false);
 }finally{await f.db.close();}
});

test('receipt and metadata returned by adapters are detached before download awaits',async()=>{
 const f=await fixture();try{
  const row=(await f.services.itemMine(mid,key))[0];
  const object=await f.services.storageMetadata(row.object_path,row.object_version);
  const substituted=Buffer.from('%PDF-1.7\nsubstituted only\n%%EOF\n');
  f.services.itemMine=async()=>[row];
  f.services.storageMetadata=async()=>object;
  f.services.download=async()=>{
   row.pdf_hash=createHash('sha256').update(substituted).digest('hex');
   row.byte_length=substituted.length;object.byteLength=substituted.length;
   return substituted;
  };
  const inspect=f.services.trustedPrivacyProof;
  f.services.trustedPrivacyProof=async()=>({...await inspect(),pdfSha256:row.pdf_hash});
  // Neither the initial expected length nor digest may follow mutation.
  await assert.rejects(downloadOwnVaultPdf({manifestId:mid,artifactKey:key},f.services),/vault_download_invalid|vault_pdf_digest_mismatch/);
 }finally{await f.db.close();}
});
