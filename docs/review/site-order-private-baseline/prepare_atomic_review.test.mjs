import {test} from 'node:test';
import assert from 'node:assert/strict';
import {catalogSql,equalityGuard,assertReceipts,newSchemas,loadReplyRecovery} from './prepare_atomic_review.mjs';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
const hash=s=>createHash('sha256').update(s).digest('hex');
const pinned={existing_function_contracts:Array.from({length:8},(_,i)=>({signature:'f'+i+'()',source_md5:'hash'+i,owner:'fixture',security_definer:false,volatility:'s',config:null,acl:[]})),existing_relation_names:Array.from({length:9},(_,i)=>'t'+i)};
pinned.full_existing_contract=JSON.parse(readFileSync(new URL('./full-existing-contract.json',import.meta.url),'utf8'));
const snapshot={functions:Object.fromEntries([...pinned.existing_function_contracts.map(f=>[f.signature,{source_md5:f.source_md5,owner:f.owner,prosecdef:f.security_definer,provolatile:f.volatility,proconfig:f.config,acl:[]}]),...pinned.full_existing_contract.additional_function_names.map(n=>[n+'()',{source_md5:n==='private.respond_site_share'?pinned.full_existing_contract.intended_legacy_change.before_md5:n==='public.respond_site_share'?pinned.full_existing_contract.intended_legacy_change.public_wrapper_before_and_after_md5:'fixture'}])]),relations:Object.fromEntries([...pinned.existing_relation_names,...pinned.full_existing_contract.additional_relation_names].map(n=>[n,{}])),default_acls:[],namespaces:[]};
const before={kind:'native-production-readonly-normalized-v1',production_mutation:false,server_version_num:'170006',snapshot,new_namespace_presence:Object.fromEntries(newSchemas.map(n=>[n,false]))};
const after={kind:'native-rehearsal-exact-current-helpers-v1',synthetic_seal:false,server_version_num:'170006',current_helper_bodies:8,original_c_sha256:'7796c2e7bcc7a9eca78f1b79ce8cfc87fcd978c1dc4a4ddb7a5a8ced17b597e5',source_sha256:{fixture:'test-only'},before_sha256:hash(JSON.stringify(before.snapshot)),existing_after:structuredClone(snapshot),new_after:{namespaces:newSchemas.map(name=>({name}))}};
after.existing_after.functions['private.respond_site_share()'].source_md5=pinned.full_existing_contract.intended_legacy_change.after_md5;
test('receipt gate accepts matching test-only shapes',()=>assert.equal(assertReceipts(before,after,{fixture:'test-only'},pinned),true));
test('denies missing real-native provenance and synthetic seal',()=>{
 for(const patch of [{kind:'pglite'},{synthetic_seal:true},{current_helper_bodies:7},{before_sha256:'changed'},{source_sha256:{}},{server_version_num:'170011'},{new_after:{namespaces:[]}}, {existing_after:{functions:{}}}])assert.throws(()=>assertReceipts(before,{...after,...patch},{fixture:'test-only'},pinned));
 assert.throws(()=>assertReceipts({...before,production_mutation:true},after,{fixture:'test-only'},pinned));
 assert.throws(()=>assertReceipts({...before,new_namespace_presence:{}},after,{fixture:'test-only'},pinned));
 assert.throws(()=>assertReceipts({...before,snapshot:{functions:{},relations:{}}},after,{fixture:'test-only'},pinned));
 const drift=structuredClone(before);drift.snapshot.functions['f0()'].source_md5='changed';assert.throws(()=>assertReceipts(drift,after,{fixture:'test-only'},pinned),/body_drift/);
 const aclDrift=structuredClone(before);aclDrift.snapshot.functions['f0()'].acl=[['fixture','PUBLIC','EXECUTE',true]];assert.throws(()=>assertReceipts(aclDrift,after,{fixture:'test-only'},pinned),/attributes_or_acl_drift/);
});
test('schema values are SQL quoted and no parameter remains',()=>{
 const q=catalogSql('select $1::text[] v;', ["bad'name"]);assert.equal(q,"select array['bad''name']::text[] v");
 assert.throws(()=>catalogSql('select 1',[]),/parameter/);
});
test('guard emits exact JSON, escapes literals and chooses a collision-free dollar tag',()=>{
 const sql=equalityGuard('select 1 v',{x:"' $sko_catalog_guard$"},"guard'label");
 assert.match(sql,/is distinct from/);assert.match(sql,/errcode='55000'/);assert.match(sql,/guard''label/);
 const tags=sql.match(/\$sko_guard_[a-f0-9]+\$/g);assert.equal(tags.length,2);assert.equal(tags[0],tags[1]);
});

test('optional reply recovery cannot read an arbitrary relative root',async()=>{
 assert.equal(await loadReplyRecovery(),null);
 await assert.rejects(()=>loadReplyRecovery('relative'),/absolute_root_required/);
});

test('full preflight emits a bounded READ ONLY metadata query',async()=>{
 const {preflightQuery}=await import('./capture_full_preflight.mjs');
 const sql=await preflightQuery(new URL('../../../',import.meta.url).pathname);
 assert.match(sql,/^begin read only;/);assert.match(sql,/server_version_num/);assert.match(sql,/new_namespace_presence/);assert.doesNotMatch(sql,/\$1/);assert.match(sql,/site_share_inbox/);assert.match(sql,/respond_site_share/);
});

test('missing formal C stops before any rehearsal is supplied',()=>{
 const missing=structuredClone(before);for(const n of ['private.require_trade_documents_master_feature','private.require_standalone_trade_document_access','private.standalone_trade_document_registration_context'])delete missing.snapshot.functions[n+'()'];
 assert.throws(()=>assertReceipts(missing,undefined,{},pinned),/complete_thirteen_function_before_required/);
});
