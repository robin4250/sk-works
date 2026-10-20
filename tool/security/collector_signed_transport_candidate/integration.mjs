import assert from 'node:assert/strict';import fs from 'node:fs/promises';import {createHash,randomBytes} from 'node:crypto';import http from 'node:http';import {Readable} from 'node:stream';
import {createCollectorSignedHandler,createCollectorPgSink,signCollectorBytes} from './collector_signed_transport.mjs';
const {PGlite}=await import(process.argv[2]);const db=new PGlite();let server;let checks=0;
const check=(a,b)=>{assert.equal(a,b);checks++;};
try{
 if(!process.argv[3])throw Error('Explicit reviewed collector SQL path required');
 const sql=await fs.readFile(process.argv[3],'utf8');
 check(createHash('sha256').update(sql).digest('hex'),'b96f6e4365e2e992886f38dad0f777e55665f18b03525cddf4edbdf746348207');
 await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create role sko_security_collector_ingest nologin noinherit;create schema private;create schema auth;
 create function auth.uid() returns uuid language sql as $$select null::uuid$$;
 create function private.account_access_allowed() returns boolean language sql as $$select false$$;
 create function public.is_current_user_master_admin() returns boolean language sql as $$select false$$;
 create function private.consume_reauthentication_proof(text,jsonb,text) returns void language plpgsql as $$begin raise exception 'not exercised';end$$;`);
 await db.exec(sql);
 const id='00000000-0000-0000-0000-000000000020',now=Date.now(),key=randomBytes(32);
 const event={event_id:'00000000-0000-0000-0000-000000000010',collector_id:id,occurred_at:new Date(now).toISOString(),event_kind:'current_lure_touched',generation:1,correlation_key:'a'.repeat(64),key_epoch:new Date(now).toISOString().slice(0,10)};
 const handler=createCollectorSignedHandler({key,collectorId:id,clock:()=>now,enabled:()=>true,writeEvent:createCollectorPgSink(db)});
 server=http.createServer(async(req,res)=>{try{const r=await handler(new Request(`http://127.0.0.1${req.url}`,{method:req.method,headers:req.headers,body:Readable.toWeb(req),duplex:'half'}));res.writeHead(r.status,Object.fromEntries(r.headers));res.end();}catch{res.writeHead(503);res.end();}});
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const url=`http://127.0.0.1:${server.address().port}/collector/events`;
 async function send(e=event,k=key){const body=Buffer.from(JSON.stringify(e));return (await fetch(url,{method:'POST',headers:{'content-type':'application/json','x-sko-collector-id':id,'x-sko-collector-time':String(now),'x-sko-collector-signature':signCollectorBytes({key:k,collectorId:id,timestamp:now,body})},body})).status;}
 await db.exec('set role sko_security_collector_ingest');check(await send(),503); // actual DB gate remains OFF
 await db.exec('reset role;update private.security_collector_control set ingest_enabled=true;set role sko_security_collector_ingest');
 check(await send(),204);check(await send(),204); // durable SQL retry, not in-memory replay
 check(await send({...event,generation:2}),503); // same-ID signed conflict
 check(await send(event,randomBytes(32)),401);
 check(await send({...event,ip:'must never persist'}),400);
 for(const role of ['anon','authenticated','service_role']){await db.exec(`reset role;set role ${role}`);check(await send(),503);}
 await db.exec('reset role');const rows=(await db.query('select event_id,generation,source_provenance from private.security_collector_events')).rows;
 check(rows.length,1);check(rows[0].generation,1);check(rows[0].source_provenance,'trusted_collector_observation');
 await db.exec('update private.security_collector_control set ingest_enabled=false;set role sko_security_collector_ingest');check(await send(),503);
 console.log(JSON.stringify({pass:true,checks,real_loopback_http:true,real_hmac:true,exact_collector_sql:true,engine:'PGlite PostgreSQL17.5',native_postgres:false,master_proof_exercised:false,production_changed:false}));
}finally{if(server)await new Promise(resolve=>{server.close(resolve);server.closeAllConnections();});await db.close();}
