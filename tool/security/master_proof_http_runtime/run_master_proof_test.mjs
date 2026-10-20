import assert from 'node:assert/strict';
import {test} from 'node:test';
import {configuration,route,FixtureFailure,safeFailure} from './run_master_proof.mjs';
const fixture=()=>({admin:{email:'sko-http-admin-123456abcdef@example.invalid',password:'Synthetic-'+'a'.repeat(48)+'!A1'},other:{email:'sko-http-other_admin-123456abcdef@example.invalid',password:'Synthetic-'+'b'.repeat(48)+'!A1'},publicKey:'fixture.'+'a'.repeat(20),serviceKey:'fixture.'+'b'.repeat(20)});
test('only generated .invalid users are accepted; no production credential input',()=>{
 assert.equal(configuration(fixture()).admin.email,fixture().admin.email);
 for(const email of ['owner@gmail.com','sko-http-admin-123456abcdef@example.com']){const f=fixture();f.admin.email=email;assert.throws(()=>configuration(f),/synthetic_credentials_only/);}
});
test('no caller-selected host or extra connection options',()=>{
 assert.throws(()=>configuration({...fixture(),baseUrl:'https://production.invalid'}),/config_keys/);
 assert.throws(()=>route('https://gateway.invalid/auth/v1/user'),/gateway_origin/);
 assert.throws(()=>route('http://production.invalid/auth/v1/user'),/gateway_origin/);
});
test('only exact reviewed Auth and REST routes go to isolated aliases',()=>{
 assert.equal(route('http://gateway.invalid/auth/v1/user'),'http://auth:9999/user');
 assert.equal(route('http://gateway.invalid/auth/v1/token?grant_type=password'),'http://auth:9999/token?grant_type=password');
 assert.equal(route('http://gateway.invalid/rest/v1/rpc/issue_reauthentication_proof'),'http://rest:3000/rpc/issue_reauthentication_proof');
 for(const path of ['/auth/v1/admin/users','/auth/v1/user?extra=true','/rest/v1/rpc/arbitrary','//outside.invalid/path'])assert.throws(()=>route('http://gateway.invalid'+path));
});
test('credentials and actors must be distinct bounded generated values',()=>{
 const same=fixture();same.other.email=same.admin.email;assert.throws(()=>configuration(same),/distinct_actors_required/);
 const bad=fixture();bad.serviceKey='\r\nsecret';assert.throws(()=>configuration(bad),/fixture_key_invalid/);
});
test('only fixed assertion diagnoses escape; raw credentials and unexpected errors never do',()=>{
 assert.deepEqual(safeFailure(new FixtureFailure('wrong_password_accepted')),{verified:false,failure_code:'wrong_password_accepted'});
 const secret=fixture().admin.password;
 for(const error of [new Error(secret),new FixtureFailure(secret),{code:'wrong_password_accepted',message:secret}]){
  assert.deepEqual(safeFailure(error),{verified:false,failure_code:'master_proof_http_failed'});
  assert.equal(JSON.stringify(safeFailure(error)).includes(secret),false);
 }
});
