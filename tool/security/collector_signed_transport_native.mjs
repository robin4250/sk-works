// CI-only native adapter wrapper. Existing signed candidate files stay exact.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
import {collectorFixtureUrl} from './collector_fixture_guard.mjs';

const root=new URL('../../',import.meta.url);
const source=path=>new URL(path,root);
const sha256=data=>createHash('sha256').update(data).digest('hex');
const blob=data=>createHash('sha1').update(Buffer.from(`blob ${data.length}\0`)).update(data).digest('hex');
let phase='disposable-destination';
try {
  assert.equal(process.env.CI,'true','Dedicated CI only');
  assert.equal(process.platform,'linux','Linux CI fixture required');
  assert.ok(!Object.keys(process.env).some(key=>/^SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|URL|SERVICE_ROLE_KEY|SECRET_KEY|PROJECT_REF)$/.test(key)),
    'Hosted project configuration is not accepted');
  const destination=new URL(collectorFixtureUrl(process.env.SKO_COLLECTOR_FIXTURE_URL));
  assert.equal(destination.hostname,'127.0.0.1');
  assert.equal(destination.port,'5432');

  phase='exact-existing-source';
  const candidate='tool/security/collector_signed_transport_candidate/';
  const manifest=JSON.parse(await readFile(source(candidate+'manifest.json'),'utf8'));
  for(const file of manifest.files) {
    assert.equal(sha256(await readFile(source(candidate+file.path))),file.sha256,file.path);
  }
  assert.equal(manifest.collector_sha256,'b96f6e4365e2e992886f38dad0f777e55665f18b03525cddf4edbdf746348207');
  const adapter='tool/security/collector_storage_pg_adapter.mjs';
  const guard='tool/security/collector_fixture_guard.mjs';
  assert.equal(blob(await readFile(source(adapter))),'79f25c69d636627699dcf833bf6cb35b4c542112');
  assert.equal(blob(await readFile(source(guard))),'41ef08ee8513d1f7670b1ba75e6c8e6a3bca92e6');

  phase='existing-native-adapter-integration';
  const {stdout,stderr}=await promisify(execFile)(process.execPath,[
    fileURLToPath(source(candidate+'integration.mjs')),
    fileURLToPath(source(adapter)),
    fileURLToPath(source('docs/candidates/security_collector_storage_v1_20261020.sql.review-only')),
  ],{cwd:fileURLToPath(root),encoding:'utf8',timeout:120000,maxBuffer:262144,
    env:{...process.env,SKO_COLLECTOR_FIXTURE_URL:destination.href}});
  // The unchanged integration's engine/native fields are old PGlite literals.
  // Native execution is established by the exact adapter, which independently
  // requires native server_version_num 17 and an empty disposable catalog.
  assert.equal(stderr.trim(),'');
  const result=JSON.parse(stdout.trim());
  assert.equal(result.pass,true);
  assert.equal(result.checks,14);
  assert.equal(result.real_loopback_http,true);
  assert.equal(result.real_hmac,true);
  assert.equal(result.exact_collector_sql,true);
  assert.equal(result.master_proof_exercised,false);
  assert.equal(result.production_changed,false);
  console.log(JSON.stringify({pass:true,checks:result.checks,
    engine:'native PostgreSQL 17 via existing disposable adapter',native_postgres:true,
    real_loopback_http:true,real_hmac:true,exact_collector_sql:true,
    original_fixture_report_uses_legacy_pglite_labels:true,
    master_proof_exercised:false,production_changed:false}));
} catch {
  // Child output can contain SQL details; do not forward it or connection data.
  console.error(JSON.stringify({pass:false,phase,private_error_omitted:true,production_changed:false}));
  process.exitCode=1;
}
