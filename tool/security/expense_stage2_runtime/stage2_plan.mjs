// Offline only. No connection, credentials, gate activation or business DML.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {isDeepStrictEqual as equal} from 'node:util';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
const hash=(s,alg='sha256')=>createHash(alg).update(s).digest('hex');
for(const [name,pin] of Object.entries({
 'expense_direction_code_checkpoint.mjs':'9a642ea96fc3d564f6c711c2547da5954310f5fdf7f1448abdef2a0dcfa6197f',
 'expense_direction_default_off_preparation.mjs':'5e1401c0271be411ae6d1de9ac8f20432380cd4ebd6db2cc0ccffd46e83fdda8'}))
 assert.equal(hash(fs.readFileSync(new URL('./source/'+name,import.meta.url))),pin);
const {catalogSql,oldFunctions,newFunctions}=await import('./source/expense_direction_code_checkpoint.mjs');
const {defaultOffBusinessHashSql}=await import('./source/expense_direction_default_off_preparation.mjs');
const detail='public.payment_certificate_detail_rows(uuid)';
const added=['private.payment_expense_v2_requested()','private.expense_direction_v2_client_rollout_verified(uuid)','private.expense_payment_conversion_audit_immutable()','private.convert_payment_expense_v1_draft(uuid,uuid,uuid,date,integer,jsonb,text,text,text)'];
const existing=[...oldFunctions,...newFunctions,detail];
const sigs=[...existing,...added].map(x=>"'"+x+"'").join(',');
const tables='public.payment_certificates,private.expense_claims,private.expense_settlement_choices,private.expense_amount_consumptions,private.expense_document_snapshots';
const quote=(s,tag='stage2_value')=>{assert(!s.includes('$'+tag+'$'),'delimiter collision');return '$'+tag+'$'+s+'$'+tag+'$';};
const json=x=>quote(JSON.stringify(x))+'::jsonb';
const sourceMd5={
 'private.expense_cost_direction_v2_enabled(uuid)':'9f038cd8f856dc2fad5b866160f26637',
 'private.expense_cost_finalize()':'22ff4377666ec56ccc4b261cf380e9c0',
 'private.expense_payment_direction_capability(uuid)':'72c86b51bc0c6ae5c283e9868834fb54',
 'private.expense_payment_v2_envelope(uuid,uuid,uuid,date,integer,numeric,jsonb)':'52dcf11a021a6584621527aeacbf6e37',
 'private.expense_payment_v2_guard()':'4d08bd0b372a3048b9eb52dd99a3c321',
 'private.read_expense_document(text,uuid)':'85a16c6a5181c4f4ee85316f69a288cb',
 'private.refresh_automatic_payment_certificate(uuid,uuid,date)':'5828ec68ad83ace5f0c0fc8f21851cf8',
 'public.expense_payment_direction_capability(uuid)':'23d08c31cf55263869f09be3967f42a7',
 [detail]:'c069b7e687c0bb7faac9ff314d3873ff'};
const closureSql=`WITH RECURSIVE names(name) AS (
 SELECT unnest(array['private.expense_cost_scope_lock','private.account_access_allowed','private.expense_cost_components','private.certificate_calculation_rows','auth.uid',${existing.map(s=>"'"+s.slice(0,s.indexOf('('))+"'").join(',')}]) COLLATE \"C\"
 UNION
 SELECT match[1] COLLATE \"C\" FROM names seed JOIN pg_proc p ON p.oid IN (SELECT q.oid FROM pg_proc q JOIN pg_namespace n ON n.oid=q.pronamespace WHERE n.nspname||'.'||q.proname=seed.name) CROSS JOIN LATERAL regexp_matches(p.prosrc,'((?:private|public|auth)\\.[a-zA-Z_][a-zA-Z_0-9]*)[[:space:]]*\\(','g') match
 ) SELECT coalesce(jsonb_object_agg(n.nspname||'.'||p.proname||'('||replace(oidvectortypes(p.proargtypes),', ',',')||')',jsonb_build_object('proc',to_jsonb(p),'definition',pg_get_functiondef(p.oid))),'{}'::jsonb) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname||'.'||p.proname IN(SELECT name FROM names)`;
export const checkpointSql=`select jsonb_build_object(
 'legacy',(${catalogSql}),
 'closure',(${closureSql}),
 'functions',coalesce((select jsonb_object_agg(s,jsonb_build_object('proc',to_jsonb(p),'definition',pg_get_functiondef(p.oid))) from unnest(array[${sigs}]) s join pg_proc p on p.oid=to_regprocedure(s)),'{}'::jsonb),
 'policies',coalesce((select jsonb_agg(to_jsonb(p) order by p.oid) from pg_policy p where p.polrelid='public.payment_certificates'::regclass),'[]'::jsonb),
 'payment_relation',(select to_jsonb(c)-'relpages'-'reltuples'-'relallvisible'-'relallfrozen' from pg_class c where c.oid='public.payment_certificates'::regclass),
 'default_acl',coalesce((select jsonb_agg(to_jsonb(a) order by a.oid) from pg_default_acl a),'[]'::jsonb),
 'schemas',(select jsonb_agg(to_jsonb(n) order by n.oid) from pg_namespace n where n.nspname in ('private','public')),
 'policy_expression',(select pg_get_expr(polqual,polrelid) from pg_policy where polrelid='public.payment_certificates'::regclass and polname='payment_expense_source_compatibility'),
 'rights_safe',NOT EXISTS(SELECT 1 FROM pg_proc pr CROSS JOIN LATERAL aclexplode(coalesce(pr.proacl,acldefault('f',pr.proowner))) ac WHERE pr.oid IN(select to_regprocedure(s) from unnest(array[${added.map(s=>"'"+s+"'").join(',')}]) s) AND ac.grantee<>pr.proowner AND (pr.oid IS DISTINCT FROM to_regprocedure('private.payment_expense_v2_requested()') OR ac.grantee<>(SELECT oid FROM pg_roles WHERE rolname='authenticated') OR ac.is_grantable)) AND NOT EXISTS(SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) ac WHERE c.oid=to_regclass('private.expense_payment_direction_conversions') AND ac.grantee<>c.relowner),
 'role_oids',(select jsonb_object_agg(rolname,oid) from pg_roles where rolname in ('postgres','authenticated','anon','service_role')),
 'audit',case when to_regclass('private.expense_payment_direction_conversions') is null then null else jsonb_build_object(
  'relation',(select to_jsonb(c)-'relpages'-'reltuples'-'relallvisible'-'relallfrozen' from pg_class c where c.oid=to_regclass('private.expense_payment_direction_conversions')),
  'columns',(select jsonb_agg(to_jsonb(a) order by a.attnum) from pg_attribute a where a.attrelid=to_regclass('private.expense_payment_direction_conversions') and a.attnum>0),
  'defaults',(select jsonb_agg(jsonb_build_object('column',a.adnum,'expression',pg_get_expr(a.adbin,a.adrelid)) order by a.adnum) from pg_attrdef a where a.adrelid=to_regclass('private.expense_payment_direction_conversions')),
  'constraints',(select jsonb_agg(to_jsonb(c) order by c.oid) from pg_constraint c where c.conrelid=to_regclass('private.expense_payment_direction_conversions')),
  'indexes',(select jsonb_agg(to_jsonb(i) order by i.indexrelid) from pg_index i where i.indrelid=to_regclass('private.expense_payment_direction_conversions')),
  'triggers',(select jsonb_agg(to_jsonb(t) order by t.oid) from pg_trigger t where t.tgrelid=to_regclass('private.expense_payment_direction_conversions')),
  'policies',(select coalesce(jsonb_agg(to_jsonb(p) order by p.oid),'[]'::jsonb) from pg_policy p where p.polrelid=to_regclass('private.expense_payment_direction_conversions'))
 ) end) value`;
// All scans are bounded before digest aggregation. No financial rows are returned.
const limits=`DO $stage2_limits$ DECLARE audit_count bigint:=0; BEGIN
 IF (SELECT sum(n) FROM (${tables.split(',').map(t=>`select count(*) n from (select 1 from ${t} limit 10001) q`).join(' union all ')}) q)>10000 THEN RAISE EXCEPTION 'stage2 row limit'; END IF;
 IF (SELECT sum(n) FROM (${tables.split(',').map(t=>`select coalesce(sum(octet_length(to_jsonb(x)::text)),0) n from ${t} x`).join(' union all ')}) q)>16777216 THEN RAISE EXCEPTION 'stage2 byte limit'; END IF;
 IF to_regclass('private.expense_payment_direction_conversions') IS NOT NULL THEN EXECUTE 'select count(*) from private.expense_payment_direction_conversions' INTO audit_count; END IF; PERFORM set_config('sko.stage2_audit_count',audit_count::text,true);
 END $stage2_limits$;`;
const observation=`select jsonb_build_object('schema',2,'read_only',current_setting('transaction_read_only'),'checkpoint',(${checkpointSql}),'business',(${defaultOffBusinessHashSql}),
 'audit_count',current_setting('sko.stage2_audit_count')::bigint,'v2_count',(select count(*) from public.payment_certificates where snapshot?'expense_cost_direction_v2' or snapshot?'expense_cost_basis')) value`;
export const captureSql=`BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY; SET LOCAL search_path=public;SET LOCAL ROLE postgres;SET LOCAL statement_timeout='30s';SET LOCAL lock_timeout='3s';\n${limits}\n${observation};\nCOMMIT;`;
function validateBefore(b){
 assert.equal(b.schema,2);assert.equal(b.read_only,'on');assert.match(b.business,/^[a-f0-9]{32}$/);assert.equal(b.v2_count,0);assert.equal(b.audit_count,0);
 const c=b.checkpoint;assert.equal(c.audit,null);assert.equal(c.payment_relation.relrowsecurity,true);
 assert.deepEqual(Object.keys(c.functions).sort(),existing.toSorted());assert(c.closure && Object.keys(c.closure).length>0);assert.equal(c.policy_expression,null);assert.equal(c.rights_safe,true);
 assert(!c.policies.some(p=>p.polname==='payment_expense_source_compatibility'));
 for(const [s,h] of Object.entries(sourceMd5))assert.equal(hash(c.functions[s].proc.prosrc,'md5'),h,'stage1 source differs '+s);
 for(const s of existing){const p=c.functions[s].proc;assert.equal(p.proowner,c.functions[existing[0]].proc.proowner);assert.deepEqual(p.proconfig,['search_path=""']);}
}
function candidates(converter,negotiation){
 assert.equal(hash(converter),'725ff2533539c63759c92c0bbc45d37c131fa431c421fd76deb127bdff2604d7');
 assert.equal(hash(negotiation),'f08628a18891c114c64f7551c33f1139879da3fb1439bac23c8eb54f1995507d');
 assert.equal(negotiation.split('\nBEGIN;\n').length,2);assert(negotiation.endsWith('COMMIT;\n'));
 return {converter,negotiation:negotiation.replace('\nBEGIN;\n','\n').slice(0,-'COMMIT;\n'.length)};
}
function expectedSources(b,conv,neg){
 const sources=Object.fromEntries(existing.map(s=>[s,b.checkpoint.functions[s].proc.prosrc]));
 const da=" if jsonb_typeof(c.snapshot->'calculation_rows')='array' then";
 const ea=" if p_kind='paymentCertificate' and row_data->'snapshot'?'expense_cost_direction_v2' then";
 const dr="\n if c.snapshot?'expense_cost_direction_v2' AND private.payment_expense_v2_requested() IS NOT TRUE\n then raise exception 'Update SKO to read directional expenses' using errcode='42501'; end if;\n if jsonb_typeof(c.snapshot->'calculation_rows')='array' then";
 const er="\n if p_kind='paymentCertificate' and row_data->'snapshot'?'expense_cost_direction_v2' then\n if private.payment_expense_v2_requested() IS NOT TRUE\n then raise exception 'Update SKO to read directional expenses' using errcode='42501'; end if;";
 for(const [s,a,r] of [[detail,da,dr],['private.read_expense_document(text,uuid)',ea,er]]){assert.equal(sources[s].split(a).length,2);sources[s]=sources[s].replace(a,r);}
 const bodies=[...conv.matchAll(/as \$\$([\s\S]*?)\$\$/gi)].map(m=>m[1]);assert.equal(bodies.length,3);
 const helper=neg.match(/AS \$\$([\s\S]*?)\$\$/)[1];
 [helper,...bodies].forEach((body,i)=>sources[added[i]]=body);
 return sources;
}
const noUsage=`IF EXISTS(SELECT 1 FROM public.payment_certificates WHERE snapshot?'expense_cost_direction_v2' OR snapshot?'expense_cost_basis') THEN RAISE EXCEPTION 'v2 usage exists';END IF;`;
const gates=`IF (SELECT prosrc FROM pg_proc WHERE oid='private.expense_cost_direction_v2_enabled(uuid)'::regprocedure) IS DISTINCT FROM 'select false' THEN RAISE EXCEPTION 'direction gate changed';END IF;`;
function invariants(b,sources){return `
DO $stage2_post$ DECLARE obs jsonb;f record;procval jsonb;old jsonb;pol jsonb;BEGIN
 SELECT value INTO obs FROM (${checkpointSql}) q;
 IF (${defaultOffBusinessHashSql}) IS DISTINCT FROM '${b.business}' THEN RAISE EXCEPTION 'financial drift';END IF;
 ${noUsage} ${gates}
 IF (SELECT prosrc FROM pg_proc WHERE oid='private.expense_direction_v2_client_rollout_verified(uuid)'::regprocedure) IS DISTINCT FROM 'select false' THEN RAISE EXCEPTION 'rollout gate changed';END IF;
 IF EXISTS(SELECT 1 FROM private.expense_payment_direction_conversions) THEN RAISE EXCEPTION 'conversion already used';END IF;
 IF (SELECT jsonb_object_agg(k,CASE WHEN k IN ('private.read_expense_document(text,uuid)','public.payment_certificate_detail_rows(uuid)') THEN jsonb_build_object('proc',(v->'proc')-'prosrc') ELSE v END) FROM jsonb_each(obs->'closure') x(k,v) WHERE k NOT IN ('private.payment_expense_v2_requested()')) IS DISTINCT FROM (SELECT jsonb_object_agg(k,CASE WHEN k IN ('private.read_expense_document(text,uuid)','public.payment_certificate_detail_rows(uuid)') THEN jsonb_build_object('proc',(v->'proc')-'prosrc') ELSE v END) FROM jsonb_each(${json(b.checkpoint.closure)}) x(k,v)) THEN RAISE EXCEPTION 'dependency closure drift';END IF;
 IF obs->'default_acl' IS DISTINCT FROM ${json(b.checkpoint.default_acl)} OR obs->'schemas' IS DISTINCT FROM ${json(b.checkpoint.schemas)} OR obs->'payment_relation' IS DISTINCT FROM ${json(b.checkpoint.payment_relation)} THEN RAISE EXCEPTION 'relation/schema/defaultacl changed';END IF;
 IF obs->'legacy'->'triggers' IS DISTINCT FROM ${json(b.checkpoint.legacy.triggers)} OR obs->'legacy'->'event_triggers' IS DISTINCT FROM ${json(b.checkpoint.legacy.event_triggers)} THEN RAISE EXCEPTION 'trigger drift';END IF;
 IF (SELECT coalesce(jsonb_agg(x order by (x->>'oid')::oid),'[]'::jsonb) FROM jsonb_array_elements(obs->'policies') x WHERE x->>'polname'<>'payment_expense_source_compatibility') IS DISTINCT FROM ${json(b.checkpoint.policies)} THEN RAISE EXCEPTION 'existing policy changed';END IF;
 IF obs->>'policy_expression' IS DISTINCT FROM $$((NOT COALESCE((snapshot ? 'expense_cost_direction_v2'::text), false)) OR ( SELECT private.payment_expense_v2_requested() AS payment_expense_v2_requested))$$ THEN RAISE EXCEPTION 'policy expression differs';END IF;
 SELECT x INTO pol FROM jsonb_array_elements(obs->'policies') x WHERE x->>'polname'='payment_expense_source_compatibility';
 IF pol IS NULL OR pol->>'polcmd'<>'r' OR (pol->>'polpermissive')::boolean OR pol->'polroles' IS DISTINCT FROM to_jsonb(ARRAY[(SELECT oid FROM pg_roles WHERE rolname='authenticated')]) OR pol->>'polwithcheck' IS NOT NULL THEN RAISE EXCEPTION 'new policy differs';END IF;
 FOR f IN SELECT key,value FROM jsonb_each(${json(sources)}) LOOP
 procval:=obs->'functions'->f.key->'proc';old:=${json(b.checkpoint.functions)}->f.key->'proc';
 IF procval IS NULL OR procval->>'prosrc' IS DISTINCT FROM f.value#>>'{}' THEN RAISE EXCEPTION 'function body differs %',f.key;END IF;
 IF old IS NOT NULL THEN
 IF (procval-'prosrc') IS DISTINCT FROM (old-'prosrc') THEN RAISE EXCEPTION 'existing metadata changed %',f.key;END IF;
 ELSE
 IF (procval->>'proowner')::oid<>(SELECT oid FROM pg_roles WHERE rolname=current_user) OR (procval->>'prosecdef')::boolean OR procval->'proconfig' IS DISTINCT FROM '["search_path=\\"\\""]'::jsonb
 OR has_function_privilege('authenticated',(procval->>'oid')::oid,'EXECUTE') IS DISTINCT FROM (f.key='private.payment_expense_v2_requested()')
 OR EXISTS(SELECT 1 FROM pg_proc pr CROSS JOIN LATERAL aclexplode(coalesce(pr.proacl,acldefault('f',pr.proowner))) ac WHERE pr.oid=(procval->>'oid')::oid AND ac.grantee<>pr.proowner AND (f.key<>'private.payment_expense_v2_requested()' OR ac.grantee<>(SELECT oid FROM pg_roles WHERE rolname='authenticated') OR ac.is_grantable)) THEN RAISE EXCEPTION 'new function rights differ';END IF;
 END IF;
 END LOOP;
 IF jsonb_array_length(obs->'audit'->'columns')<>12 OR EXISTS(SELECT 1 FROM jsonb_array_elements(obs->'audit'->'columns') x WHERE (x->>'attnotnull')::boolean IS NOT TRUE OR (x->>'attisdropped')::boolean OR (x->>'atttypmod')::int<>-1) OR (SELECT jsonb_agg(x->'atttypid' ORDER BY (x->>'attnum')::int) FROM jsonb_array_elements(obs->'audit'->'columns') x) IS DISTINCT FROM '[\"2950\",\"2950\",\"2950\",\"1082\",\"23\",\"25\",\"3802\",\"3802\",\"25\",\"25\",\"2950\",\"1184\"]'::jsonb OR obs->'audit'->'defaults' IS DISTINCT FROM '[{\"column\":12,\"expression\":\"now()\"}]'::jsonb OR jsonb_array_length(obs->'audit'->'constraints')<>1 OR jsonb_array_length(obs->'audit'->'triggers')<>1 THEN RAISE EXCEPTION 'audit schema differs';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgrelid='private.expense_payment_direction_conversions'::regclass AND t.tgname='expense_payment_conversion_audit_immutable' AND t.tgfoid='private.expense_payment_conversion_audit_immutable()'::regprocedure AND t.tgtype=27 AND t.tgenabled='O' AND t.tgqual IS NULL AND NOT t.tgisinternal AND t.tgnargs=0) THEN RAISE EXCEPTION 'audit trigger differs';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class c WHERE c.oid='private.expense_payment_direction_conversions'::regclass AND c.relowner=(SELECT oid FROM pg_roles WHERE rolname=current_user) AND c.relrowsecurity AND NOT c.relforcerowsecurity)
 OR EXISTS(SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) ac WHERE c.oid='private.expense_payment_direction_conversions'::regclass AND ac.grantee<>c.relowner)
 OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='private.expense_payment_direction_conversions'::regclass)
 THEN RAISE EXCEPTION 'audit rights differ';END IF;
END $stage2_post$;`;}
export function buildInstall(before,converterText,negotiationText){
 validateBefore(before);const c=candidates(converterText,negotiationText);const sources=expectedSources(before,c.converter,c.negotiation);
 return `BEGIN;SET LOCAL ROLE postgres;SET LOCAL search_path=public;SET LOCAL statement_timeout='30s';SET LOCAL lock_timeout='3s';\nLOCK TABLE ${tables} IN SHARE ROW EXCLUSIVE MODE NOWAIT;\n${limits}\nDO $stage2_before$ BEGIN
 IF (${checkpointSql}) IS DISTINCT FROM ${json(before.checkpoint)} OR (${defaultOffBusinessHashSql}) IS DISTINCT FROM '${before.business}' THEN RAISE EXCEPTION 'stage2 before drift';END IF;
 ${gates} ${noUsage}
 END $stage2_before$;\n${c.converter}\n${c.negotiation}\n${invariants(before,sources)}\nCOMMIT;`;
}
function validatedAfter(before,after){
 validateBefore(before);assert.equal(after?.read_only,'on');assert.equal(after.schema,2);assert.equal(after.business,before.business);assert.equal(after.v2_count,0);assert.equal(after.audit_count,0);
 const a=after.checkpoint,b=before.checkpoint;
 assert.deepEqual(Object.keys(a.functions).sort(),[...existing,...added].toSorted());
 const c=candidates(fs.readFileSync(new URL('./source/converter.sql.review-only',import.meta.url),'utf8'),fs.readFileSync(new URL('./source/negotiation.sql.review-only',import.meta.url),'utf8'));
 const sources=expectedSources(before,c.converter,c.negotiation);
 for(const s of existing){const p={...a.functions[s].proc},q={...b.functions[s].proc};assert.equal(p.prosrc,sources[s]);delete p.prosrc;delete q.prosrc;assert.deepEqual(p,q);}
 for(const [i,s] of added.entries()){const p=a.functions[s].proc;assert.equal(p.provolatile,i<2?'s':'v');assert.equal(p.proparallel,'u');assert.equal(p.proisstrict,false);assert.equal(p.proleakproof,false);assert.equal(p.prokind,'f');assert.equal(p.proretset,false);assert.equal(p.prorettype,['16','16','2279','3802'][i]);assert.equal(p.pronargs,[0,1,0,9][i]);assert.equal(p.pronargdefaults,0);assert.equal(p.prosrc,sources[s]);assert.equal(p.proowner,b.functions[existing[0]].proc.proowner);assert.equal(p.prosecdef,false);assert.deepEqual(p.proconfig,['search_path=""']);}
 assert.equal(a.rights_safe,true);assert.deepEqual(a.role_oids,b.role_oids);
 for(const k of ['default_acl','schemas','payment_relation'])assert.deepEqual(a[k],b[k]);
 for(const k of ['triggers','event_triggers'])assert.deepEqual(a.legacy[k],b.legacy[k]);
 const policies=a.policies.filter(p=>p.polname!=='payment_expense_source_compatibility');assert.deepEqual(policies,b.policies);
 assert.equal(a.policies.length,b.policies.length+1);const p=a.policies.find(p=>p.polname==='payment_expense_source_compatibility');assert.equal(p.polcmd,'r');assert.equal(p.polpermissive,false);assert.deepEqual(p.polroles,[a.role_oids.authenticated]);assert.equal(p.polwithcheck,null);
 assert.equal(a.policy_expression,"((NOT COALESCE((snapshot ? 'expense_cost_direction_v2'::text), false)) OR ( SELECT private.payment_expense_v2_requested() AS payment_expense_v2_requested))");
 assert(a.audit);assert.deepEqual(a.audit.columns.map(x=>x.attname),['document_id','company_id','subject_id','month','source_revision','source_hash','before_row','after_row','backup_reference','rollout_reference','actor_id','converted_at']);
 assert.deepEqual(a.audit.columns.map(x=>x.atttypid),['2950','2950','2950','1082','23','25','3802','3802','25','25','2950','1184']);assert(a.audit.columns.every(x=>x.attnotnull && !x.attisdropped && x.atttypmod===-1));assert.deepEqual(a.audit.defaults,[{column:12,expression:'now()'}]);
 assert.equal(a.audit.constraints.length,1);assert.equal(a.audit.constraints[0].contype,'p');
 const triggers=a.audit.triggers.filter(t=>!t.tgisinternal);assert.equal(triggers.length,1);assert.equal(triggers[0].tgname,'expense_payment_conversion_audit_immutable');assert.equal(triggers[0].tgtype,27);assert.equal(triggers[0].tgenabled,'O');assert.equal(triggers[0].tgfoid,a.functions['private.expense_payment_conversion_audit_immutable()'].proc.oid);assert.equal(triggers[0].tgqual,null);
 assert.equal(a.audit.relation.relrowsecurity,true);assert.equal(a.audit.relation.relforcerowsecurity,false);assert.equal(a.audit.relation.relowner,b.functions[existing[0]].proc.proowner);assert.deepEqual(a.audit.policies,[]);
 // Compare each old dependency exactly, allowing only the two reviewed reader bodies.
 for(const [sig,item] of Object.entries(b.closure)){
  const found=a.closure[sig];assert(found);if(existing.includes(sig)){const x={...item.proc},y={...found.proc};delete x.prosrc;delete y.prosrc;assert.deepEqual(y,x);assert.equal(found.proc.prosrc,sources[sig]);}else assert.deepEqual(found,item);
 }
 return true;
}
export function classify(before,after){
 try{validateBefore(before);if(after?.read_only!=='on'||after.schema!==2||after.business!==before.business||after.v2_count!==0||after.audit_count!==0)return 'state_requires_review';
 if(equal(after.checkpoint,before.checkpoint))return 'before_state_observed';
 validatedAfter(before,after);return 'installed_off_unused_undo_candidate';
 }catch{return 'state_requires_review';}
}
export function buildUnusedUndo(before,after){
 validatedAfter(before,after);assert.equal(after.schema,2);assert.equal(after.read_only,'on');assert.equal(after.business,before.business);assert.equal(after.v2_count,0);assert.equal(after.audit_count,0);
 assert(after.checkpoint.audit);assert.deepEqual(Object.keys(after.checkpoint.functions).sort(),[...existing,...added].toSorted());
 // SQL rechecks exact actual OIDs/ACL/body + no-use constraints, never CASCADE.
 const restores=[detail,'private.read_expense_document(text,uuid)'].map(s=>before.checkpoint.functions[s].definition+';').join('\n');
 return `BEGIN;SET LOCAL ROLE postgres;SET LOCAL search_path=public;SET LOCAL statement_timeout='30s';SET LOCAL lock_timeout='3s';LOCK TABLE ${tables},private.expense_payment_direction_conversions IN SHARE ROW EXCLUSIVE MODE NOWAIT;\n${limits}\nDO $stage2_undo$ BEGIN
 IF (${checkpointSql}) IS DISTINCT FROM ${json(after.checkpoint)} OR (${defaultOffBusinessHashSql}) IS DISTINCT FROM '${before.business}' THEN RAISE EXCEPTION 'stage2 actual differs';END IF;
 ${noUsage} ${gates}
 IF (SELECT prosrc FROM pg_proc WHERE oid='private.expense_direction_v2_client_rollout_verified(uuid)'::regprocedure) IS DISTINCT FROM 'select false' OR EXISTS(SELECT 1 FROM private.expense_payment_direction_conversions) THEN RAISE EXCEPTION 'stage2 used or enabled';END IF;
 END $stage2_undo$;
 ${restores}
 DROP POLICY payment_expense_source_compatibility ON public.payment_certificates;
 DROP FUNCTION private.payment_expense_v2_requested();
 DROP FUNCTION private.convert_payment_expense_v1_draft(uuid,uuid,uuid,date,integer,jsonb,text,text,text);
 DROP TRIGGER expense_payment_conversion_audit_immutable ON private.expense_payment_direction_conversions;
 DROP FUNCTION private.expense_payment_conversion_audit_immutable();
 DROP TABLE private.expense_payment_direction_conversions;
 DROP FUNCTION private.expense_direction_v2_client_rollout_verified(uuid);
 DO $stage2_restored$ BEGIN IF (${checkpointSql}) IS DISTINCT FROM ${json(before.checkpoint)} OR (${defaultOffBusinessHashSql}) IS DISTINCT FROM '${before.business}' THEN RAISE EXCEPTION 'stage2 restore differs';END IF; END $stage2_restored$;
 COMMIT;`;
}
// CLI accepts JSON on stdin and returns JSON only. Never connects or reads secrets.
if(process.argv[1]===fileURLToPath(import.meta.url)){
 try{const mode=process.argv[2];const input=mode==='capture-sql'?{}:JSON.parse(fs.readFileSync(0,'utf8'));let result;
 if(mode==='capture-sql')result={sql:captureSql};
 else if(mode==='install')result={sql:buildInstall(input.before,input.converterText,input.negotiationText)};
 else if(mode==='classify')result={state:classify(input.before,input.after),retry_allowed:false};
 else if(mode==='undo')result={sql:buildUnusedUndo(input.before,input.after)};
 else throw Error('unknown mode');process.stdout.write(JSON.stringify(result));
 }catch{process.stderr.write('stage2_offline_refused\n');process.exitCode=1;}
}
