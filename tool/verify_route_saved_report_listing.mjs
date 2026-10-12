// Disposable in-memory SQL only; never accepts an application database URL.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve, dirname} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const {PGlite} = await import(pathToFileURL(resolve(process.argv[2])).href);
const db = new PGlite();
const id = n => `10000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const actor=id(1), other=id(2), company=id(3), worker=id(4), route=id(5);
try {
  await db.exec(`create role authenticated;create role anon;
    create schema private;create schema auth;
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('fixture.uid',true),'')::uuid$$;
    create function private.account_access_allowed() returns boolean language sql stable as $$select coalesce(current_setting('fixture.blocked',true),'false') <> 'true'$$;
    create table public.company_members(company_id uuid,user_id uuid);
    insert into public.company_members values('${company}','${actor}'),('${company}','${other}');
    create table public.route_assignments(id uuid,company_id uuid,route_name text);
    insert into public.route_assignments values('${route}','${company}','Saved route');
    create table public.daily_reports(id uuid,signature_json jsonb);
    insert into public.daily_reports values('${id(90)}','{"strokes":[[{"x":0.2,"y":0.3},{"x":0.8,"y":0.6}]]}');`);
  await db.exec(readFileSync(resolve(root,'supabase/migrations/20261011121738_route_visit_report_documents.sql'),'utf8'));
  for (let i=0;i<6;i++) {
    await db.exec(`insert into private.route_visit_reports(
      id,company_id,created_by,source_clock_in_id,route_assignment_id,route_stop_id,
      start_capture_id,end_capture_id,report_date,site_name,status,workers,
      representative_signature_json,supervisor_signature_json,created_at)
      values('${id(10+i)}','${i===5?id(99):company}','${i===3?other:actor}',
      '${id(20)}','${route}','${id(30+i)}','${id(40+i)}','${id(50+i)}',
      '${i===4?'2026-11-01':'2026-10-12'}','Visit ${i}','${i===2?'reporter_signed':'completed'}',
      '[{"worker_id":"${worker}"}]',
      '{"strokes":[[{"x":0.2,"y":0.3},{"x":0.8,"y":0.6}]]}',
      '{"strokes":[[{"x":0.1,"y":0.4},{"x":0.9,"y":0.5}]]}',
      '2026-10-12T0${i}:00:00Z');`);
  }
  const snapshot=async()=>({
    visits:(await db.query('select * from private.route_visit_reports order by id')).rows,
    daily:(await db.query('select * from public.daily_reports order by id')).rows,
    guards:(await db.query("select proname,prosrc,proacl from pg_proc where proname in ('account_access_allowed','route_visit_report_command','save_route_visit_report_signature') order by proname")).rows,
    protection:(await db.query("select relrowsecurity,relacl from pg_class where oid='private.route_visit_reports'::regclass")).rows,
  });
  const before=await snapshot();
  const migration=readFileSync(resolve(root,'supabase/migrations/20261012034936_route_saved_report_listing.sql'),'utf8');
  await db.exec(migration);
  await db.exec(migration);
  await db.exec(`set role authenticated;set fixture.uid='${actor}'`);
  const list=async(offset=0,limit=500,subject=worker)=>(await db.query(
    'select public.list_saved_route_visit_reports($1,$2,$3,$4,$5) as value',
    ['2026-10-01','2026-11-01',subject,offset,limit])).rows[0].value;
  const reports=await list();
  assert.deepEqual(reports.map(r=>r.id),[id(10),id(11),id(12)]);
  assert.equal(reports.length+1,4,'three visit documents and one separate checkout document');
  assert.equal(new Set(reports.map(r=>r.start_capture_id)).size,3);
  assert.deepEqual(await list(1,1),[reports[1]]);
  assert.deepEqual(await list(0,500,id(98)),[]);
  await assert.rejects(db.query('select * from private.route_visit_reports'),/permission denied/);
  await assert.rejects(db.query("select public.list_saved_route_visit_reports('2026-01-01','2026-11-01')"),/invalid report range/);
  await assert.rejects(db.query("select public.list_saved_route_visit_reports('2026-10-01','2026-11-01',null,0,501)"),/invalid report range/);
  await db.exec(`set fixture.uid='${other}'`);
  assert.deepEqual((await list()).map(r=>r.id),[id(13)]);
  await db.exec(`set fixture.blocked='true'`);
  await assert.rejects(list(),/account unavailable/);
  await db.exec(`set fixture.blocked='false';set fixture.uid=''`);
  await assert.rejects(list(),/account unavailable/);
  await db.exec('reset role;set role anon');
  await assert.rejects(list(),/permission denied/);
  await db.exec('reset role');
  assert.deepEqual(await snapshot(),before,'documents, signatures, guards, ACL and RLS unchanged');
  console.log('PASS: all three saved visits, exact identities, worker/month pagination, actor/company/account restrictions, signatures and canonical report preserved');
} finally { await db.close(); }
