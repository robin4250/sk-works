import assert from 'node:assert/strict';import{validateIncomeViewerFixtureUrl}from'./company_income_viewer_pg17_database_guard.mjs';
const allowed='postgresql://postgres:fixture-only-password@127.0.0.1:5432/sko_company_income_viewer_fixture';assert.equal(validateIncomeViewerFixtureUrl(allowed),allowed);
for(const invalid of[undefined,'postgresql://postgres:fixture-only-password@remote.example:5432/sko_company_income_viewer_fixture',allowed.replace('sko_company_income_viewer_fixture','postgres'),allowed+'?sslmode=require',allowed.replace('fixture-only-password','real-password'),allowed.replace(':5432',':5433')])assert.throws(()=>validateIncomeViewerFixtureUrl(invalid));
console.log('PASS income viewer disposable database URL guard');
