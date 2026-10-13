import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const {PGlite}=await import(process.argv[2]);
const db=new PGlite();
const root=fileURLToPath(new URL('../../../',import.meta.url));
const here=new URL('./',import.meta.url);
const read=p=>fs.readFile(new URL(p,here),'utf8');
const checkpoint=JSON.parse(await read('definition_checkpoint.json'));
try {
  await db.exec(await fs.readFile(root+'tool/fixtures/route_journey_capture/schema.sql','utf8'));
  await db.exec("create role service_role;create function private.get_attendance_capture_capability(uuid) returns jsonb language sql as $$select '{}'::jsonb$$;");
  for(const m of ['20261008204012_route_journey_capture_staged.sql','20261010132957_route_journey_visit_lifecycle.sql']) await db.exec(await fs.readFile(root+'supabase/migrations/'+m,'utf8'));
  // Supply the actual observed definitions and ACLs in an isolated database.
  await db.exec(await read('all_observed_prerequisite_definitions.sql'));
  for(const f of checkpoint.prerequisiteFunctions) {
    await db.exec(`revoke all on function ${f.signature} from public,anon,authenticated,service_role;`);
    const roles=[...f.acl.matchAll(/(?:\{|,)([a-z_]+)=X\//g)].map(m=>m[1]);
    for(const role of roles) await db.exec(`grant execute on function ${f.signature} to ${role};`);
  }
  await db.exec(`insert into companies values('00000000-0000-0000-0000-000000000001');insert into private.route_journey_rollouts values('00000000-0000-0000-0000-000000000001',true)`);
  await db.exec(`insert into workers values('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000003','fixture','active');
    insert into route_assignments values('00000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000001');
    insert into attendance_verifications values('00000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',null,'00000000-0000-0000-0000-000000000004','2026-10-11','clock_in',null,null,'manual',null);
    insert into daily_reports values('00000000-0000-0000-0000-000000000006','00000000-0000-0000-0000-000000000001',null,'00000000-0000-0000-0000-000000000004','2026-10-11','00000000-0000-0000-0000-000000000003','draft');
    insert into storage.objects(bucket_id,name) values('attendance-route-evidence','fixture-preserved.jpg');`);
  const tables=['attendance_verifications','daily_reports','private.route_journey_captures','private.route_journey_visit_events','private.route_journey_visit_archive','storage.objects'];
  const snapshot=async()=>Object.fromEntries(await Promise.all(tables.map(async t=>[t,(await db.query(`select coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) rows,count(*)::int n from ${t} r`)).rows[0]])));
  const before=await snapshot();
  const guard=await read('guard.sql');
  await db.exec(guard);
  // Drift detection rejects ACL edits before replacing any function.
  await db.exec('begin');
  await db.exec('grant execute on function private.route_journey_live_visit_workspace(uuid) to authenticated');
  await assert.rejects(db.exec(guard),/prerequisite drift/);
  await db.exec('rollback');
  await db.exec('begin');
  await db.exec(guard);
  await db.exec(await read('forward_four_functions.sql'));
  assert.deepEqual(await snapshot(),before,'forward changes no existing rows or Storage objects');
  const forward=(await db.query(`select oid::regprocedure::text signature,md5(pg_get_functiondef(oid)) md5,proacl::text acl from pg_proc where oid=any(array[${checkpoint.functions.map(f=>"'"+f.signature+"'::regprocedure").join(',')}])`)).rows;
  for(const f of checkpoint.functions) assert.equal(forward.find(x=>x.signature===f.signature).acl,f.acl,'ACL retained');
  await assert.rejects(db.exec(guard),/prerequisite drift/);
  await db.exec('rollback');
  await db.exec(guard);
  await db.exec(await read('forward_four_functions.sql'));
  await db.exec(await read('guarded_restore.sql'));
  await db.exec(guard);
  assert.deepEqual(await snapshot(),before,'restore changes no rows or Storage objects');
  console.log('PASS observed code+ACL guard, ACL drift rejection, four replacements retain ACL, transaction rollback and original-definition restore. No production writes.');
} catch(e) { console.error(e.message,e.where??''); process.exitCode=1; } finally {await db.close();}
