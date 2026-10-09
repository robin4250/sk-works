import fs from 'node:fs';
import assert from 'node:assert/strict';
import {Client} from 'pg';
const raw=process.env.SKO_NOTIFICATION_FIXTURE_URL;
const uri=new URL(raw);
if(!['postgres:','postgresql:'].includes(uri.protocol)||uri.hostname!=='127.0.0.1'||uri.pathname!=='/sko_notification_fixture'||uri.username!=='postgres'||uri.password!=='fixture-only-password'||uri.search||uri.hash)throw new Error('dedicated localhost notification fixture only');
const clients=await Promise.all(['setup','first','second','barrier'].map(async application_name=>{const c=new Client({connectionString:raw,application_name});await c.connect();return c;}));
const [setup,first,second,barrier]=clients;
try{
 assert.equal(Math.floor(Number((await setup.query('show server_version_num')).rows[0].server_version_num)/10000),17);
 assert.equal((await setup.query("select to_regclass('public.generation_setting_issues') as existing")).rows[0].existing,null);
 await setup.query(fs.readFileSync('supabase/tests/generation_setting_issue_notification_fixture.sql','utf8'));
 await setup.query(fs.readFileSync('supabase/migrations/20261009205616_generation_setting_issue_first_notification.sql','utf8'));
 await barrier.query('begin;lock table public.generation_setting_issues in share mode');
 const sql="select private.upsert_generation_setting_issue('10000000-0000-0000-0000-000000000001','race','payroll','Fixture title','Fixture body','payroll_settings',null)";
 const operations=[first.query(sql),second.query(sql)];
 const deadline=Date.now()+15000;
 while(true){
  const n=Number((await setup.query("select count(*) as n from pg_stat_activity where application_name in ('first','second') and wait_event_type='Lock' and wait_event='relation'")).rows[0].n);
  if(n===2)break;
  if(Date.now()>deadline)throw new Error('both actual calls must reach blocked INSERT after absent-row SELECT');
  await new Promise(resolve=>setTimeout(resolve,25));
 }
 await barrier.query('commit');await Promise.all(operations);
 assert.equal(Number((await setup.query("select count(*) as n from public.generation_setting_issues where issue_key='race'")).rows[0].n),1);
 const notifications=Number((await setup.query('select count(*) as n from public.app_notifications')).rows[0].n);
 assert.equal(notifications,2,'known defect: simple NULL fix permits both absent-row calls to notify');
 console.log(JSON.stringify({postgresMajor:17,issueRows:1,initialNotifications:notifications,status:'KNOWN_DUPLICATE: minimal fix is not complete concurrent adoption'}));
}finally{await barrier.query('rollback').catch(()=>{});await Promise.all(clients.map(c=>c.end()));}
