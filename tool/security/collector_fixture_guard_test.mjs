import assert from 'node:assert/strict';
import {collectorFixtureUrl} from './collector_fixture_guard.mjs';
for (const host of ['127.0.0.1', 'localhost', '[::1]'])
  assert.ok(collectorFixtureUrl(`postgresql://postgres:fixture-only@${host}:5432/sko_collector_fixture`));
for (const raw of [undefined, '', 'not-url',
 'postgresql://postgres:fixture-only@database.example/sko_collector_fixture',
 'postgresql://postgres:fixture-only@127.0.0.1/production',
 'postgresql://other:fixture-only@127.0.0.1/sko_collector_fixture',
 'postgresql://postgres:secret@127.0.0.1/sko_collector_fixture',
 'postgresql://postgres:fixture-only@127.0.0.1/sko_collector_fixture?host=database.example',
 'postgresql://postgres:fixture-only@127.0.0.1/sko_collector_fixture#fragment',
 'https://postgres:fixture-only@127.0.0.1/sko_collector_fixture'])
 assert.throws(() => collectorFixtureUrl(raw));
console.log('PASS collector disposable URL guard: valid loopbacks and 10 invalid destinations');
