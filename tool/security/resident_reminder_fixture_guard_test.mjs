import assert from 'node:assert/strict';
import {resident_reminderFixtureUrl} from './resident_reminder_fixture_guard.mjs';
for (const host of ['127.0.0.1', 'localhost', '[::1]'])
  assert.ok(resident_reminderFixtureUrl(`postgresql://postgres:fixture-only@${host}:5432/sko_resident_reminder_fixture`));
for (const raw of [undefined, '', 'not-url',
 'postgresql://postgres:fixture-only@database.example/sko_resident_reminder_fixture',
 'postgresql://postgres:fixture-only@127.0.0.1/production',
 'postgresql://other:fixture-only@127.0.0.1/sko_resident_reminder_fixture',
 'postgresql://postgres:secret@127.0.0.1/sko_resident_reminder_fixture',
 'postgresql://postgres:fixture-only@127.0.0.1/sko_resident_reminder_fixture?host=database.example',
 'postgresql://postgres:fixture-only@127.0.0.1/sko_resident_reminder_fixture#fragment',
 'https://postgres:fixture-only@127.0.0.1/sko_resident_reminder_fixture'])
 assert.throws(() => resident_reminderFixtureUrl(raw));
console.log('PASS resident_reminder disposable URL guard: valid loopbacks and 10 invalid destinations');

