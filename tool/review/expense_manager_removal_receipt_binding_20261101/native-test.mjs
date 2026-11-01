import assert from 'node:assert/strict';
import {prepare,id,info} from './fixture.mjs';
const pg=await import(process.argv[2]);const Client=pg.Client??pg.default?.Client;
const {admin:c,config}=await prepare(Client);const clients=[c];let checks=0;
async function actor(who,sid){await c.query(`reset role;set test.uid='${who}';set test.sid='${sid}';set role authenticated`);}
async function claim(n,photo){
 const claim=id(n);await actor(info.applicant,info.applicantSid);
 let reservation;
 if(photo){reservation=(await c.query('select public.expense_prepare_receipt($1,$2,$3,$4,4,$5) value',[claim,info.company,info.worker,'a'.repeat(64),'image/jpeg'])).rows[0].value;
 if(photo==='attached'){await c.query(`insert into storage.objects(bucket_id,name,metadata) values('expense-receipts',$1,'{"size":4,"mimetype":"image/jpeg"}')`,[reservation.object_path]);
 await c.query('select public.expense_personal_submit_with_receipt($1,$2,$3,current_date,$4,1234)',[claim,info.company,info.worker,'Receipt original']);return {claim,reservation};}}
 await c.query('select public.expense_personal_submit($1,$2,$3,current_date,$4,1234)',[claim,info.company,info.worker,'Receipt original']);return {claim,reservation};
}
async function remove(claim,command){await actor(info.manager,info.sid);return(await c.query('select public.expense_manager_remove($1,$2,$3,1,$4,$5) value',[command,info.company,claim,info.sid,'本人へ削除通知'])).rows[0].value;}
function pass(name){checks++;console.log('PASS '+name);}
try{
 for(const [n,photo,state] of [[100,'attached','attached_metadata_only'],[101,'reserved','reserved_not_attached'],[102,null,'unrecorded']]){
 const x=await claim(n,photo);await c.query('reset role');
 const before=(await c.query('select to_jsonb(e) value from private.expense_claims e where id=$1',[x.claim])).rows[0].value;
 const receipts=(await c.query('select to_jsonb(e) value from private.expense_receipts e where claim_id=$1',[x.claim])).rows.map(x=>x.value);
 const objects=(await c.query('select to_jsonb(e) value from storage.objects e order by name')).rows.map(x=>x.value);
 const result=await remove(x.claim,id(n+1000));assert.equal(result.financial_state,'withdrawn_unfinalized');
 assert.deepEqual(await remove(x.claim,id(n+1000)),result);
 await c.query('reset role');const ledger=(await c.query('select * from private.expense_manager_removals where claim_id=$1',[x.claim])).rows[0];
 assert.deepEqual(ledger.before_row,before);assert.equal('receipt_object_path' in ledger.before_row,false);assert.equal(ledger.receipt_state,state);
 assert.deepEqual(ledger.receipt_snapshot,receipts[0]??null);assert.equal(ledger.before_row.amount_yen,1234);
 assert.deepEqual((await c.query('select to_jsonb(e) value from private.expense_receipts e where claim_id=$1',[x.claim])).rows.map(x=>x.value),receipts);
 assert.deepEqual((await c.query('select to_jsonb(e) value from storage.objects e order by name')).rows.map(x=>x.value),objects);
 assert.equal((await c.query('select count(*)::int n from public.app_notifications where id=$1',[result.notification_id])).rows[0].n,1);
 await actor(info.manager,info.sid);const workspace=(await c.query('select public.expense_manager_removal_workspace($1,current_date) value',[info.company])).rows[0].value;
 const row=workspace.claims.find(v=>v.id===x.claim);assert.equal(row.receipt_object_path,photo==='attached'?x.reservation.object_path:null);assert.equal(row.receipt_preservation_state,state);
 await assert.rejects(c.query('select public.expense_manager_removal_notice($1)',[result.notification_id]),e=>e.code==='42501');
 await actor(info.applicant,info.applicantSid);const notice=(await c.query('select public.expense_manager_removal_notice($1) value',[result.notification_id])).rows[0].value;
 assert.equal(notice.claim_id,x.claim);assert.equal(notice.amount_yen,1234);
 const history=(await c.query('select public.expense_personal_receipt_history($1,$2,current_date) value',[info.company,info.worker])).rows[0].value;
 const original=history.find(v=>v.id===x.claim);assert.equal(original.manager_deleted,true);assert.equal(original.receipt_object_path,photo==='attached'?x.reservation.object_path:null);
 pass(state+' original JSON + canonical receipt + exact notice + actual wrappers');
 }
 const restricted=await claim(108,null);await c.query('reset role');
 await c.query('insert into private.account_deletion_access_restrictions(user_id) values($1)',[info.manager]);
 await assert.rejects(remove(restricted.claim,id(1108)),e=>e.code==='42501');await c.query('reset role');
 assert.equal((await c.query('select count(*)::int n from private.expense_manager_removals where claim_id=$1',[restricted.claim])).rows[0].n,0);
 await c.query('delete from private.account_deletion_access_restrictions where user_id=$1',[info.manager]);pass('captured account access body rejects restricted actor');
 const invalid=await claim(107,null);await actor(info.manager,info.sid);
 for(const reason of ['', ' '])await assert.rejects(c.query('select public.expense_manager_remove($1,$2,$3,1,$4,$5)',[id(1107),info.company,invalid.claim,info.sid,reason]),e=>e.code==='22023');
 pass('empty and whitespace reasons reject before mutation');
 const bad=await claim(103,'attached');await c.query('reset role');
 // Deliberate isolated corrupted metadata fixture; product never writes receipt metadata.
 await c.query('update private.expense_receipts set created_by=$1 where claim_id=$2',[info.manager,bad.claim]);
 const badBefore=(await c.query('select to_jsonb(e) value from private.expense_claims e where id=$1',[bad.claim])).rows[0].value;
 const badReceipt=(await c.query('select to_jsonb(e) value from private.expense_receipts e where claim_id=$1',[bad.claim])).rows[0].value;
 const noticeBefore=(await c.query('select count(*)::int n from public.app_notifications')).rows[0].n;
 await assert.rejects(remove(bad.claim,id(1103)),e=>e.code==='40001');await c.query('reset role');
 assert.equal((await c.query('select count(*)::int n from private.expense_manager_removals where claim_id=$1',[bad.claim])).rows[0].n,0);
 assert.equal((await c.query('select withdrawn from private.expense_claims where id=$1',[bad.claim])).rows[0].withdrawn,false);
 assert.deepEqual((await c.query('select to_jsonb(e) value from private.expense_claims e where id=$1',[bad.claim])).rows[0].value,badBefore);
 assert.deepEqual((await c.query('select to_jsonb(e) value from private.expense_receipts e where claim_id=$1',[bad.claim])).rows[0].value,badReceipt);
 assert.equal((await c.query('select count(*)::int n from public.app_notifications')).rows[0].n,noticeBefore);pass('mismatched receipt rejects atomically with original metadata and no notice');
 // Explicit prior-validation race: old prepare reaches INSERT after deletion.
 const plain=await claim(104,null);await remove(plain.claim,id(1104));await c.query('reset role');
 await assert.rejects(c.query(`insert into private.expense_receipts(claim_id,company_id,applicant_id,created_by,object_path,sha256,size_bytes,mime_type)
 values($1,$2,$3,$4,$5,$6,4,'image/jpeg')`,[plain.claim,info.company,info.worker,info.applicant,'delayed-reservation.jpg','b'.repeat(64)]),e=>e.code==='55000');
 pass('post-removal legacy INSERT rejected; prior validation is not admission');
 const d=new Client({...config,connectionTimeoutMillis:5000,query_timeout:17000});clients.push(d);await d.connect();
 await d.query("set statement_timeout='15s';set lock_timeout='4s'");
 const observer=new Client({...config,connectionTimeoutMillis:5000,query_timeout:17000});clients.push(observer);await observer.connect();
 await observer.query("set statement_timeout='15s';set lock_timeout='4s'");
 assert.equal((await observer.query('select current_user role')).rows[0].role,'postgres');
 async function waitForLock(pid,blocker){for(let i=0;i<100;i++){await observer.query('select pg_stat_clear_snapshot()');const a=(await observer.query('select wait_event_type,pg_blocking_pids(pid) blockers from pg_stat_activity where pid=$1',[pid])).rows[0];if(a?.wait_event_type==='Lock'&&a.blockers.includes(blocker))return true;await new Promise(r=>setTimeout(r,10));}throw Error('Expected competing transaction lock not observed');}
 const pid=(await c.query('select pg_backend_pid() pid')).rows[0].pid;
 const dpid=(await d.query('select pg_backend_pid() pid')).rows[0].pid;
 // Reservation wins: old prepare passed validation, its INSERT holds new guard lock.
 const race=await claim(105,null);await c.query('reset role');await d.query('begin');
 await d.query(`insert into private.expense_receipts(claim_id,company_id,applicant_id,created_by,object_path,sha256,size_bytes,mime_type)
 values($1,$2,$3,$4,$5,$6,4,'image/jpeg')`,[race.claim,info.company,info.worker,info.applicant,'inflight-reservation.jpg','c'.repeat(64)]);
 const removing=remove(race.claim,id(1105));await waitForLock(pid,dpid);await d.query('commit');await removing;await c.query('reset role');
 assert.equal((await c.query('select receipt_state from private.expense_manager_removals where claim_id=$1',[race.claim])).rows[0].receipt_state,'reserved_not_attached');pass('two connections: reservation-first snapshot sees committed reservation');
 // Removal wins: a legacy prepare's earlier validation cannot bypass INSERT guard.
 const late=await claim(106,null);await actor(info.manager,info.sid);await c.query('begin');
 await c.query('select public.expense_manager_remove($1,$2,$3,1,$4,$5)',[id(1106),info.company,late.claim,info.sid,'race']);
 assert.equal((await c.query('select current_user role')).rows[0].role,'authenticated');
 const dp=(await d.query('select pg_backend_pid() pid')).rows[0].pid;
 const inserting=d.query(`insert into private.expense_receipts(claim_id,company_id,applicant_id,created_by,object_path,sha256,size_bytes,mime_type)
 values($1,$2,$3,$4,$5,$6,4,'image/jpeg')`,[late.claim,info.company,info.worker,info.applicant,'after-validation.jpg','d'.repeat(64)]).then(()=>({ok:true}),error=>({error}));
 const blocked=await waitForLock(dp,pid);
 assert.equal(blocked,true);await c.query('commit');assert.equal((await inserting).error?.code,'55000');pass('two connections: removal-first legacy reservation waits then rejects');
 console.log(JSON.stringify({checks,deployable:false,realStorage:false,realGoTrue:false,financialReaderQualified:false}));
}finally{await Promise.allSettled(clients.map(x=>x.end()));}
