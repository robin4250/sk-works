// Does not execute SQL. Exact frozen source + independently observed catalog capsule.
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const sha=s=>createHash('sha256').update(s).digest('hex');
const base='tool/security/employee_bank_preapply_capsule/';
const catalog=JSON.parse(await fs.readFile(base+'catalog.json','utf8'));
const observed=catalog.functions;
assert.equal(observed.length,8);assert.equal(new Set(observed.map(x=>x.signature)).size,8);
const select=`select jsonb_build_object('signature',item->>'signature','definition_md5',md5(pg_get_functiondef(p.oid)),
 'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text,'config',p.proconfig,'security_definer',p.prosecdef,
 'volatility',p.provolatile::text,'strict',p.proisstrict,'leakproof',p.proleakproof,'parallel',p.proparallel::text,
 'kind',p.prokind::text,'returns_set',p.proretset,'return_type',format_type(p.prorettype,null))
 from pg_proc p where p.oid=to_regprocedure(item->>'signature')`;
function guard(rows,phase){
 assert.ok(!JSON.stringify(rows).includes('$catalog$'));
 return `do $attributes$ declare item jsonb;actual jsonb;begin
 for item in select value from jsonb_array_elements($catalog$${JSON.stringify(rows)}$catalog$::jsonb) loop
  ${select} into actual;
  if actual is distinct from item then raise sqlstate '55000' using message='employee_bank_capsule_${phase}_catalog_drift';end if;
 end loop;
 if not exists(select 1 from pg_trigger t where t.tgrelid='public.worker_private_bank_accounts'::regclass
 and t.tgname='${catalog.bank_trigger.name}' and t.tgenabled='${catalog.bank_trigger.enabled}'
 and pg_get_triggerdef(t.oid)=$trigger$${catalog.bank_trigger.definition}$trigger$) then
 raise sqlstate '55000' using message='employee_bank_capsule_trigger_drift';end if;
 end $attributes$;\n`;
}
const originals='tool/staged/employee_bank_initial_registration';
const definitions=JSON.parse(await fs.readFile('tool/security/employee_bank_initial/expected-candidate-definitions.json','utf8'));
const installed=observed.map(row=>({...row,definition_md5:definitions[row.signature]? // pg_get_functiondef includes final newline; saved candidate definitions are exact catalog form.
 createHash('md5').update(definitions[row.signature]).digest('hex'):row.definition_md5}));
for(const [mode,sourceHash] of [['install','af83bc3305e24e4db1fb0b4374c69d8df44c3215f358a755674371b228f9105a'],['restore-unused','3e963756ab0fe84ceda7674068d762288fb37f11538e61e708aa9ffd1f9fd4d5']]){
 const path=originals+(mode==='install'?'':'.restore-unused')+'.sql.review-only';
 const source=await fs.readFile(path,'utf8');assert.equal(sha(source),sourceHash);
 const start=source.indexOf('\nbegin;\n'),end=source.lastIndexOf('\ncommit;');
 assert.ok(start>=0&&end>start);assert.equal(source.slice(end).trim(),'commit;');
 const body=source.slice(start+'\nbegin;\n'.length,end);
 const before=mode==='install'?observed:installed,after=mode==='install'?installed:observed;
 const capsule=`-- REVIEW ONLY; no production authorization. Frozen source SHA256 ${sourceHash}\n-- No original function/table data edits beyond the frozen reviewed module.\nbegin;\nset local lock_timeout='5s';\nselect pg_advisory_xact_lock(hashtextextended('sko:employee-bank-preapply-capsule-v1',0));\n${guard(before,'before')}${body}\n${guard(after,'after')}commit;\n`;
 await fs.writeFile('docs/candidates/employee_bank_preapply_capsule_20261029/'+mode+'.sql.review-only',capsule);
}
console.log('PASS exact frozen bank sources encapsulated in single transactions with eight-function pre/post attribute fingerprints');
