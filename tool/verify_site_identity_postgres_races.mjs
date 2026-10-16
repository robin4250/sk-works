import fs from 'node:fs';
import assert from 'node:assert/strict';
const url=new URL(process.env.SKO_SITE_IDENTITY_FIXTURE_URL??'postgres://invalid');
if(url.protocol!=='postgres:'||url.hostname!=='127.0.0.1'||url.port!=='5432'||url.pathname!=='/sko_site_identity_fixture'||url.username!=='postgres'||url.search||url.hash)throw Error('Only explicit local disposable site identity fixture is permitted');
const pg=await import(process.argv[2]);const Client=pg.Client??pg.default?.Client;
const clients=[];
async function connect(name){const c=new Client({connectionString:url.href,application_name:name});await c.connect();clients.push(c);await c.query("set statement_timeout='15s';set lock_timeout='12s'");return c;}
const admin=await connect('site-identity-control'),a=await connect('site-identity-a'),b=await connect('site-identity-b');
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const sql='select public.site_identity_change_link($1,$2,$3,$4,$5) v';
const args=(co,delivery,rev,unlink=false)=>[id(co),id(10+co),delivery===null?null:id(300+delivery),rev,unlink];
async function actor(client,n){await client.query("select set_config('test.uid',$1,false)",[id(100+n)]);}
async function barrier(){await admin.query('begin');await admin.query("select pg_advisory_xact_lock(hashtextextended('site-identity-registry',0))");}
async function blocked(names){const until=Date.now()+7000;while(Date.now()<until){await admin.query('select pg_stat_clear_snapshot()');const r=await admin.query("select application_name from pg_stat_activity where application_name=any($1) and wait_event_type='Lock'",[names]);if(r.rows.length===names.length)return;await new Promise(r=>setTimeout(r,25));}throw Error('Independent connections did not reach lock barrier');}
async function reset(){await admin.query('truncate site_identity_private.events,site_identity_private.selections,site_identity_private.roots');}
try{
 const version=Number((await admin.query('show server_version_num')).rows[0].server_version_num);assert(version>=160000&&version<170000);console.log('PostgreSQL server_version_num',version);
 assert.equal((await admin.query("select count(*)::int n from pg_tables where schemaname='public'")).rows[0].n,0,'fixture must be fresh; never drop existing data');
 await admin.query(`create role anon;create role authenticated;grant usage on schema public to authenticated;create schema auth;create schema private;
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
 create table public.company_members(company_id uuid,user_id uuid,role text);
 create table public.sites(id uuid primary key,company_id uuid,name text,formal_name text);
 create table private.document_deliveries(id uuid primary key,sender_company_id uuid,recipient_company_id uuid);
 create table private.company_data_delivery_items(id uuid primary key,delivery_id uuid,payload_kind text,payload jsonb);
 create table private.site_share_inbox(data_item_id uuid primary key,recipient_company_id uuid,status text);
 create table public.attendance_entries(id uuid primary key,site_id uuid references public.sites(id),amount integer);
 grant insert on public.attendance_entries to authenticated;
 `);
 for(let n=1;n<=3;n++){await admin.query("insert into public.company_members values($1,$2,'admin')",[id(n),id(100+n)]);await admin.query("insert into public.sites values($1,$2,'same','正式名')",[id(10+n),id(n)]);}
 for(const [n,to]of [[1,2],[2,3]]){await admin.query('insert into private.document_deliveries values($1,$2,$3)',[id(200+n),id(1),id(to)]);await admin.query("insert into private.company_data_delivery_items values($1,$2,'site_share',$3::jsonb)",[id(300+n),id(200+n),JSON.stringify({source_site_id:id(11)})]);await admin.query("insert into private.site_share_inbox values($1,$2,'pending')",[id(300+n),id(to)]);}
 await admin.query(fs.readFileSync('tool/staged/site_identity_links.sql','utf8'));
 for(const client of[a,b]){await actor(client,2);await client.query('set role authenticated');}
 await barrier();const duplicate=Promise.allSettled([a.query(sql,args(2,1,0)),b.query(sql,args(2,1,0))]);await blocked(['site-identity-a','site-identity-b']);await admin.query('commit');
 const dr=await duplicate;assert.equal(dr.filter(x=>x.status==='fulfilled').length,1);assert.equal(dr.find(x=>x.status==='rejected').reason.code,'40001');assert.equal((await admin.query('select count(*)::int n from site_identity_private.events')).rows[0].n,1);console.log('PASS duplicate receipt/same revision: one committed winner, one stale loser, no partial event');
 // Failed transaction can roll back and retry against the current exact revision.
 await b.query('begin');await assert.rejects(()=>b.query(sql,args(2,1,0)),e=>e.code==='40001');await b.query('rollback');const retry=await b.query(sql,args(2,1,1));assert.equal(retry.rows[0].v.revision,1);console.log('PASS stale transaction rollback and exact current-revision retry');
 await actor(b,3);await barrier();const independent=Promise.allSettled([a.query(sql,args(2,null,1,true)),b.query(sql,args(3,2,0))]);await blocked(['site-identity-a','site-identity-b']);await admin.query('commit');const ir=await independent;assert(ir.every(x=>x.status==='fulfilled'));
 const selection=(await admin.query('select site_id,home_root,display_group,revision from site_identity_private.selections order by site_id')).rows;
 const sa=selection.find(x=>x.site_id===id(11)),sb=selection.find(x=>x.site_id===id(12)),sc=selection.find(x=>x.site_id===id(13));assert.equal(sb.home_root,sb.display_group);assert.equal(sc.display_group,sa.display_group);assert.equal(sa.revision,'0');console.log('PASS different companies concurrent unlink/link: both commit; sender and third-party choices preserved');
 await reset();await actor(a,2);await actor(b,2);
 // Rollback the lock holder after it created a complete but uncommitted link.
 await a.query('begin');await a.query(sql,args(2,1,0));const waiting=b.query(sql,args(2,1,0));waiting.catch(()=>{});await blocked(['site-identity-b']);await a.query('rollback');const afterRollback=await waiting;assert.equal(afterRollback.rows[0].v.revision,1);assert.equal((await admin.query('select count(*)::int n from site_identity_private.events')).rows[0].n,1);console.log('PASS writer rollback releases barrier; waiting retry commits exactly one event');
 // No identity lock is taken by legacy attendance INSERT; prove it commits while unlink waits.
 await barrier();const unlink=a.query(sql,args(2,null,1,true));unlink.catch(()=>{});await blocked(['site-identity-a']);await b.query('insert into public.attendance_entries values($1,$2,321)',[id(501),id(12)]);await admin.query('commit');await unlink;
 const preserved=(await admin.query('select site_id,amount from public.attendance_entries where id=$1',[id(501)])).rows[0];assert.equal(preserved.site_id,id(12));assert.equal(preserved.amount,321);assert.equal((await admin.query('select count(*)::int n from public.sites')).rows[0].n,3);console.log('PASS unlink versus new attendance: original local site ID, amount and all sites preserved');
}finally{for(const c of clients){try{await c.query('rollback')}catch{}await c.end();}}
