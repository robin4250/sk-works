// Synthetic stack: actual GoTrue JWT and PostgREST against review-only guard.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
const source=await readFile('tool/company_checkout_real_gotrue_e2e.mjs','utf8');
const start=" phase='unchanged-checkout-foundation';",end='}catch(error){';
assert.equal(source.split(start).length,2);assert.equal(source.split(end).length,2);
const test=String.raw`
 phase='qualification-reference-fixture';
 await db.query(\`create schema private;
 create table public.company_members(company_id uuid,user_id uuid,role text);
 create table public.qualification_master(id uuid primary key,company_id uuid not null,category text);
 create table public.worker_qualifications(id uuid primary key,qualification_master_id uuid references public.qualification_master(id) on delete restrict);
 create table public.qualification_master_aliases(id uuid primary key,qualification_master_id uuid references public.qualification_master(id) on delete cascade);
 create table private.qualification_submissions(id uuid primary key,qualification_master_id uuid references public.qualification_master(id));
 alter table public.qualification_master enable row level security;
 revoke all on public.qualification_master from public, anon;
 grant select on public.company_members to authenticated;
 grant select,delete on public.qualification_master to authenticated;
 create policy read_member on public.qualification_master for select to authenticated using (exists(select 1 from public.company_members cm where cm.company_id=qualification_master.company_id and cm.user_id=auth.uid()));
 create policy admin_all on public.qualification_master for all to authenticated using(exists(select 1 from public.company_members cm where cm.company_id=qualification_master.company_id and cm.user_id=auth.uid() and cm.role in ('owner','admin'))) with check(exists(select 1 from public.company_members cm where cm.company_id=qualification_master.company_id and cm.user_id=auth.uid() and cm.role in ('owner','admin')));\`);
 await db.query(await read('docs/review/qualification-master-access/delete-preserve.sql.review-only'));
 const id=n=>\`00000000-0000-0000-0000-\${String(n).padStart(12,'0')}\`;
 const company=id(1),foreign=id(2);
 await db.query("insert into company_members values($1,$2,'owner'),($3,$4,'owner')",[company,users.owner.id,foreign,users.othercompany.id]);
 for(let n=10;n<=14;n++)await db.query("insert into qualification_master values($1,$2,'fixture')",[id(n),company]);
 await db.query('insert into worker_qualifications values($1,$2)',[id(30),id(10)]);
 await db.query('insert into qualification_master_aliases values($1,$2)',[id(31),id(11)]);
 await db.query('insert into private.qualification_submissions values($1,$2)',[id(32),id(12)]);
 await db.query("notify pgrst,'reload schema'");await new Promise(resolve=>setTimeout(resolve,1000));
 for(const n of [10,11,12]){
  let response=await request('/rest/v1/qualification_master?id=eq.'+id(n),{method:'DELETE',token:sessions.owner.access_token});
  eq(response.status,409);eq((await response.json()).code,'23503');
  eq((await db.query('select count(*)::int n from qualification_master where id=$1',[id(n)])).rows[0].n,1);
 }
 let response=await request('/rest/v1/qualification_master?id=eq.'+id(13),{method:'DELETE',token:sessions.othercompany.access_token});
 assert.ok([200,204].includes(response.status));checks++;
 eq((await db.query('select count(*)::int n from qualification_master where id=$1',[id(13)])).rows[0].n,1);
 response=await request('/rest/v1/qualification_master?id=eq.'+id(13),{method:'DELETE'});
 assert.ok(response.status>=400);checks++;
 eq((await db.query('select count(*)::int n from qualification_master where id=$1',[id(13)])).rows[0].n,1);
 response=await request('/rest/v1/qualification_master?id=eq.'+id(14),{method:'DELETE',token:sessions.owner.access_token});
 assert.ok([200,204].includes(response.status));checks++;
 eq((await db.query('select count(*)::int n from qualification_master where id=$1',[id(14)])).rows[0].n,0);
 eq((await db.query('select count(*)::int n from qualification_master_aliases where id=$1',[id(31)])).rows[0].n,1);
 eq((await db.query('select count(*)::int n from private.qualification_submissions where id=$1',[id(32)])).rows[0].n,1);
 // Exercise a forward recovery: remove candidate manager permissions only.
 await db.query(await read('docs/review/qualification-master-access/policy.sql.review-only'));
 await db.query(await read('docs/review/qualification-master-access/retain-protection-recovery.sql.review-only'));
 response=await request('/rest/v1/qualification_master?id=eq.'+id(11),{method:'DELETE',token:sessions.owner.access_token});
 eq(response.status,409);eq((await response.json()).code,'23503');
 eq((await db.query('select count(*)::int n from qualification_master_aliases where id=$1',[id(31)])).rows[0].n,1);
 eq((await db.query("select count(*)::int n from pg_policies where schemaname='public' and tablename='qualification_master' and policyname like 'managers can %'")).rows[0].n,0);
 eq((await db.query("select md5(pg_get_functiondef('auth.uid()'::regprocedure)) v")).rows[0].v,authUidBefore);
 console.log(JSON.stringify({pass:true,checks,real_gotrue:true,real_postgrest:true,fixture_permissions:true,production_changed:false}));
`;
const dir=await mkdtemp(join(tmpdir(),'qualification-delete-proof-'));
try{const file=join(dir,'proof.mjs');await writeFile(file,source.split(start)[0]+test.replaceAll('\\`','`').replaceAll('\\${','${')+end+source.split(end)[1]);const result=spawnSync(process.execPath,[file],{stdio:'inherit',env:process.env});if(result.error)throw result.error;process.exitCode=result.status??1;}finally{await rm(dir,{recursive:true,force:true});}
