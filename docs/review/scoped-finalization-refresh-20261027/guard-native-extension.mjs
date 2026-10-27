// Extend the existing real-function Native PG17 fixture at its legacy 25th-day point.
// It runs only against SKO_CHECKOUT_FIXTURE_URL; never against production.
import {readFile,writeFile,unlink} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
import assert from 'node:assert/strict';
const root=fileURLToPath(new URL('.',import.meta.url));
const originalPath=process.env.SKO_EXPLICIT_VERIFIER||resolve(root,'../explicit-finalization-candidate/verify_ordinary_explicit_finalization.mjs');
const original=await readFile(originalPath,'utf8');
const marker="await client.query('insert into explicit_report_finalization_private.reports(company_id,report_id,enabled) values($1,$2,true)',[A,oldRid]);";
assert.equal(original.split(marker).length,2);
const activate=await readFile(resolve(root,'activate.guarded.sql.review-only'),'utf8');
const restore=await readFile(resolve(root,'restore-unused.guarded.sql.review-only'),'utf8');
const before=JSON.parse(await readFile(resolve(root,'before.fixture.json'),'utf8'))[0].result;
let payload=`
 // Only fixture-specific UUID/row/catalog fingerprints are substituted.
 await client.query('create table if not exists public.invoice_detail_lines (id uuid primary key)');
 const sourceTarget=${JSON.stringify(before.target)};
 const sourceRoutineHash=${JSON.stringify(before.routine_catalog_md5)};
 const sourceBusiness=${JSON.stringify(before.business)};
 const liveBusiness={};
 for(const v of sourceBusiness){
  const row=(await client.query("select count(*)::bigint n,md5(coalesce(string_agg(h,'' order by h),'')) h from (select md5(to_jsonb(x)::text) h from public."+v.name+" x)t")).rows[0];
  liveBusiness[v.name]={n:Number(row.n),h:row.h};
 }
 const guardCatalog=await q("select md5(string_agg(p.oid::text||':'||md5(to_jsonb(p)::text),',' order by p.oid)) v from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('explicit_report_finalization_private','explicit_route_finalization_private','shared_daily_report_private','checkout_shared_hours_private') or (n.nspname='public' and p.proname in ('start_shared_report_finalization_edit','finalize_shared_daily_report','read_shared_daily_report_context','sign_daily_report'))");
 const guardRowHash=await q('select md5(to_jsonb(d)::text) v from daily_reports d where id=$1',[oldRid]);
 const guardWorkersHash=await q("select md5(coalesce(string_agg(h,'' order by h),'')) v from(select md5(to_jsonb(w)::text)h from daily_report_workers w where report_id=$1)x",[oldRid]);
 const fixtureGuard=s=>{
  s=s.replaceAll(sourceTarget.id,oldRid).replaceAll(sourceTarget.company_id,A).replaceAll(sourceTarget.row_md5,guardRowHash).replaceAll(sourceTarget.workers_md5,guardWorkersHash).replaceAll(sourceRoutineHash,guardCatalog);
  for(const v of sourceBusiness){const expected="n="+v.n+" and h='"+v.hash+"'";const actual="n="+liveBusiness[v.name].n+" and h='"+liveBusiness[v.name].h+"'";if(!s.includes(expected))throw Error('fixture baseline missing');s=s.replace(expected,actual);}
  return s;
 };
 const activateGuard=fixtureGuard(${JSON.stringify(activate)}),restoreGuard=fixtureGuard(${JSON.stringify(restore)});
 const guardBefore=await business();
 await exec("insert into public.invoice_detail_lines(id) values('00000000-0000-4000-8000-000000000555')");
 await reject(()=>exec(activateGuard),/business_drift/);await exec('rollback');
 await exec("delete from public.invoice_detail_lines where id='00000000-0000-4000-8000-000000000555'");
 await exec(activateGuard);
 eq(await business(),guardBefore,'Scoped activation preserves all business rows');
 await reject(()=>exec(activateGuard),/already_configured/);await exec('rollback');
 await exec(restoreGuard);
 eq(await business(),guardBefore,'Unused scope restore preserves all business rows');
 await reject(()=>exec(restoreGuard),/configuration_changed/);await exec('rollback');
 await exec(activateGuard);
`;
// Preserve String.raw source generation: escape backticks and interpolation in payload.
assert.ok(!payload.includes('`'));
const changed=original.replace(marker,payload);
const output=resolve(originalPath,'../verify_scope_activation.generated.mjs');
try{await writeFile(output,changed);const r=spawnSync(process.execPath,[output,...process.argv.slice(2)],{stdio:'inherit',env:process.env});process.exitCode=r.status??1;}finally{await unlink(output).catch(()=>{});}
