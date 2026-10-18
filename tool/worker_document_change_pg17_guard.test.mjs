import test from 'node:test';
import assert from 'node:assert/strict';
import {validateWorkerDocumentFixtureUrl} from './worker_document_change_pg17_guard.mjs';
const base='postgresql://postgres:fixture-only@127.0.0.1:5432/sko_document_change_fixture';
test('only exact disposable loopback fixture is permitted',()=>{
 assert.equal(validateWorkerDocumentFixtureUrl(base),base);
 assert.equal(validateWorkerDocumentFixtureUrl(base.replace('127.0.0.1','localhost')),base.replace('127.0.0.1','localhost'));
 for(const value of ['',base+'?sslmode=require',base+'#x',base.replace('127.0.0.1','db.example.invalid'),base.replace('sko_document_change_fixture','postgres'),base.replace(':5432',':5433'),base.replace('fixture-only','secret'),base.replace('postgresql:','https:')])assert.throws(()=>validateWorkerDocumentFixtureUrl(value),/Only local disposable/);
});
