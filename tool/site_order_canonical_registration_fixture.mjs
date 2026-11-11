import fs from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
import {createCanonicalSiteOrderRenderer,registerCanonicalSiteOrderJob} from './site_order_canonical_renderer.mjs';

export async function verifyCanonicalSiteOrderRegistration(db,c) {
 const {id,A,B,UA,actor,q,prepare,preview,decide}=c;
 const executable=process.env.SKO_CANONICAL_DART;
 if(!executable)throw Error('Actual canonical Dart executable required');
 const render=await createCanonicalSiteOrderRenderer({dartExecutable:executable,repositoryRoot:process.cwd()});
 const sample=JSON.parse(await fs.readFile('tool/canonical_renderer/synthetic-evidence.json','utf8'));
 const names=await q('select jsonb_object_agg(id,name) v from public.companies');
 await actor(UA);
 const sid=await q('select id v from auth.sessions where user_id=$1',[UA]);
 await db.query("select set_config('test.jwt',$1,false)",[JSON.stringify({sub:UA,role:'authenticated',session_id:sid})]);
 await db.query("update private.master_feature_settings set enabled=true where feature_key='site_order_documents'");
 // Prior immutable fixture job must survive. A separate actual-PDF job is used.
 const doc=id(9950),request=id(9951),site=id(9301),trade=id(2100);
 const body={...sample.body,issuer_company_id:A,counterparty_company_id:B,
  issuer:{...sample.body.issuer,name:names[A]},counterparty:{...sample.body.counterparty,name:names[B]}};
 await prepare(doc,0,body);await decide(doc,1,A,await preview(doc,1,A));
 const job=await q('select site_order_artifact_private.prepare_job($1,$2,$3,1,$4,$5) v',[A,site,doc,request,trade]);
 const receipt=await registerCanonicalSiteOrderJob(db,job.job_id,render);
 const stored=Buffer.from(await q('select pdf_bytes v from site_order_artifact_private.pdf_records where job_id=$1',[job.job_id]));
 if(stored.length<10000||stored.subarray(0,5).toString()!=='%PDF-'||
  receipt.pdf_sha256!==createHash('sha256').update(stored).digest('hex'))throw Error('Actual canonical PDF not registered');
 const again=await registerCanonicalSiteOrderJob(db,job.job_id,()=>{throw Error('Existing original must not regenerate');});
 if(JSON.stringify(again)!==JSON.stringify(receipt))throw Error('Original retry receipt changed');
 if(process.env.SKO_CANONICAL_PDF_OUTPUT_DIR){
  const folder=resolve(process.env.SKO_CANONICAL_PDF_OUTPUT_DIR);await fs.mkdir(folder,{recursive:true});
  await fs.writeFile(resolve(folder,'registered-order.pdf'),stored);
 }
 // Changing a draft after a job was prepared must block its FIRST registration.
 // An existing original stays readable by its exact historical receipt.
 await prepare(doc,1,{...body,work_name:'変更後の合成工事'});
 const archived=await registerCanonicalSiteOrderJob(db,job.job_id,()=>{throw Error('No historical regeneration');});
 if(JSON.stringify(archived)!==JSON.stringify(receipt))throw Error('Historical original receipt changed');
 const changedDoc=id(9960);
 await prepare(changedDoc,0,body);await decide(changedDoc,1,A,await preview(changedDoc,1,A));
 const stale=await q('select site_order_artifact_private.prepare_job($1,$2,$3,1,$4,$5) v',[A,site,changedDoc,id(9961),trade]);
 await prepare(changedDoc,1,{...body,work_name:'確定前に変更された本文'});
 let staleDenied=false;
 try{await q('select site_order_artifact_private.register_canonical_pdf($1,$2) v',[stale.job_id,Buffer.from('%PDF-1.7\nnever-an-approved-new-original\n%%EOF')]);}
 catch(error){staleDenied=/approved document revision/.test(error.message);}
 if(!staleDenied)throw Error('RED: stale unregistered job accepted after current document revision changed');
 if(await q('select count(*)::int v from site_order_artifact_private.pdf_records where job_id=$1',[stale.job_id])!==0)throw Error('Stale job created an original');
 console.log('PASS first registration current-revision CAS and existing historical receipt retained');
 await db.query("update private.master_feature_settings set enabled=false where feature_key='site_order_documents'");
 let denied=false;try{await registerCanonicalSiteOrderJob(db,job.job_id,render);}catch(e){denied=e.message==='canonical_registration_rejected';}
 if(!denied)throw Error('OFF must reject exact retry without returning PDF');
 console.log('PASS actual pure-Dart canonical PDF -> private DB original/receipt; immutable retry; OFF recheck');
}
