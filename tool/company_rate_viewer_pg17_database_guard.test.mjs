import assert from 'node:assert/strict';import{validateRateViewerFixtureUrl}from'./company_rate_viewer_pg17_database_guard.mjs';
const allowed='postgresql://postgres:fixture-only-password@127.0.0.1:5432/sko_company_rate_viewer_fixture';assert.equal(validateRateViewerFixtureUrl(allowed),allowed);
for(const invalid of[undefined,'postgresql://postgres:fixture-only-password@remote.example:5432/sko_company_rate_viewer_fixture',allowed.replace('sko_company_rate_viewer_fixture','postgres'),allowed+'?sslmode=require',allowed.replace('fixture-only-password','real-password'),allowed.replace(':5432',':5433')])assert.throws(()=>validateRateViewerFixtureUrl(invalid));
console.log('PASS rate viewer disposable database URL guard');
