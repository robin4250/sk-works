// Extends the source-bound actual save/sign/payroll shared suite. Source guard
// code is captured/pinned; auth/clock entry surroundings remain synthetic.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
let base=await readFile('tool/verify_shared_daily_report.mjs','utf8');
const install=" await exec(await readFile('docs/candidates/shared_daily_report.sql.review-only','utf8'));";
assert.equal(base.split(install).length,2);
base=base.replace(install,install+String.raw`
 const groupFixture=JSON.parse(await readFile('tool/security/shared_group_lock_source_fixture.json','utf8'));
 await exec(groupFixture.normalizer_definition);await exec(groupFixture.normalizer_trigger_definition);
 eq(await q("select md5(prosrc) v from pg_proc where oid='private.validate_attendance_shift_evidence()'::regprocedure"),groupFixture.normalizer_source_md5,'Actual normalizer source is unchanged');
 await exec(await readFile('docs/candidates/shared_daily_report_group_lock.sql.review-only','utf8'));
`);
const beforeCommit="  await sharedRaceClient.query('rollback');await exec('commit');";
assert.equal(base.split(beforeCommit).length,2);
base=base.replace(beforeCommit,String.raw`
  await sharedRaceClient.query('rollback');
  await sharedRaceClient.query('begin');await sharedRaceClient.query('reset role');
  await sharedRaceClient.query("set local lock_timeout='100ms'");
  await reject(()=>sharedRaceClient.query("insert into public.attendance_verifications values($1,$2,$3,$4,null,'clock_in','2026-10-28 08:00Z','2026-10-28',null,null,null)",[id(8190),A,W4,SITE]),/lock timeout/);
  await sharedRaceClient.query('rollback');await exec('commit');
  await sharedRaceClient.query("insert into public.attendance_verifications values($1,$2,$3,$4,null,'clock_in','2026-10-28 08:00Z','2026-10-28',null,null,null)",[id(8190),A,W4,SITE]);
  const lateCrew=await sharedCall(U,id(80),'select public.read_shared_daily_report_context($1) v',[firstRace.report_id]);
  eq(lateCrew.supervisor_ready,false,'Post-freeze member cannot silently be excluded from final signature');
  assert.ok(lateCrew.supervisor_pending_reasons.includes('work_roster_correction_required'));
  await sharedRaceClient.query('begin');
  await sharedRaceClient.query('select payroll_scope_private.lock_scopes($1::jsonb,false)',[JSON.stringify([{cid:A,wid:W6,day:'2026-11-03'}])]);
  await exec('begin');await exec("set local lock_timeout='100ms'");
  await client.query("insert into attendance_verifications(id,company_id,worker_id,site_id,event_type,confirmed_at,work_date) values($1,$2,$3,$4,'clock_in','2026-11-03 08:00Z','2026-11-03')",[id(8192),A,W4,SITE]);
  await reject(()=>client.query("insert into attendance_verifications(id,company_id,worker_id,site_id,event_type,confirmed_at,work_date) values($1,$2,$3,$4,'clock_in','2026-11-03 08:00Z','2026-11-03')",[id(8193),A,W6,SITE]),/batch_scopes_must_be_prepared/);
  await exec('rollback');await sharedRaceClient.query('rollback');
  eq(await q('select count(*)::int v from attendance_verifications where id=any($1::uuid[])',[[id(8192),id(8193)]]),0,'Unprepared batch rejects before blocked second worker scope and rolls back first row');
  await exec('begin');await exec("set local lock_timeout='100ms'");
  await client.query("insert into attendance_verifications(id,company_id,worker_id,site_id,event_type,confirmed_at,work_date) values($1,$2,$3,$4,'clock_in','2026-11-03 08:00Z','2026-11-03')",[id(8194),A,W4,SITE]);
  await reject(()=>client.query("insert into attendance_verifications(id,company_id,worker_id,site_id,event_type,confirmed_at,work_date) values($1,$2,$3,$4,'clock_in','2026-12-03 08:00Z','2026-12-03')",[id(8195),A,W4,SITE]),/batch_scopes_must_be_prepared/);
  await exec('rollback');
  eq(await q('select count(*)::int v from attendance_verifications where id=any($1::uuid[])',[[id(8194),id(8195)]]),0,'Same worker across months cannot add a later canonical scope after a group lock');

`);
const folder=await mkdtemp(join(tmpdir(),'shared-group-proof-'));
try{const file=join(folder,'proof.mjs');await writeFile(file,base);
 const result=spawnSync(process.execPath,[file,process.argv[2]],{stdio:'inherit',env:process.env});
 if(result.error)throw result.error;process.exitCode=result.status??1;
 if(result.status===0)console.log(JSON.stringify({pass:true,group_lock_order:true,production_changed:false}));
}finally{await rm(folder,{recursive:true,force:true});}
