import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.argv[2]);
const db = new PGlite();
const read = path => fs.readFile(new URL(path, import.meta.url), 'utf8');
try {
  await db.exec(await read('./fixtures/route_journey_capture/schema.sql'));
  await db.exec(`alter table attendance_verifications add column confirmed_at timestamptz;
    alter table attendance_verifications add column photo_storage_path text;
    grant select,insert on attendance_verifications to authenticated;
    grant insert on daily_reports,daily_report_workers to authenticated;`);
  const legacy = await read('../supabase/migrations/20261008124940_gps_shift_work_date_evidence.sql');
  const start = legacy.indexOf('CREATE OR REPLACE FUNCTION private.link_daily_report_attendance_evidence');
  const end = legacy.indexOf('CREATE OR REPLACE FUNCTION public.daily_report_clocked_in_destinations', start);
  assert.ok(start >= 0 && end > start);
  await db.exec(legacy.slice(start, end));
  await db.exec(`create function public.link_daily_report_attendance_evidence(p_report_id uuid)
    returns integer language sql security invoker set search_path='' as
    $$select private.link_daily_report_attendance_evidence(p_report_id)$$;
    grant execute on function public.link_daily_report_attendance_evidence(uuid) to authenticated;`);
  for (const migration of ['20261008204012_route_journey_capture_staged.sql',
    '20261010132957_route_journey_visit_lifecycle.sql','20261010222139_route_manual_visit_capture.sql']) {
    await db.exec(await read(`../supabase/migrations/${migration}`));
  }
  const id = n => `50000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
  const [company, user, worker, route, stop, report, source, out, arrival, move] = Array.from({length:10},(_,i)=>id(i+1));
  await db.exec(`set test.uid='${user}'; insert into companies values('${company}');
    insert into company_members values('${company}','${user}','member');
    insert into workers values('${worker}','${company}','${user}','本人','active');
    insert into route_assignments values('${route}','${company}');
    insert into route_stops values('${stop}','${route}',null,1,'予定住所','実際の現場');
    insert into private.route_journey_rollouts values('${company}',true); set role authenticated;`);
  // Match manual attendance repository INSERTs; never pre-populate report IDs.
  await db.exec(`insert into attendance_verifications(id,company_id,worker_id,route_assignment_id,work_date,event_type,verification_mode,confirmed_at)
    values('${source}','${company}','${worker}','${route}','2026-10-10','clock_in','manual','2026-10-09T23:00:00Z')`);
  const payload = at => `'${JSON.stringify({capture_contract_version:1,gps_capture_status:'missing',photo_capture_status:'missing',attempted_at:at})}'::jsonb`;
  await db.query(`select public.save_route_journey_visit('${arrival}','${source}','${stop}','company',${payload('2026-10-10T00:00:00Z')},'start','${arrival}')`);
  await db.query(`select public.save_route_journey_visit('${move}','${source}','${stop}','company',${payload('2026-10-10T01:00:00Z')},'end','${arrival}')`);
  await db.exec(`insert into attendance_verifications(id,company_id,worker_id,route_assignment_id,work_date,event_type,source_clock_in_id,verification_mode,confirmed_at)
    values('${out}','${company}','${worker}','${route}','2026-10-10','clock_out','${source}','manual','2026-10-10T08:00:00Z');
    insert into daily_reports values('${report}','${company}',null,'${route}','2026-10-10','${user}','draft');
    insert into daily_report_workers values('${report}','${worker}');`);
  const link = async reportId => (await db.query(`select public.link_daily_report_attendance_evidence('${reportId}') n`)).rows[0].n;
  assert.equal(await link(report),0,'legacy photo-only linker reproduces missing manual attendance');
  assert.equal((await db.query(`select public.link_route_journey_report('${report}') n`)).rows[0].n,0);
  assert.deepEqual((await db.query(`select public.route_journey_report_evidence('${report}') v`)).rows[0].v,[]);
  await db.exec('reset role');
  const migration = await read('../supabase/migrations/20261011000100_link_daily_report_time_only_evidence.sql');
  // A same-name upstream change must abort before replacing the function.
  await db.exec('begin');
  await db.exec(legacy.slice(start,end).replace('v_count integer;', 'v_count integer; -- upstream drift'));
  await assert.rejects(db.exec(migration), /RPCが更新されています/);
  await db.exec('rollback');
  await db.exec(migration);
  await db.exec('set role authenticated');
  assert.equal(await link(report),2);
  assert.equal((await db.query(`select public.link_route_journey_report('${report}') n`)).rows[0].n,2);
  // Same predicates as saved-report reader: linked report and destination.
  const attendance=(await db.query(`select event_type,confirmed_at,verification_mode from attendance_verifications
    where daily_report_id='${report}' and route_assignment_id='${route}' order by confirmed_at`)).rows;
  assert.deepEqual(attendance.map(r=>r.event_type),['clock_in','clock_out']);
  const visits=(await db.query(`select public.route_journey_report_evidence('${report}') v`)).rows[0].v;
  assert.equal(visits.length,2);assert.ok(visits.every(r=>r.verification_mode==='manual'&&r.stop_label==='実際の現場'));
  const chronological=[...attendance.map(r=>({kind:r.event_type,at:Date.parse(r.confirmed_at)})),
    ...visits.map(r=>({kind:r.visit_kind,at:Date.parse(r.payload.attempted_at)}))].sort((a,b)=>a.at-b.at);
  assert.deepEqual(chronological.map(r=>r.kind),['clock_in','start','end','clock_out']);
  assert.equal(await link(report),0,'retry does not relink or duplicate attendance');
  assert.equal((await db.query(`select count(*)::int n from attendance_verifications where daily_report_id='${report}'`)).rows[0].n,2);
  // Preserve date/destination/company and already attached report boundaries.
  await db.exec('reset role');
  const site=id(11), siteReport=id(12), existingReport=id(13);
  await db.exec(`insert into sites values('${site}','通常現場');
    insert into daily_reports values('${siteReport}','${company}','${site}',null,'2026-10-10','${user}','draft');
    insert into daily_reports values('${existingReport}','${company}','${site}',null,'2026-10-09','${user}','draft');`);
  const insert = (n, values) => db.exec(`insert into attendance_verifications(id,company_id,worker_id,site_id,work_date,event_type,verification_mode,confirmed_at,photo_storage_path,daily_report_id)
    values('${id(n)}','${values.company??company}','${worker}','${values.site??site}',${values.date===null?'null':"'"+(values.date??'2026-10-10')+"'"},'clock_in','${values.mode??'manual'}','${values.at??'2026-10-09T23:30:00Z'}',${values.photo?"'"+values.photo+"'":'null'},${values.report?"'"+values.report+"'":'null'})`);
  await insert(20,{});await insert(21,{mode:'location_photo'});await insert(22,{mode:'location_photo',photo:'legacy.jpg'});
  await insert(23,{date:null});await insert(24,{date:'2026-10-09'});await insert(25,{site:id(30)});
  await insert(26,{company:id(31)});await insert(27,{report:existingReport});
  await db.exec('set role authenticated');
  assert.equal(await link(siteReport),4,'manual, failed-photo, uploaded-photo, legacy JST date all link');
  assert.deepEqual((await db.query(`select id from attendance_verifications where daily_report_id='${siteReport}' order by id`)).rows.map(r=>r.id),[20,21,22,23].map(id));
  assert.equal((await db.query(`select daily_report_id from attendance_verifications where id='${id(27)}'`)).rows[0].daily_report_id,existingReport);
  await db.exec(`set test.uid='${id(99)}'`);
  await assert.rejects(link(siteReport),/権限/);
  await assert.rejects(link(id(98)),/確認できません/);
  console.log('PASS actual manual attendance INSERT → visit RPC → report save → attendance link → route link → saved report read, chronology, retries and scope boundaries');
} finally { await db.close(); }
