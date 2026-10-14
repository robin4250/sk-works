import assert from 'node:assert/strict';
import {fixtureUrl} from './fixtures/line_release_pg_adapter.mjs';
const good='postgresql://postgres:fixture-only@127.0.0.1:5432/sko_line_release_fixture';
assert.equal(fixtureUrl(good),good);
for(const bad of [
  good.replace('127.0.0.1','example.com'),good.replace('fixture-only','other-secret'),
  good.replace('/sko_line_release_fixture','/postgres'),good+'?options=-c%20search_path=public',
  good+'?host=example.com',good+'#fragment',good.replace(':5432',':6543'),
  good.replace('postgresql:','http:'),undefined,
]) assert.throws(()=>fixtureUrl(bad));
console.log('LINE release fixture adapter rejects remote, wrong database/credential/port, query overrides and malformed URLs.');
