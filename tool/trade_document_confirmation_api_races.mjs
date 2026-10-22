// Public-API SQL-role races on two independent native PG17 connections.
// Synthetic existing session claims only: no real JWT/HTTP or lost-COMMIT claim.
import assert from 'node:assert/strict';

export async function verifyPublicConfirmationApiRaces(db,c){
 const {id,A,UA,CUSTOMER,actor,check,openNativePeer}=c;
 if(!openNativePeer){
  console.log('SKIP public confirmation API races: independent native PostgreSQL connections required');
  return;
 }
 const sessionRows=(await db.query('select id from auth.sessions where user_id=$1 order by id',[UA])).rows;
 assert.equal(sessionRows.length,1,'one existing fixture owner session required');
 const claims=JSON.stringify({sub:UA,role:'authenticated',session_id:sessionRows[0].id});
 const initialize=async peer=>{
  await peer.query("set statement_timeout='15s';set lock_timeout='10s'");
  await peer.query("select set_config('test.uid',$1,false),set_config('test.jwt',$2,false),set_config('test.blocked','false',false),set_config('test.invoice_manage','true',false),set_config('test.invoice_view','true',false)",[UA,claims]);
  check((await peer.query('select current_database() v')).rows[0].v,'sko_document_consent_fixture');
 };
 const owner=async()=>{await actor(UA);await db.query("select set_config('test.jwt',$1,false)",[claims]);};
 const api=async(peer,sql,args=[])=>{
  await peer.query('set role authenticated');
  try{
   check((await peer.query('select current_user v')).rows[0].v,'authenticated');
   return (await peer.query(sql,args)).rows[0]?.v;
  }finally{await peer.query('reset role').catch(()=>{});}
 };
 const prepare=async num=>{
  await owner();const parent=id(94000+num);
  await db.query("insert into public.invoices(id,company_id,customer_id,billing_period_start,billing_period_end,updated_at,status,grand_total,tax,snapshot) values($1,$2,$3,'2026-10-01','2026-10-31',clock_timestamp(),'draft',110000,10000,'{}')",[parent,A,CUSTOMER]);
  await db.query('select private.ensure_invoice_approval_rows($1)',[parent]);
  const source=(await db.query('select updated_at::text v from public.invoices where id=$1',[parent])).rows[0].v;
  const attachment=await api(db,"select public.trade_document_attachment_workspace('invoice',$1,$2) v",[parent,source]);
  const payload={...attachment.defaults,company_seal_enabled:false,company_seal_snapshot:null,issue_date:'2026-10-22',order_date:'2026-10-21',work_name:'公開承認競合の合成工事',work_address:'東京都',acceptance_text:'上記注文内容を承諾します。',intro_text:'合成請負',payment_conditions:'翌月末',notes:''};
  await api(db,"select public.save_trade_document_attachment('invoice',$1,$2,0,$3::jsonb) v",[parent,source,JSON.stringify(payload)]);
  const workspace=await api(db,"select public.trade_document_confirmation_workspace('invoice',$1,$2) v",[parent,source]);
  check(workspace.can_integrated_confirm,true);check(workspace.kind,'invoice');
  const preview=await api(db,'select public.preview_trade_document_confirmation($1,$2,$3,$4) v',[A,workspace.local_document_id,workspace.document_revision,'invoice']);
  check(preview.expected_command.document_id,workspace.document_id);check(preview.expected_command.actor_id,UA);
  return {parent,workspace,preview,command:preview.expected_command,rid:id(95000+num)};
 };
 const confirm=(peer,x)=>api(peer,'select public.confirm_trade_document_with_seal($1::jsonb,$2,true,true) v',[JSON.stringify(x.command),x.rid]);
 const receipt=(peer,x)=>api(peer,'select public.read_trade_document_confirmation_receipt($1,$2,$3::jsonb) v',[A,x.rid,JSON.stringify(x.command)]);
 const render=(peer,x,archive=false)=>api(peer,'select public.render_confirmed_trade_document($1,$2,$3,$4,$5) v',[A,x.workspace.local_document_id,x.workspace.document_revision,'invoice',archive]);
 const state=async(x,peer=db)=>(await peer.query(`select jsonb_build_object('parent',to_jsonb(i),
 'approvals',(select coalesce(jsonb_agg(to_jsonb(a) order by position),'[]') from public.invoice_approvals a where a.invoice_id=i.id),
 'audit',(select coalesce(jsonb_agg(to_jsonb(a) order by id),'[]') from public.invoice_approval_audit a where a.invoice_id=i.id),
 'revision',(select to_jsonb(r) from trade_document_consent_private.revisions r where r.document_id=$2 and r.revision=$3),
 'consents',(select coalesce(jsonb_agg(to_jsonb(s) order by s.company_id),'[]') from trade_document_consent_private.consents s where s.document_id=$2),
 'events',(select coalesce(jsonb_agg(to_jsonb(e) order by e.id),'[]') from trade_document_consent_private.events e where e.document_id=$2),
 'api_receipts',(select coalesce(jsonb_agg(to_jsonb(r) order by r.request_id),'[]') from trade_document_confirmation_api_private.receipts r where r.document_id=$2),
 'financial_receipts',(select coalesce(jsonb_agg(to_jsonb(r) order by r.request_id),'[]') from trade_document_consent_private.financial_receipts r where r.document_id=$2),
 'primitive_receipts',(select coalesce(jsonb_agg(to_jsonb(r) order by r.request_id),'[]') from trade_document_consent_private.receipts r where r.request_id=$4),
 'selection_md5',(select md5(to_jsonb(s)::text) from private.company_seal_png_selection s where s.company_id=$5),
 'payment_parents_md5',(select md5(coalesce(jsonb_agg(to_jsonb(p) order by p.id)::text,'[]')) from public.payment_certificates p)) v
 from public.invoices i where i.id=$1`,[x.parent,x.workspace.document_id,x.workspace.document_revision,x.rid,A])).rows[0].v;
 const tracked=promise=>{
  const task={done:false};
  task.result=promise.then(value=>({ok:true,value}),error=>({ok:false,error})).then(value=>{task.done=true;return value;});
  return task;
 };
 const lockWait=async(waiter,holder,task)=>{
  const deadline=Date.now()+5000;
  while(Date.now()<deadline){
   if(task.done){const outcome=await task.result;throw Error('public API race did not wait: '+(outcome.ok?'completed':outcome.error.message));}
   const activity=(await db.query('select wait_event_type,pg_blocking_pids(pid) blockers from pg_stat_activity where pid=$1',[waiter.processID])).rows[0];
   if(activity?.wait_event_type==='Lock'&&activity.blockers.includes(holder.processID)){
    check(task.done,false);check(activity.blockers.includes(holder.processID),true);return;
   }
   await new Promise(resolve=>setTimeout(resolve,25));
  }
  throw Error('public API transaction lock was not observed within five seconds');
 };
 const peers=async run=>{
  let one,two;
  try{
   one=await openNativePeer();two=await openNativePeer();
   await initialize(one);await initialize(two);await run(one,two);
  }finally{
   // Release the holder first; the blocked request and its queued RESET ROLE can
   // then complete before the second ROLLBACK/end. No original session is touched.
   if(one)await one.query('rollback').catch(()=>{});
   if(two)await two.query('rollback').catch(()=>{});
   await Promise.allSettled([one,two].filter(Boolean).map(peer=>peer.end()));
  }
 };
 const once=(after,before)=>{
  check(after.audit.filter(row=>row.action==='approved').length,1);
  check(after.approvals.length,1);check(after.approvals[0].status,'approved');
  check(after.consents.length,1);check(after.events.length,1);
  check(after.api_receipts.length,1);check(after.financial_receipts.length,1);check(after.primitive_receipts.length,1);
  check(after.revision.binding,before.revision.binding);check(after.revision.body,before.revision.body);
  check(after.parent.invoice_seal_frozen,true);
  check(after.parent.grand_total,before.parent.grand_total);check(after.parent.tax,before.parent.tax);
  check(after.selection_md5,before.selection_md5);check(after.payment_parents_md5,before.payment_parents_md5);
 };

 const duplicate=await prepare(1),duplicateBefore=await state(duplicate);
 await peers(async(one,two)=>{
  await one.query('begin');const first=await confirm(one,duplicate);
  check(first.operation,'invoice_final_approval_with_seal');check(first.result.financial_approved,true);
  const repeated=tracked(confirm(two,duplicate));await lockWait(two,one,repeated);
  await one.query('commit');const outcome=await repeated.result;assert.equal(outcome.ok,true,outcome.error?.message);check(outcome.value,first);
  const after=await state(duplicate);once(after,duplicateBefore);
  check((await receipt(two,duplicate)).result,first);
  check(await confirm(two,duplicate),first);check(await state(duplicate),after);
  const issued=await render(two,duplicate);check(issued.evidence.seals.length,1);
  check(issued.evidence.seals[0].seal_hash,duplicate.preview.display_preview.own_seal.seal_hash);
 });

 const stale=await prepare(2);
 await peers(async(editor,reviewer)=>{
  await editor.query('begin');await editor.query('update public.invoices set grand_total=grand_total+1 where id=$1',[stale.parent]);
  const pending=tracked(confirm(reviewer,stale));await lockWait(reviewer,editor,pending);
  await editor.query('commit');const edited=await state(stale),outcome=await pending.result;
  check(outcome.ok,false);check(outcome.error.code,'40001');check(/changed|attachment/.test(outcome.error.message),true);
  check(await state(stale),edited);check(edited.audit.length,0);check(edited.consents.length,0);check(edited.events.length,0);
  check(edited.api_receipts.length,0);check(edited.financial_receipts.length,0);check(edited.primitive_receipts.length,0);
  check((await receipt(reviewer,stale)).found,false);
 });

 const editAfter=await prepare(3),editBefore=await state(editAfter);
 await peers(async(reviewer,editor)=>{
  await reviewer.query('begin');const approved=await confirm(reviewer,editAfter),approvedRender=await render(reviewer,editAfter);
  const approvedState=await state(editAfter,reviewer);once(approvedState,editBefore);
  const editing=tracked(editor.query('update public.invoices set grand_total=grand_total+1 where id=$1',[editAfter.parent]));
  await lockWait(editor,reviewer,editing);await reviewer.query('commit');const outcome=await editing.result;assert.equal(outcome.ok,true,outcome.error?.message);
  await owner();await assert.rejects(render(db,editAfter),error=>error.code==='40001'&&/changed|attachment/.test(error.message));
  const archived=await render(db,editAfter,true);check(archived.evidence,approvedRender.evidence);
  const after=await state(editAfter);
  for(const key of ['consents','events','api_receipts','financial_receipts','primitive_receipts','revision','selection_md5','payment_parents_md5'])check(after[key],approvedState[key]);
  check(after.approvals[0].status,'pending');check(after.audit.filter(row=>row.action==='approved').length,1);check(after.audit.filter(row=>row.action==='content_changed').length,1);
  check(after.parent.invoice_seal_frozen,true);check(after.parent.snapshot,approvedState.parent.snapshot);
  check(Number(after.parent.grand_total),Number(approvedState.parent.grand_total)+1);check(after.parent.tax,approvedState.parent.tax);
  check((await receipt(db,editAfter)).result,approved);check(await confirm(db,editAfter),approved);check(await state(editAfter),after);
 });
 console.log('PASS native PUBLIC confirmation API races: two authenticated-role calls with existing synthetic session claims; duplicate uncommitted request waits and returns one immutable API receipt/one real approval/one seal consent; prior material edit refuses stale API command; following edit preserves approved archive/seal and receipt while current render refuses. No real JWT/HTTP, lost-COMMIT, production or device claim.');
}
