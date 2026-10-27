// Actual PostgreSQL row-lock integration, synthetic auth rows only.
import {createRequire} from 'node:module';
import assert from 'node:assert/strict';
import fs from 'node:fs';
const {Client}=createRequire(process.cwd()+'/tool/security/fixture_dependencies/package.json')('pg');
const clients=[new Client(),new Client()];
try {
  await Promise.all(clients.map(c=>c.connect()));
  for(const c of clients) await c.query("select set_config('test.actor','00000000-0000-0000-0000-000000000001',false),set_config('test.jwt','{\"role\":\"authenticated\",\"session_id\":\"00000000-0000-0000-0000-000000000002\",\"is_anonymous\":false}',false)");
  const [operation,master]=clients;
  await operation.query('begin');
  await operation.query("select private.require_lifecycle_features(array['affiliation_switch'])");
  await master.query("set lock_timeout='150ms'");
  await assert.rejects(master.query("select public.set_master_feature_enabled('affiliation_switch',false)"),e=>e.code==='55P03');
  await operation.query('commit');
  await master.query("select public.set_master_feature_enabled('affiliation_switch',false)");
  await assert.rejects(operation.query("select private.require_lifecycle_features(array['affiliation_switch'])"),e=>e.code==='42501');
  // Reverse order: uncommitted OFF prevents a new operation starting on stale ON.
  await master.query("select public.set_master_feature_enabled('affiliation_switch',true)");
  await master.query('begin');
  await master.query("select public.set_master_feature_enabled('affiliation_switch',false)");
  await operation.query("set lock_timeout='150ms'");
  await assert.rejects(operation.query("select private.require_lifecycle_features(array['affiliation_switch'])"),e=>e.code==='55P03');
  await master.query('commit');
  await assert.rejects(operation.query("select private.require_lifecycle_features(array['affiliation_switch'])"),e=>e.code==='42501');
  const before=await master.query('select count(*)::int n from private.lifecycle_feature_audit');
  const restore=fs.readFileSync('docs/review/master-lifecycle-controls/sql/restore-unused.sql.review-only','utf8');
  await assert.rejects(master.query(restore),e=>e.message==='lifecycle_restore_used');
  await master.query('rollback');
  const after=await master.query('select count(*)::int n from private.lifecycle_feature_audit');
  assert.deepEqual(after.rows,before.rows);
  console.log('Concurrent OFF/operation ordering and used-restore rejection passed.');
} finally {
  await Promise.all(clients.map(async c=>{try{await c.query('rollback');}finally{await c.end();}}));
}
