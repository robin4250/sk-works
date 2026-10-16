import assert from 'node:assert/strict';
import {collectPlatformWindow} from './platform_log_adapter.mjs';
const endpoint=new URL(process.env.SKO_PLATFORM_CLICKHOUSE_URL);
if(endpoint.protocol!=='http:'||endpoint.hostname!=='127.0.0.1'||endpoint.pathname!=='/')throw Error('Disposable loopback ClickHouse only');
async function query(sql,json=false){const url=new URL(endpoint);url.searchParams.set('database','sko_platform_fixture');const r=await fetch(url,{method:'POST',headers:{authorization:`Basic ${Buffer.from('fixture:fixture-only').toString('base64')}`},body:sql+(json?' FORMAT JSON':'')});if(!r.ok)throw Error(`Fixture ClickHouse failure ${r.status}: ${await r.text()}`);return json?r.json():r.text();}
assert.equal((await query("select count() n from system.tables where database='sko_platform_fixture'",true)).data[0].n,'0','Empty disposable database required');
await query("create table logs(id UUID,timestamp DateTime64(9,'UTC'),source String,log_attributes Map(String,String)) engine=Memory");
const from='2026-10-16T10:00:29.123Z',to='2026-10-16T10:05:30.456Z';
const ids=Object.fromEntries(['before','from','inside','to','pg','auth'].map((key,i)=>[key,'00000000-0000-4000-8000-'+String(i+1).padStart(12,'0')]));
const row=(key,timestamp,source='edge_logs',log_attributes={'response.status_code':'403','request.path':'/rest/v1/fixture?secret=x'})=>({id:ids[key],timestamp,source,log_attributes});
const rows=[row('before','2026-10-16 10:00:29.122999999'),row('from','2026-10-16 10:00:29.123000000'),row('inside','2026-10-16 10:05:30.455999999'),row('to','2026-10-16 10:05:30.456000000'),row('pg','2026-10-16 10:01:00.000000000','postgres_logs',{'parsed.sql_state_code':'42501'}),row('auth','2026-10-16 10:01:00.000000000','auth_audit_logs',{'actor_id':'fixture-private-not-projected'})];
await query('insert into logs format JSONEachRow\n'+rows.map(JSON.stringify).join('\n'));
const fetchImpl=async url=>{
 assert.equal(url.origin,'https://api.supabase.com');assert.equal(url.pathname,'/v1/projects/abcdefghijklmnopqrst/analytics/endpoints/logs');assert.equal(url.searchParams.get('iso_timestamp_start'),'2026-10-16T10:00:00.000Z');assert.equal(url.searchParams.get('iso_timestamp_end'),'2026-10-16T10:06:00.000Z');
 const result=await query(url.searchParams.get('sql'),true);
 assert.equal(result.meta.find(x=>x.name==='id').type,'UUID');assert.equal(result.meta.find(x=>x.name==='timestamp').type,"DateTime64(9, 'UTC')");
 if(url.searchParams.get('sql').includes("source = 'edge_logs'"))assert.deepEqual(result.data.map(x=>x.id),[ids.from,ids.inside]);
 return new Response(JSON.stringify({result:result.data,error:null}));
};
const base={from,to,keyEpoch:1,hmacKey:Buffer.alloc(32,4),projectRef:'abcdefghijklmnopqrst',managementToken:'fixture-token-not-production',fetchImpl};
for(const source of ['edge_logs','postgres_logs','auth_audit_logs']){
 const out=await collectPlatformWindow({...base,source});assert.equal(out.events.length,source==='edge_logs'?2:1);
 assert.equal(out.events[0].result,source==='edge_logs'?'forbidden':source==='postgres_logs'?'permission_denied':'unknown');assert.equal(out.events[0].source_tracking,'unavailable');
 assert.doesNotMatch(JSON.stringify(out),/secret|fixture-private|\/rest|actor_id/);
}
console.log('PASS actual ClickHouse unified logs schema, three source projections, UTC nanosecond half-open boundaries, minute envelope, HMAC privacy and unknown origin.');
console.log('LIMIT: Management API response/authorization is a fixture adapter, not a live project call or platform source trust proof.');
