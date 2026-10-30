// Guard-only PG17 rehearsal. Reuse the exact reviewed neutral fixture setup,
// without repeating the successful 30 x 5 geometry matrix.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const path='tool/verify_signature_new_input_geometry.mjs';
const original=await readFile(path,'utf8');
assert.equal(createHash('sha256').update(original).digest('hex'),'a3f88d2edce2131ff243a62d73e7b1879088d80ee5f33c9ad8a4d489c0c6c8d4');
const start=" phase='old-server-dot-acceptance-red';";const end='}catch(error){';
assert.equal(original.split(start).length,2);assert.equal(original.split(end).length,2);
const guard=String.raw`
 phase='full-helper-guard-rehearsal';
 const originalCatalog=await q("select jsonb_agg(to_jsonb(p) order by p.oid) v from pg_proc p where p.oid=any($1::regprocedure[])",[fixture.writers.map(signature)]);
 const originalBusiness=await snapshot();
 const base=(await q("select to_jsonb(p)-'prosrc'-'oid'-'pronamespace' v from pg_proc p where p.oid='private.save_daily_report_signature(uuid,text,text,jsonb)'::regprocedure"));
 Object.assign(base,{proacl:['postgres=X/postgres'],pronargs:1,proargnames:['p_value'],proargtypes:['3802'],prosecdef:false,provolatile:'i'});
 const validator=await readFile(root+'validator-core.sql','utf8');
 const helperSources=[...validator.matchAll(/create function signature_new_input_private\.(\w+)\(p_value jsonb\)[\s\S]*?as \$\$([\s\S]*?)\$\$;/gi)];eq(helperSources.length,2,'Two expected pure helpers');
 const quoted=x=>'$expected$'+JSON.stringify(x)+'$expected$::jsonb';
 let post="do $guard$ begin ";
 for(const m of helperSources){const expected={...base,proname:m[1]};post+="if not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='signature_new_input_private' and p.proname='"+m[1]+"' and (to_jsonb(p)-'prosrc'-'oid'-'pronamespace') is not distinct from "+quoted(expected)+" and md5(p.prosrc)='"+md5(m[2])+"') then raise exception 'fixture_full_helper_catalog_guard';end if;";}
 post+="end $guard$;";
 const sql=await readFile(root+'install.sql.review-only','utf8');assert.ok(sql.trimEnd().endsWith('commit;'));const uncommitted=sql.trimEnd().slice(0,-7);
 for(const fault of ["alter function signature_new_input_private.require_ink(jsonb) cost 101;", "grant execute on function signature_new_input_private.require_financial_signature(jsonb) to anon;"]){
  await reject(()=>db.query(uncommitted+fault+post+'commit;'),/fixture_full_helper_catalog_guard/);await db.query('rollback');
  eq(await q("select to_regnamespace('signature_new_input_private') is null v"),true,'Late guard failure rolls back new schema and helpers');
  eq(await q("select jsonb_agg(to_jsonb(p) order by p.oid) v from pg_proc p where p.oid=any($1::regprocedure[])",[fixture.writers.map(signature)]),originalCatalog,'Late guard failure rolls back all three writer full catalog and source');
  eq(await snapshot(),originalBusiness,'Failed code install changes no original, receipt or financial counter');
 }
 await db.query(uncommitted+post+'commit;');
 eq(await snapshot(),originalBusiness,'Successful code install changes no business rows');
 for(const pin of sourcePins.writers){const f=fixture.writers.find(f=>f.schema===pin.schema&&f.proname===pin.name);eq(await q('select md5(prosrc) v from pg_proc where oid=$1::regprocedure',[signature(f)]),pin.after,'Expected three writer source installed');}
 for(const before of originalCatalog){const after=await q('select to_jsonb(p) v from pg_proc p where oid=$1',[before.oid]);delete before.prosrc;delete after.prosrc;eq(after,before,'Every original non-body catalog attribute preserved');}
 eq(await q("select md5(prosrc) v from pg_proc where oid='checkout_report_registration_private.has_signature(text,jsonb)'::regprocedure"),untouchedHistoryHash,'Historical interpreter unchanged');
 console.log(JSON.stringify({pass:true,checks,guard_only:true,full_helper_catalog:true,late_cost_and_acl_fault_whole_transaction_rollback:true,all_three_writer_full_attributes_rollback:true,fixture_oid_mapping_only:true,literal_production_oid_guard_rehearsed:false,production_changed:false}));
`;
const rewritten=original.slice(0,original.indexOf(start))+guard+original.slice(original.indexOf(end));
await import('data:text/javascript;charset=utf-8,'+encodeURIComponent(rewritten));
