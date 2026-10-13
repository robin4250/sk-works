import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const script=fileURLToPath(new URL('./verify_route_journey_postgres_races.mjs',import.meta.url));
for(const connectionString of [
 'postgres://fixture@127.0.0.1/sko_route_capture_race_fixture?host=example.com',
 'postgres://fixture@127.0.0.1/sko_route_capture_race_fixture?host=/tmp',
 'postgres://fixture@127.0.0.1/sko_route_capture_race_fixture?dbname=production',
 'postgresql://fixture@localhost/sko_route_capture_race_fixture?options=-csearch_path=public',
 'http://fixture@127.0.0.1/sko_route_capture_race_fixture',
 'postgres://fixture@example.com/sko_route_capture_race_fixture',
 'postgres://fixture@127.0.0.1/production',
 'postgres://fixture@127.0.0.1/sko_route_capture_race_fixture#host',
]) {
 const result=spawnSync(process.execPath,[script,'/nonexistent-pg-must-never-load'],
  {env:{...process.env,SKO_ROUTE_RACE_DATABASE_URL:connectionString},encoding:'utf8',timeout:5000});
 assert.notEqual(result.status,0);assert.match(result.stderr,/Only local disposable sko_route_capture_race_fixture database is permitted/);
 assert.doesNotMatch(result.stderr,/ERR_MODULE_NOT_FOUND/);
}
console.log('PASS URL guard: protocols, remote host, database, pg host/query override and fragment rejected before importing client or connecting');
