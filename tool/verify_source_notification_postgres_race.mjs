import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const connectionString=process.env.SKO_NOTIFICATION_RACE_DATABASE_URL;
const url=new URL(connectionString??'postgres://invalid');
if(!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.pathname!=='/sko_notification_race_fixture')throw new Error('Only local disposable sko_notification_race_fixture database is permitted');
const pg=await import(process.argv[2]);const Client=pg.Client??pg.default?.Client;
const clients=[];
async function connect(name){const c=new Client({connectionString,application_name:name});await c.connect();clients.push(c);await c.query("set statement_timeout='15s';set lock_timeout='12s'");return c;}
const root=new URL('./fixtures/source_member_notifications/',import.meta.url);
const ids=Array.from({length:9},(_,i)=>`00000000-0000-0000-0000-${String(i+1).padStart(12,'0')}`);
const [company,actor,recipient,worker,peer,site,report,source,other]=ids;
try{
 const admin=await connect('source-notification-admin'),a=await connect('source-notification-a'),b=await connect('source-notification-b');
 const schema=await fs.readFile(new URL('schema.sql',root),'utf8');
 await admin.query('drop schema if exists private cascade;drop schema if exists auth cascade;drop schema public cascade;create schema public');
 await admin.query("do $$begin if not exists(select 1 from pg_roles where rolname='anon')then create role anon;end if;if not exists(select 1 from pg_roles where rolname='authenticated')then create role authenticated;end if;end$$");
 await admin.query(schema.replace('create role anon; create role authenticated;',''));
 const manifest=JSON.parse(await fs.readFile(new URL('manifest.json',root),'utf8'));
 for(const item of manifest.files){const bytes=await fs.readFile(new URL(item.path,root));assert.equal(bytes.length,item.bytes);assert.equal(createHash('sha256').update(bytes).digest('hex'),item.sha256);await admin.query(bytes.toString());}
 await admin.query('grant select,update on public.app_notifications to authenticated');
 await admin.query(await fs.readFile(new URL('../supabase/migrations/20261008171216_source_member_notifications.sql',import.meta.url),'utf8'));
 await admin.query(`insert into auth.users values('${actor}'),('${recipient}');insert into companies values('${company}');insert into company_members values('${company}','${actor}','admin'),('${company}','${recipient}','viewer');insert into workers values('${worker}','${company}','${actor}','Author','active'),('${peer}','${company}','${recipient}','Peer','active');insert into daily_reports values('${report}','${company}','${site}',null,'2026-09-30','${actor}');insert into daily_report_workers values('${report}','${worker}'),('${report}','${peer}');insert into attendance_verifications values('${source}','${company}','${worker}','${site}',null,'2026-09-30','clock_in',null,'${report}',null),('${other}','${company}','${peer}','${site}',null,'2026-09-30','clock_in',null,'${report}',null);insert into attendance_verifications select gen_random_uuid(),company_id,worker_id,site_id,null,work_date,'clock_out',id,daily_report_id,null from attendance_verifications where event_type='clock_in';insert into private.source_notification_rollouts values('${company}',true);`);
 for(const c of[a,b])await c.query(`set test.uid='${actor}';set role authenticated`);
 await admin.query('begin');await admin.query(`select id from daily_reports where id='${report}' for update`);
 const first=a.query(`select public.publish_saved_group_report_notifications('${report}') n`),second=b.query(`select public.publish_saved_group_report_notifications('${report}') n`);
 const results=Promise.all([first,second]);results.catch(()=>{});
 const deadline=Date.now()+7000;let blocked=false;
 while(Date.now()<deadline){await admin.query('select pg_stat_clear_snapshot()');const r=await admin.query("select count(*)::int n from pg_stat_activity where application_name in ('source-notification-a','source-notification-b') and wait_event_type='Lock'");if(r.rows[0].n===2){blocked=true;break;}await new Promise(resolve=>setTimeout(resolve,25));}
 assert.equal(blocked,true,'Both independent publishers must reach observed database Lock barrier');
 await admin.query('commit');const published=await results;assert.deepEqual(published.map(r=>r.rows[0].n).sort(),[0,1]);
 assert.equal((await admin.query("select count(*)::int n from app_notifications where action_key='group_report_saved'")).rows[0].n,1);
 assert.equal((await admin.query("select count(*)::int n from private.source_notification_receipts where event_key='group_report_saved'")).rows[0].n,1);
 const notice=(await admin.query("select id from app_notifications where action_key='group_report_saved'")).rows[0].id;
 await admin.query('delete from app_notifications where id=$1',[notice]);
 assert.equal((await a.query(`select public.publish_saved_group_report_notifications('${report}') n`)).rows[0].n,0);
 assert.equal((await admin.query("select count(*)::int n from app_notifications where action_key='group_report_saved'")).rows[0].n,0);
 const receipt=(await admin.query("select notification_id,work_date::text from private.source_notification_receipts where event_key='group_report_saved'")).rows[0];assert.equal(receipt.notification_id,null);assert.equal(receipt.work_date,'2026-09-30');
 await b.query(`set test.uid='${recipient}'`);await assert.rejects(b.query('select public.get_source_notification_target($1)',[notice]),/unavailable/);
 console.log('PASS actual Postgres: observed 2-connection lock barrier, one publication, one ledger, deletion preserves dedup and target denial');
}finally{await Promise.allSettled(clients.map(c=>c.end()));}
