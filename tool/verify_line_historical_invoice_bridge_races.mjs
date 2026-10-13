import assert from 'node:assert/strict';import pg from 'pg';
import {makeBridgeQuote,id} from './fixtures/line_historical_invoice_bridge_fixture.mjs';
process.on('uncaughtException',error=>{console.error(error.message,error.code,error.internalQuery ?? '');process.exit(1);});
const url=new URL(process.env.SKO_LINE_IMPORT_POSTGRES_URL);
if(!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.pathname!='/sko_line_import_fixture')throw Error('Disposable loopback LINE fixture database only');
const a=new pg.Client({connectionString:url.href}),b=new pg.Client({connectionString:url.href});await Promise.all([a.connect(),b.connect()]);
const db={query:(sql,params)=>a.query(sql,params)};
const value=async(client,sql,params=[])=> (await client.query(sql,params)).rows[0]?.value;
const terms=q=>JSON.stringify(q.terms);
const preview=async q=>value(a,'select public.line_historical_invoice_preview($1,$2,$3,1000,true) value',[q.id,q.fingerprint,terms(q)]);
const bridge=(client,q,command,p)=>value(client,'select public.create_line_historical_invoices($1,$2,$3,$4,1000,true,$5,true) value',[id(command),q.id,q.fingerprint,terms(q),p.fingerprint]);
const oldPreview=q=>value(a,'select public.line_invoice_preview($1,1) value',[q.draft]);
const legacy=(client,q,command,p)=>value(client,'select public.create_line_invoices($1,$2,1,$3) value',[id(command),q.draft,p.fingerprint]);
const oneInvoice=async month=>assert.equal((await a.query('select count(*)::int n from invoices where billing_period_start=$1',[month])).rows[0].n,1);
try {
 for(const client of [a,b])await client.query("select set_config('test.uid',$1,false),set_config('statement_timeout','10s',false),set_config('lock_timeout','5s',false)",[id(1)]);
 // Existing stage two has current customer 71, while bridge explicitly chooses 70.
 // Distinct scope keys force the race through the common invoice table lock.
 const first=await makeBridgeQuote(db,'2020-02-01',400),firstPreview=await preview(first),firstOld=await oldPreview(first);
 await a.query('begin');const made=await bridge(a,first,401,firstPreview);
 await assert.rejects(legacy(b,first,402,firstOld),error=>error.code==='40001');await a.query('commit');
 await assert.rejects(legacy(b,first,402,firstOld),error=>error.code==='22023'&&/Historical LINE month/.test(error.message));
 await oneInvoice(first.month);assert.deepEqual(await bridge(b,first,401,firstPreview),made);
 // Reverse winner: existing stage two holds the common invoice lock first.
 const second=await makeBridgeQuote(db,'2020-03-01',410),secondPreview=await preview(second),secondOld=await oldPreview(second);
 await a.query('begin');const oldMade=await legacy(a,second,411,secondOld);
 await assert.rejects(bridge(b,second,412,secondPreview),error=>error.code==='40001');await a.query('commit');
 await assert.rejects(bridge(b,second,412,secondPreview),error=>error.code==='22023'&&/LINE month already/.test(error.message));
 assert.deepEqual(await legacy(b,second,411,secondOld),oldMade);await oneInvoice(second.month);
 // Same bridge command waits for the receipt, then returns its original result.
 const third=await makeBridgeQuote(db,'2020-04-01',420),thirdPreview=await preview(third);
 await a.query('begin');const original=await bridge(a,third,421,thirdPreview);
 let returned=false;const repeated=bridge(b,third,421,thirdPreview).then(x=>{returned=true;return x;});
 const pid=(await a.query('select pg_backend_pid() pid')).rows[0].pid;
 for(let n=0;n<100;n++){if((await a.query('select exists(select 1 from pg_stat_activity where $1=any(pg_blocking_pids(pid))) value',[pid])).rows[0].value)break;if(n===99)throw Error('Repeated command did not wait for its receipt');await new Promise(resolve=>setTimeout(resolve,10));}
 assert.equal(returned,false);await a.query('commit');assert.deepEqual(await repeated,original);await oneInvoice(third.month);
 // Independent bridge commands cannot charge the same group/month at two parties.
 const fourth=await makeBridgeQuote(db,'2020-05-01',430),fourthPreview=await preview(fourth);
 const other={...fourth,terms:[{...fourth.terms[0],customer_id:id(71)}]},otherPreview=await preview(other);
 await a.query('begin');await bridge(a,fourth,431,fourthPreview);await assert.rejects(bridge(b,other,432,otherPreview),error=>error.code==='40001');await a.query('commit');await assert.rejects(bridge(b,other,432,otherPreview),error=>error.code==='22023');await oneInvoice(fourth.month);
 // A legacy ordinary writer takes a table lock before scope; failed NOWAIT must
 // release bridge's advisory lock so that the existing writer can continue.
 const fifth=await makeBridgeQuote(db,'2020-06-01',440),fifthPreview=await preview(fifth);
 await b.query('begin');await b.query('lock table invoices in row exclusive mode');await assert.rejects(bridge(a,fifth,441,fifthPreview),error=>error.code==='40001');
 const key='invoice:'+id(10)+id(70)+fifth.month;assert.equal((await b.query('select pg_try_advisory_xact_lock(hashtextextended($1,0)) value',[key])).rows[0].value,true);await b.query('rollback');
 const iid=made.invoices[0].invoice_id;
 const expenses=()=>value(a,'select public.line_historical_invoice_expense_preview($1,$2) value',[first.id,iid]);
 // Existing approve_invoice locks company before the invoice. Refresh does the
 // same row order and uses NOWAIT, preserving nonblocking lock recovery.
 await b.query('begin');await b.query('select id from companies where id=$1 for update',[id(10)]);await assert.rejects(expenses(),error=>error.code==='40001');
 await b.query("insert into invoice_approvals values($1,'approved')",[iid]);await b.query('commit');await assert.rejects(expenses(),error=>error.code==='22023');
 await b.query('delete from invoice_approvals where invoice_id=$1',[iid]);const ep=await expenses();
 const apply=(client)=>value(client,'select public.refresh_line_historical_invoice_expenses($1,$2,$3,true) value',[first.id,iid,ep.fingerprint]);
 await a.query('begin');const refreshed=await apply(a);await assert.rejects(apply(b),error=>error.code==='40001');await a.query('commit');assert.deepEqual(await apply(b),refreshed);
 assert.equal((await a.query('select count(*)::int n from attendance_entries')).rows[0].n,0);assert.equal((await a.query('select count(*)::int n from attendance_correction_requests')).rows[0].n,0);
 console.log('Postgres 17 bridge races: both legacy/bridge winners, common NOWAIT lock order, no deadlocks, both immutable command replays, one group/month conversion and nonblocking ordinary writers passed.');
} finally {await Promise.allSettled([a.query('rollback'),b.query('rollback')]);await Promise.allSettled([a.end(),b.end()]);}
