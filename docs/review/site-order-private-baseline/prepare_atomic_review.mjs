// Offline only. This emits a blocked review bundle; it never connects to any DB.
import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {transactionBody} from './sql_transaction.mjs';
const sha=s=>createHash('sha256').update(s).digest('hex');
const literal=s=>"'"+s.replaceAll("'","''")+"'";
export const siteSources=['docs/review/site-order-artifact-registration/private-register.sql.review-only','docs/review/site-order-manager-purpose/adapter.sql.review-only',...['foundation','legacy-response-guard','approval','approval-consent','archive-read','delivery','read-surfaces','archive-payload','approval-operation','refusal'].map(n=>'docs/review/site-order-package-flow/'+n+'.sql.review-only')];
export const newSchemas=['trade_document_consent_private','trade_document_confirmation_api_private','site_order_artifact_private','site_order_manager_private','site_order_package_private'];
export const replyRecoveryContract={head:'de4d4bb018e8c8ca56b0c85bde09fadebca312a4',path:'docs/review/site-order-package-flow/reply-recovery.sql.review-only',sha256:'991281df5f789e1e6a3d469dd854609a065d2a6d56db33b85a08d3cf57fd9979'};
export async function loadReplyRecovery(root){
 if(!root)return null;
 if(!path.isAbsolute(root))throw Error('reply_source_absolute_root_required');
 const sql=await fs.readFile(path.join(root,replyRecoveryContract.path),'utf8');
 if(sha(sql)!==replyRecoveryContract.sha256)throw Error('reply_recovery_source_drift');
 transactionBody(sql);return {sql,...replyRecoveryContract};
}
export const siteHistoryContract={head:'f4c6da47e8c6bd894c920ab1d85399a4dc5da7bb',path:'docs/review/site-order-package-flow/site-history.sql.review-only',sha256:'0f9cc2f094e8146089a8cdf89f10fb0244ce5d80da239497b76d5c602285e577'};
export async function loadSiteHistory(root){
 if(!root)return null;
 if(!path.isAbsolute(root))throw Error('history_source_absolute_root_required');
 const sql=await fs.readFile(path.join(root,siteHistoryContract.path),'utf8');
 if(sha(sql)!==siteHistoryContract.sha256)throw Error('site_history_source_drift');
 transactionBody(sql);return {sql,...siteHistoryContract};
}
export function legacyCaptureSql(){return "create temporary table site_order_legacy_expected(signature text primary key,attrs jsonb) on commit drop;insert into site_order_legacy_expected select case when p.oid='private.respond_site_share(uuid,boolean)'::regprocedure then 'private.respond_site_share(uuid,boolean)' else 'public.respond_site_share(uuid,boolean)'end,to_jsonb(p)-'prosrc' from pg_proc p where p.oid in('private.respond_site_share(uuid,boolean)'::regprocedure,'public.respond_site_share(uuid,boolean)'::regprocedure);";}
export function catalogSql(source,schemas){
 if(!source.includes('$1::text[]'))throw Error('catalog_schema_parameter_missing');
 return source.trim().replace(/;$/,'').replaceAll('$1::text[]','array['+schemas.map(literal).join(',')+']::text[]');
}
export function assertReceipts(before,after,hashes,manifest){
 if(!manifest?.existing_function_contracts||!manifest?.existing_relation_names||!manifest?.full_existing_contract)throw Error('pinned_existing_inventory_required');
 if(before?.kind!=='native-production-readonly-normalized-v1'||before.production_mutation!==false||!before.snapshot)throw Error('fresh_readonly_native_before_required');
 const functions=before.snapshot.functions??{},relations=before.snapshot.relations??{};
 const required=[...manifest.existing_function_contracts.map(f=>f.signature.split('(')[0]),...manifest.full_existing_contract.additional_function_names];
 if(JSON.stringify(Object.keys(functions).map(n=>n.split('(')[0]).sort())!==JSON.stringify(required.sort()))throw Error('complete_thirteen_function_before_required');
 if(JSON.stringify(Object.keys(relations).sort())!==JSON.stringify([...manifest.existing_relation_names,...manifest.full_existing_contract.additional_relation_names].sort()))throw Error('complete_fifteen_relation_before_required');
 for(const f of manifest.existing_function_contracts){
  const actual=Object.entries(functions).find(([n])=>n.split('(')[0]===f.signature.split('(')[0])[1];
  if(actual.source_md5!==f.source_md5)throw Error('current_helper_body_drift');
  const acl=f.acl.map(a=>[a.grantor,a.grantee,a.privilege,a.grant_option]);
  if(actual.owner!==f.owner||actual.prosecdef!==f.security_definer||actual.provolatile!==f.volatility||JSON.stringify(actual.proconfig)!==JSON.stringify(f.config)||JSON.stringify([...(actual.acl??[])].sort())!==JSON.stringify(acl.sort()))throw Error('current_helper_attributes_or_acl_drift');
 }
 const legacy=manifest.full_existing_contract.intended_legacy_change;
 const expectedFunctions=structuredClone(functions);
 for(const [name,f]of Object.entries(expectedFunctions)){
  if(name.split('(')[0]===legacy.function_name){if(f.source_md5!==legacy.before_md5)throw Error('legacy_before_body_changed');f.source_md5=legacy.after_md5;}
  if(name.split('(')[0]==='public.respond_site_share'&&f.source_md5!==legacy.public_wrapper_before_and_after_md5)throw Error('legacy_public_body_changed');
 }
 if(after?.kind!=='native-rehearsal-exact-current-helpers-v1'||after.synthetic_seal!==false||after.current_helper_bodies!==8||after.original_c_sha256!=='7796c2e7bcc7a9eca78f1b79ce8cfc87fcd978c1dc4a4ddb7a5a8ced17b597e5')throw Error('native_exact_eight_body_rehearsal_required');
 if(JSON.stringify(after.source_sha256)!==JSON.stringify(hashes))throw Error('rehearsal_source_mismatch');
 if(JSON.stringify(after.existing_after?.functions)!==JSON.stringify(expectedFunctions)||JSON.stringify(after.existing_after?.default_acls)!==JSON.stringify(before.snapshot.default_acls)||JSON.stringify(after.existing_after?.namespaces)!==JSON.stringify(before.snapshot.namespaces))throw Error('existing_function_or_acl_changed');
 if(!/^17[0-9]{4}$/.test(before.server_version_num??'')||after.server_version_num!==before.server_version_num)throw Error('matching_native_pg17_version_required');
 if(after.before_sha256!==sha(JSON.stringify(before.snapshot)))throw Error('rehearsal_before_mismatch');
 if(!after.existing_after||!after.new_after)throw Error('full_after_catalogs_required');
 if(newSchemas.some(n=>(before.new_namespace_presence??{})[n]!==false))throw Error('all_new_namespaces_must_be_absent');
 if(JSON.stringify(after.new_after.namespaces?.map(n=>n.name).sort())!==JSON.stringify([...newSchemas].sort()))throw Error('all_five_after_namespaces_required');
 return true;
}
export function equalityGuard(query,expected,label){
 const payload=JSON.stringify(expected);let index=0,tag;
 do{tag='$sko_guard_'+sha(query+payload+label+index++).slice(0,24)+'$';}while((query+payload+label).includes(tag));
 return `do ${tag} declare actual jsonb; begin select v into actual from (${query}) captured; if actual is distinct from ${literal(payload)}::jsonb then raise exception using errcode='55000',message=${literal(label)};end if;end ${tag};`;
}
export async function prepare(root,{before,after,replyRecoveryRoot,siteHistoryRoot}={}){
 const read=p=>fs.readFile(path.join(root,p),'utf8');
 const manifest=JSON.parse(await read('docs/review/site-order-private-baseline/manifest.json'));
 manifest.full_existing_contract=JSON.parse(await read('docs/review/site-order-private-baseline/full-existing-contract.json'));
 const core='docs/candidates/trade_document_bound_seal_consent_20261021.sql.review-only',api='docs/candidates/trade_document_confirmation_api_20261022.sql.review-only';
 const sources=await Promise.all([core,...siteSources].map(read));
 const apiText=await read(api),actor=apiText.match(/create function trade_document_confirmation_api_private\.actor\(\)[\s\S]*?end \$\$;/)?.[0];
 if(sha(sources[0])!==manifest.sources[core]||!actor||sha(actor)!==manifest.actor_statement_sha256)throw Error('canonical_core_source_drift');
 const hashes=Object.fromEntries([core,...siteSources].map((n,i)=>[n,sha(sources[i])]));
 const pinned=JSON.parse(await read('docs/review/site-order-private-baseline/full-source-contract.json'));
 if(JSON.stringify(hashes)!==JSON.stringify(pinned))throw Error('site_source_drift');
 const recovery=await loadReplyRecovery(replyRecoveryRoot);
 if(recovery){hashes['external/'+recovery.head+'/'+recovery.path]=recovery.sha256;sources.push(recovery.sql);}
 const history=await loadSiteHistory(siteHistoryRoot);
 if(history){hashes['external/'+history.head+'/'+history.path]=history.sha256;sources.push(history.sql);}
 assertReceipts(before,after,hashes,manifest);
 const catalog=await read('docs/review/site-order-private-baseline/catalog_normalized.sql');
 // The existing capture SQL is caller-supplied only by this pinned package.
 const existing=await read('docs/review/site-order-private-baseline/existing_catalog_normalized.sql');
 const beforeSql=catalogSql(existing,['auth','private','public']);
 const newSql=catalogSql(catalog,newSchemas);
 const actorSql='create schema trade_document_confirmation_api_private;revoke all on schema trade_document_confirmation_api_private from public,anon,authenticated,service_role;'+actor+'revoke all on function trade_document_confirmation_api_private.actor() from public,anon,authenticated,service_role;';

 const sql=['-- BLOCKED REVIEW ONLY. Production HOLD remains; this is not an approved installer.','begin;',"set local search_path='';","do $$begin raise exception 'STOP: independent scoped approval and reviewed unblocking are required';end$$;",equalityGuard(beforeSql,before.snapshot,'site_baseline_before_catalog_changed'),equalityGuard(newSql,{namespaces:null,functions:null,relations:null},'site_baseline_new_namespace_already_exists'),legacyCaptureSql(),transactionBody(sources[0]),actorSql,...sources.slice(1).map(transactionBody),equalityGuard(beforeSql,after.existing_after,'site_baseline_existing_after_changed'),equalityGuard(newSql,after.new_after,'site_baseline_new_after_changed'),'commit;'].join('\n');
 return {sql,manifest:{blocked_review_only:true,production_approved:false,source_sha256:hashes,before_sha256:sha(JSON.stringify(before.snapshot)),existing_after_sha256:sha(JSON.stringify(after.existing_after)),new_after_sha256:sha(JSON.stringify(after.new_after)),sql_sha256:sha(sql)}};
}
if(process.argv[1]===new URL(import.meta.url).pathname){
 const [root,beforePath,afterPath,output,replyRecoveryRoot,siteHistoryRoot]=process.argv.slice(2);
 if(![root,beforePath,afterPath,output].every(Boolean))throw Error('usage: root before.json after.json new-output-directory');
 const result=await prepare(path.resolve(root),{before:JSON.parse(await fs.readFile(beforePath,'utf8')),after:JSON.parse(await fs.readFile(afterPath,'utf8')),replyRecoveryRoot,siteHistoryRoot});
 await fs.mkdir(output,{recursive:false});await fs.writeFile(path.join(output,'atomic-forward.sql.review-only'),result.sql);await fs.writeFile(path.join(output,'manifest.json'),JSON.stringify(result.manifest,null,2)+'\n');
}
