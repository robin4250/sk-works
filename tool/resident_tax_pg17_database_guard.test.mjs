import test from 'node:test';
import assert from 'node:assert/strict';
import {validateResidentTaxFixtureUrl} from './resident_tax_pg17_database_guard.mjs';
const allowed='postgres://postgres:fixture-only-password@127.0.0.1:5432/sko_resident_tax_fixture';
test('only the exact local disposable fixture is accepted',()=>{
  assert.equal(validateResidentTaxFixtureUrl(allowed),allowed);
  for(const host of ['localhost','[::1]']) {
    assert.equal(validateResidentTaxFixtureUrl(allowed.replace('127.0.0.1',host)),allowed.replace('127.0.0.1',host));
  }
});
test('remote, production-like and ambiguous connections are rejected before connecting',()=>{
  for(const value of [undefined,'', 'not-a-url',
    allowed.replace('127.0.0.1','db.example.supabase.co'),
    allowed.replace('127.0.0.1','127.0.0.2'),
    allowed.replace('/sko_resident_tax_fixture','/postgres'),
    allowed.replace('5432','6543'), allowed.replace('fixture-only-password','secret'),
    allowed.replace('postgres://postgres:','postgres://service_role:'),
    allowed.replace('postgres://','https://'),allowed+'?sslmode=require',allowed+'#fragment',
  ]) assert.throws(()=>validateResidentTaxFixtureUrl(value),/disposable resident-tax fixture/);
});
