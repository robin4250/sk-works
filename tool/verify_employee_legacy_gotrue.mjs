// Isolated real GoTrue/PostgREST; reuses the existing disposable stack harness.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
const source=await readFile('tool/company_checkout_real_gotrue_e2e.mjs','utf8');
const start=" phase='unchanged-checkout-foundation';";
const end='}catch(error){';
assert.equal(source.split(start).length,2);
assert.equal(source.split(end).length,2);
const test=String.raw`
 phase='legacy-personnel-fixture';
 let foundation=await read('docs/review/employee-category-candidate/fixture.sql');
 for(const exact of [
  'create role anon nologin; create role authenticated nologin;',
  'create schema auth; create schema private;',
  "create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('test.actor',true),'')::uuid$$;"
 ]){
  eq(foundation.split(exact).length,2);
  foundation=foundation.replace(exact,exact==='create schema auth; create schema private;'?'create schema private;':'');
 }
 await db.query(foundation);
 const company='10000000-0000-0000-0000-000000000001';
 const worker='30000000-0000-0000-0000-000000000001';
 await db.query("update company_members set user_id=$1 where company_id=$2 and role='admin'",[users.owner.id,company]);
 for(const n of ['apply_worker_personnel_payload','worker_personnel_payload','save_worker_personnel_profile'])
   await db.query(await read('docs/review/employee-category-candidate/'+n+'.before.sql'));
 await db.query('revoke all on function public.save_worker_personnel_profile(uuid,jsonb) from public,anon,authenticated,service_role');
 await db.query('grant execute on function public.save_worker_personnel_profile(uuid,jsonb) to authenticated');
 await db.query("notify pgrst,'reload schema'");
 await new Promise(resolve=>setTimeout(resolve,1000));
 const requestBody={p_worker_id:worker,p_payload:{name:'Synthetic worker',department:'first',family_members:[]}};
 let response=await rpc('ensure_employee_categories',{p_company:company},sessions.owner.access_token);
 eq(response.status,404);eq((await response.json()).code,'PGRST202');
 response=await rpc('save_worker_personnel_profile',requestBody,sessions.owner.access_token);
 eq(response.status,200);eq((await response.json()).status,'saved');
 eq((await db.query('select department from workers where id=$1',[worker])).rows[0].department,'first');
 requestBody.p_payload.department='second';
 response=await rpc('save_worker_personnel_profile',requestBody,sessions.owner.access_token);
 eq(response.status,200);eq((await response.json()).status,'saved');
 eq((await db.query('select department from workers where id=$1',[worker])).rows[0].department,'second');
 for(const token of [undefined,sessions.othercompany.access_token,sessions.outsider.access_token]){
  response=await rpc('save_worker_personnel_profile',requestBody,token);
  assert.ok(response.status>=400);checks++;
 }
 eq((await db.query("select md5(pg_get_functiondef('auth.uid()'::regprocedure)) value")).rows[0].value,authUidBefore);
 console.log(JSON.stringify({pass:true,checks,legacy_no_category_endpoint:true,real_gotrue:true,real_postgrest:true,fixture_permissions:true,production_changed:false}));
`;
const dir=await mkdtemp(join(tmpdir(),'personnel-legacy-gotrue-'));
try {
 const generated=source.split(start)[0]+test+end+source.split(end)[1];
 const file=join(dir,'proof.mjs');await writeFile(file,generated);
 const result=spawnSync(process.execPath,[file],{stdio:'inherit',env:process.env});
 if(result.error)throw result.error;process.exitCode=result.status??1;
}finally{await rm(dir,{recursive:true,force:true});}
