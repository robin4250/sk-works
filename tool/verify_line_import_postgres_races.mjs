import assert from 'node:assert/strict';
import pg from 'pg';
process.on('uncaughtException',error=>{console.error(error.message,error.code,error.internalQuery ?? '');process.exit(1);});
const url=new URL(process.env.SKO_LINE_IMPORT_POSTGRES_URL);
if(!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.pathname!='/sko_line_import_fixture')throw new Error('Use only the disposable loopback LINE fixture database');
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const a=new pg.Client({connectionString:url.href}),b=new pg.Client({connectionString:url.href});
await Promise.all([a.connect(),b.connect()]);
try{
 const q=async(client,sql,params=[]) => (await client.query(sql,params)).rows[0]?.value;
 await a.query("select set_config('test.uid',$1,false)",[id(1)]);
 await b.query("select set_config('test.uid',$1,false)",[id(1)]);
 await a.query("select public.set_line_import_feature('invoice',true)");
 const source={id:id(100),body:'9月1日\n現場A 本人\n現場A 定時',sent_at:'2026-09-01T00:00:00Z'};
 await a.query("insert into chat_messages(id,company_id,communication_group_id,origin,body,sent_at) values($1,$2,$3,'line',$4,$5)",[id(100),id(10),id(20),source.body,source.sent_at]);
 const rows=[{row_id:`${id(100)}:0`,source_message_id:id(100),work_date:'2026-09-01',worker_id:id(30),worker_name:'本人',site_id:id(40),site_name:'現場A',man_days:1,overtime_hours:0,early_hours:0,confirmed:true}];
 const data=await q(a,'select public.save_line_import_draft($1,$2,\'invoice\',\'2026-09-01\',0,\'received\',$3::jsonb,$4::jsonb,\'ノート照合済み\',true) value',[id(101),id(20),JSON.stringify([source]),JSON.stringify(rows)]);
 const preview=await q(a,'select public.line_invoice_preview($1,1) value',[data.draft_id]);
 await Promise.all([a.query('set role authenticated'),b.query('set role authenticated')]);
 const params=[id(102),data.draft_id,1,preview.fingerprint];
 const call=client=>q(client,'select public.create_line_invoices($1,$2,$3,$4) value',params);
 await a.query('begin');
 const first=await call(a);
 let returned=false;const repeated=call(b).then(result=>{returned=true;return result;});
 const pid=(await a.query('select pg_backend_pid() pid')).rows[0].pid;
 await a.query('reset role');
 for(let count=0;count<100;count++){
  const waiting=(await a.query('select exists(select 1 from pg_stat_activity where $1=any(pg_blocking_pids(pid))) value',[pid])).rows[0].value;
  if(waiting)break;
  if(count===99)throw new Error('Second command did not wait on the first transaction');
  await new Promise(resolve=>setTimeout(resolve,10));
 }
 assert.equal(returned,false);await a.query('commit');assert.deepEqual(await repeated,first);
 await b.query('reset role');
 assert.equal((await a.query("select count(*)::int n from invoices where billing_period_start='2026-09-01'")).rows[0].n,1);
 // An independent command cannot create another invoice for the same period.
 await assert.rejects(()=>q(b,'select public.create_line_invoices($1,$2,1,$3) value',[id(103),data.draft_id,preview.fingerprint]),/同じ取引会社/);
 // OFF takes its row lock and cannot invalidate a command midway through a write.
 await a.query('begin');await a.query("select * from private.line_import_feature_settings where target='attendance' for share");
 let switched=false;const off=q(b,"select public.set_line_import_feature('attendance',false) value").then(result=>{switched=true;return result;});
 for(let count=0;count<100;count++){
  const waiting=(await a.query('select exists(select 1 from pg_stat_activity where $1=any(pg_blocking_pids(pid))) value',[pid])).rows[0].value;
  if(waiting)break;if(count===99)throw new Error('Master switch did not wait on the protected feature row');await new Promise(resolve=>setTimeout(resolve,10));
 }
 assert.equal(switched,false);await a.query('commit');assert.equal((await off).attendance,false);
 assert.equal((await a.query('select count(*)::int n from private.line_import_drafts')).rows[0].n,3);
 console.log('Postgres 17: duplicate invoice command waits and reuses one receipt, independent duplicate refused, OFF waits and preserves drafts.');
}finally{await Promise.allSettled([a.query('rollback'),b.query('rollback')]);await Promise.allSettled([a.end(),b.end()]);}
