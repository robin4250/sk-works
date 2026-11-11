import test from 'node:test';
import assert from 'node:assert/strict';
import {blockedEnvironment,fixtureTarget} from './fixture-target.mjs';
test('fixed disposable loopback database is the only target',()=>{
 const target=fixtureTarget({});assert.equal(target.host,'127.0.0.1');
 assert.equal(target.database,'sko_expense_manager_removal_fixture');assert.equal(target.port,55438);
 assert.equal(target.ssl,false);assert.ok(Object.isFrozen(target));
});
for(const name of blockedEnvironment) test(`${name} cannot redirect the fixture`,()=>{
 assert.throws(()=>fixtureTarget({[name]:'external-target'}),/External database configuration/);
});
