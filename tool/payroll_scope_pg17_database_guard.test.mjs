import assert from 'node:assert/strict';
import {validatePayrollScopeFixtureUrl as check} from './payroll_scope_pg17_database_guard.mjs';
const valid='postgresql://postgres:fixture-only-password@127.0.0.1:5432/sko_payroll_scope_fixture';assert.equal(check(valid),valid);
for(const url of [undefined,'postgresql://postgres:fixture-only-password@prod.example:5432/sko_payroll_scope_fixture',valid.replace('sko_payroll_scope_fixture','postgres'),valid.replace('fixture-only-password','secret'),valid+'?sslmode=require',valid.replace(':5432',':6543'),valid.replace('postgres:','admin:')])assert.throws(()=>check(url),/Only the local disposable/);
console.log('PASS payroll-scope fixture URL guard');
