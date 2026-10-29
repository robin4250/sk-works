// Generates review-only single-transaction capsules; never executes SQL.
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const files={
 three:['tool/staged/employee_personnel_birth_date.sql.review-only','47005bf6973ad86c99af8ecad60f4576596e3c8ee547b1fb01baab78961a6cb5'],
 fourth:['tool/staged/personnel_birthday_noop.sql.review-only','c4ae672ce99c6a6dc6e3eca1d892345995ed4eea7c72779a11ed3772b383bca3'],
 restoreFourth:['tool/staged/personnel_birthday_noop_restore_unused.sql.review-only','47f4042baaba85c7bb2dff20d998fec4ccd9df808c0ac9a65992b0e112cb7ff3'],
 restoreThree:['tool/staged/employee_personnel_birth_date_restore_unused.sql.review-only','2db257e10ba1017c54b957aed16c217580f8ede1c06ff0173b6538c718a1d0e5'],
};
const bodies={};
for(const [key,[path,hash]] of Object.entries(files)){
 const source=await fs.readFile(path,'utf8');assert.equal(createHash('sha256').update(source).digest('hex'),hash,path);
 assert.equal(source.match(/^begin;$/gm)?.length,1,`${path}: outer BEGIN`);
 assert.equal(source.match(/^commit;$/gm)?.length,1,`${path}: outer COMMIT`);
 const start=source.indexOf('\nbegin;\n'),end=source.lastIndexOf('\ncommit;');
 assert.ok(start>=0&&end>start);assert.equal(source.slice(end).trim(),'commit;');
 bodies[key]=source.slice(start+'\nbegin;\n'.length,end);
}
const signatures=[
 ['private.worker_personnel_payload(uuid)','jsonb','s',null],
 ['private.apply_worker_personnel_payload(uuid,jsonb,uuid)','void','v',null],
 ['private.employee_personnel_view(uuid)','jsonb','s','{postgres=X/postgres,authenticated=X/postgres}'],
 ['public.save_worker_personnel_profile(uuid,jsonb)','jsonb','v','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'],
];
const hashes={
 install:['4619b54556b9262dc22b95a4a65fc59f','03b856009e6d298cd4fb01c07cab4d63','e00c5e49011a19f84ee60a2309822997','b6e83d8afa8ab5d4a061ed2c6df81271'],
 'restore-unused':['bed654f3bbad4e8e432db77520681330','445ae541afb2fcb376d49dde1388a84f','ec7a06349ecc5d2420e89ecedf54f6e7','c11956bf0845ab725312928c2422a7ab'],
};
function finalGuard(mode){
 const expected=signatures.map(([signature,return_type,volatility,acl],i)=>({signature,return_type,volatility,acl,body_md5:hashes[mode][i]}));
 return `do $atomic_final$ declare item jsonb;begin
 for item in select value from jsonb_array_elements($catalog$${JSON.stringify(expected)}$catalog$::jsonb) loop
  if not exists(select 1 from pg_proc p where p.oid=to_regprocedure(item->>'signature')
   and md5(p.prosrc)=item->>'body_md5' and pg_get_userbyid(p.proowner)='postgres'
   and p.proacl::text is not distinct from item->>'acl'
   and p.proconfig=array['search_path=""']::text[] and p.prosecdef
   and p.provolatile::text=item->>'volatility' and not p.proisstrict and not p.proleakproof
   and p.proparallel='u' and p.prokind='f' and not p.proretset
   and format_type(p.prorettype,null)=item->>'return_type') then
   raise sqlstate '55000' using message='personnel_birthday_atomic_final_catalog_drift';end if;
 end loop;
 if not exists(select 1 from information_schema.columns where table_schema='public'
  and table_name='worker_personnel_profiles' and column_name='birth_date' and data_type='date' and is_nullable='YES') then
  raise sqlstate '55000' using message='personnel_birthday_atomic_column_contract';end if;
 end $atomic_final$;`;
}
for(const [mode,steps] of [['install',['three','fourth']],['restore-unused',['restoreFourth','restoreThree']]]){
 const source=`-- REVIEW ONLY. No production apply authorization; existing source guards are unchanged.\n-- No zero-use machine gate: restore retains columns/data/proposals and is not permission for post-use withdrawal.\n${steps.map(k=>'-- Frozen '+files[k][0]+' SHA256 '+files[k][1]).join('\n')}\nbegin;\nset local lock_timeout='5s';\nselect pg_advisory_xact_lock(hashtextextended('sko:personnel-birthday-atomic-v1',0));\n${bodies[steps[0]]}\n-- birthday-atomic:after-step-1\n${bodies[steps[1]]}\n-- birthday-atomic:before-final-guard\n${finalGuard(mode)}\ncommit;\n`;
 await fs.writeFile('docs/candidates/personnel_birthday_atomic_20261030/'+mode+'.sql.review-only',source);
}
console.log('PASS four frozen source hashes; only outer transaction delimiters removed; install/reverse restore and final four-function attributes sealed');
