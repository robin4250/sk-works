// Public SQL-role/session guard proof. Claims/sessions here are synthetic;
// actual GoTrue/PostgREST JWT verification is a separate required proof stage.
import fs from 'node:fs/promises';
import {deflateSync} from 'node:zlib';
import {createHash} from 'node:crypto';
export async function verifyConfirmationApi(db,c){
 const {id,A,B,C,UA,UB,UV,UC,PARTNER,CUSTOMER,actor,q,check,deny,localId,prepareMonthly}=c;
 await actor(UA);
 await db.exec(`create table auth.sessions(id uuid primary key,user_id uuid not null);
 create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('test.jwt',true),''),'{}')::jsonb$$`);
 const sessions=new Map([[UA,id(8001)],[UB,id(8002)],[UV,id(8003)],[UC,id(8004)]]);
 for(const [uid,sid] of sessions)await db.query('insert into auth.sessions values($1,$2)',[sid,uid]);
 const asActor=async uid=>{await actor(uid);await db.query("select set_config('test.jwt',$1,false)",[JSON.stringify({sub:uid,role:'authenticated',session_id:sessions.get(uid)})]);};
 await asActor(UA);
 const api=async(sql,args=[])=>{await db.exec('set role authenticated');try{return await q(sql,args);}finally{await db.exec('reset role');}};
 const workspace=(kind,parent,rev)=>api('select public.trade_document_confirmation_workspace($1,$2,$3) v',[kind,parent,rev]);
 const preview=w=>api('select public.preview_trade_document_confirmation($1,$2,$3,$4) v',[w.company_id,w.local_document_id,w.document_revision,w.kind]);
 const confirm=(p,rid,document=true,seal=true)=>api('select public.confirm_trade_document_with_seal($1::jsonb,$2,$3,$4) v',[JSON.stringify(p.expected_command),rid,document,seal]);
 const receipt=(p,rid)=>api('select public.read_trade_document_confirmation_receipt($1,$2,$3::jsonb) v',[p.company_id,rid,JSON.stringify(p.expected_command)]);
 const render=(w,archive=false)=>api('select public.render_confirmed_trade_document($1,$2,$3,$4,$5) v',[w.company_id,w.local_document_id,w.document_revision,w.kind,archive]);
 const resolve=(kind,parent)=>api('select public.resolve_trade_document_confirmation($1,$2) v',[kind,parent]);
 const protectedState=()=>q(`select jsonb_build_object('parents',(select jsonb_agg(to_jsonb(p) order by id) from payment_certificates p),
 'invoices',(select jsonb_agg(to_jsonb(i) order by id) from invoices i),'invoice_approvals',(select jsonb_agg(to_jsonb(a) order by invoice_id,position) from invoice_approvals a),
 'invoice_audit',(select jsonb_agg(to_jsonb(a) order by id) from invoice_approval_audit a),
 'consents',(select jsonb_agg(to_jsonb(a) order by document_id,revision,company_id) from trade_document_consent_private.consents a),
 'api_receipts',(select jsonb_agg(to_jsonb(a) order by company_id,request_id) from trade_document_confirmation_api_private.receipts a)) v`);
 const beforeInstall=await q("select jsonb_build_object('payment',(select jsonb_agg(to_jsonb(p) order by id) from payment_certificates p),'invoices',(select jsonb_agg(to_jsonb(i) order by id) from invoices i)) v");
 await db.exec(await fs.readFile('docs/candidates/trade_document_confirmation_api_20261022.sql.review-only','utf8'));
 check(await q("select jsonb_build_object('payment',(select jsonb_agg(to_jsonb(p) order by id) from payment_certificates p),'invoices',(select jsonb_agg(to_jsonb(i) order by id) from invoices i)) v"),beforeInstall);
 check(await api('select public.trade_document_confirmation_contract_version() v'),1);
 const monthly=await prepareMonthly(31);await asActor(UA);
 const originalMonthly=await q('select to_jsonb(p) v from payment_certificates p where id=$1',[monthly.parent]);
 check((await resolve('payment_certificate',monthly.parent)).unavailable_reason,'not_prepared');
 const w=await workspace('payment_certificate',monthly.parent,'1');check(w.can_integrated_confirm,true);check(w.side,'issued');
 check(await workspace('payment_certificate',monthly.parent,'1'),w);
 check(w.document_id===w.local_document_id,false);check(w.document_id===monthly.parent,false);
 const p=await preview(w);check(Object.keys(p.expected_command).length,12);check(p.display_preview.body_hash,p.expected_command.body_hash);
 if(c.confirmedTerms)check(p.display_preview.body.contract_terms,c.confirmedTerms);
 check(p.display_preview.body.kind,'order');check(p.display_preview.body.issuer_company_id,A);
 check((await receipt(p,id(8101))).found,false);
 const deniedBefore=await protectedState();await deny(()=>confirm(p,id(8101),true,false),/confirmation and issuer seal/);check(await protectedState(),deniedBefore);
 await deny(()=>confirm({...p,expected_command:{...p.expected_command,png_base64:'x'}},id(8101)),/exact saved/);check(await protectedState(),deniedBefore);
 const approved=await confirm(p,id(8101));check(approved.operation,'monthly_content_review_with_seal');check(approved.result.financial_finalized,false);
 check(await q('select to_jsonb(p) v from payment_certificates p where id=$1',[monthly.parent]),originalMonthly);
 check(await confirm(p,id(8101)),approved);check((await receipt(p,id(8101))).result,approved);
 await deny(()=>confirm({...p,expected_command:{...p.expected_command,preview_hash:'f'.repeat(64)}},id(8101)),/payload changed/);
 const issued=await render(w);if(c.confirmedTerms)check(issued.evidence.body.contract_terms,c.confirmedTerms);check(issued.side,'issued');check(issued.evidence.seals.length,1);
 check((await resolve('payment_certificate',monthly.parent)).phase,'approved');
 const reverseTrade=id(8200);await db.query("insert into trade_companies(id,company_id,linked_company_id,trade_role,link_status) values($1,$2,$3,'customer','linked')",[reverseTrade,B,A]);
 await asActor(UB);
 const list=await api('select public.list_received_trade_document_confirmations($1) v',[reverseTrade]);check(list.items.length,1);check(list.items[0].document_id,w.document_id);
 const rw=await api('select public.received_trade_document_confirmation_workspace($1,$2,$3) v',[reverseTrade,w.document_id,w.document_revision]);
 check(rw.side,'received');check(rw.local_document_id===w.local_document_id,false);
 check(await api('select public.received_trade_document_confirmation_workspace($1,$2,$3) v',[reverseTrade,w.document_id,w.document_revision]),rw);
 const receivedRender=await render(rw);check(receivedRender.evidence,issued.evidence);await deny(()=>preview(rw),/issuer confirmation/);
 await deny(()=>receipt(p,id(8101)),/permission|scope/);
 for(const uid of [UV,UC]){await asActor(uid);await deny(()=>workspace('payment_certificate',monthly.parent,'1'),/permission/);}
 await asActor(UA);await db.exec("select set_config('test.blocked','true',false)");await deny(()=>preview(w),/signed-in/);await db.exec("select set_config('test.blocked','false',false)");
 await db.query('delete from auth.sessions where id=$1',[sessions.get(UA)]);await deny(()=>preview(w),/session/);await deny(()=>receipt(p,id(8101)),/session/);await deny(()=>render(w),/session/);
 await db.query('insert into auth.sessions values($1,$2)',[sessions.get(UA),UA]);
 await db.exec('set role anon');await deny(()=>q('select public.trade_document_confirmation_contract_version() v'),/permission denied/);await db.exec('reset role');
 await db.exec('set role authenticated');await deny(()=>q('select trade_document_consent_private.decide($1,1,$2,0,$3,\'approve\',$4,true,$5) v',[w.document_id,A,p.body_hash,p.display_preview.own_seal.seal_hash,id(8102)]),/permission denied/);await db.exec('reset role');
 const stale=await prepareMonthly(32);await asActor(UA);const sw=await workspace('payment_certificate',stale.parent,'1'),sp=await preview(sw);
 await db.query('update payment_certificates set gross_amount=gross_amount+1,revision=revision+1 where id=$1',[stale.parent]);const staleBefore=await protectedState();
 await deny(()=>confirm(sp,id(8103)),/changed|attachment/);check(await protectedState(),staleBefore);
 await db.query('update payment_certificates set gross_amount=gross_amount+1,revision=revision+1 where id=$1',[monthly.parent]);
 check((await resolve('payment_certificate',monthly.parent)).can_render_current,false);check((await resolve('payment_certificate',monthly.parent)).can_render_archive,true);
 await deny(()=>render(w),/changed|attachment/);check((await render(w,true)).evidence,issued.evidence);
 // A real registered PNG larger than the old 64KiB private expected bound.
 const large=await prepareMonthly(33);await asActor(UA);
 const bytes=largePng(),selection=await q('select revision v from private.company_seal_png_selection where company_id=$1',[A]);
 await q('select public.save_company_uploaded_seal($1,$2,$3,$4,$5,true) v',[A,'甲会社',selection,bytes.toString('base64'),createHash('sha256').update(bytes).digest('hex')]);
 const lw=await workspace('payment_certificate',large.parent,'1'),lp=await preview(lw);
 check(Buffer.byteLength(JSON.stringify(lp.display_preview))>65536,true);check(Buffer.byteLength(JSON.stringify(lp.expected_command))<8192,true);
 check((await confirm(lp,id(8104))).result.financial_finalized,false);
 // Restore a small registered image for shareable invoice response fixtures.
 const invoiceSealRevision=await q('select revision v from private.company_seal_png_selection where company_id=$1',[A]);
 await c.upload(A,'甲会社',invoiceSealRevision,32);
 // Existing invoice final approval, not a parallel content-review writer.
 const inv=id(8300);await db.query("insert into invoices(id,company_id,customer_id,billing_period_start,billing_period_end,updated_at,status,grand_total,tax,snapshot) values($1,$2,$3,'2026-10-01','2026-10-31',clock_timestamp(),'draft',110000,10000,'{}')",[inv,A,CUSTOMER]);
 await db.query('select private.ensure_invoice_approval_rows($1)',[inv]);
 const invSource=await q('select updated_at::text v from invoices where id=$1',[inv]);
 const iwSource=await q("select public.trade_document_attachment_workspace('invoice',$1,$2) v",[inv,invSource]);
 const payload={...iwSource.defaults,company_seal_enabled:false,company_seal_snapshot:null,issue_date:'2026-10-22',order_date:'2026-10-21',work_name:'公開承認合成工事',work_address:'東京都',acceptance_text:'上記注文内容を承諾します。',intro_text:'合成請負',payment_conditions:'翌月末',notes:''};
 if(c.confirmedTerms)payload.contract_terms=c.confirmedTerms;
 await q("select public.save_trade_document_attachment('invoice',$1,$2,0,$3::jsonb) v",[inv,invSource,JSON.stringify(payload)]);
 // Ordinary assigned member approval remains on the existing path, with no
 // evidence preparation or permission-error fallback. Final stamp authority
 // and normal invoice-view permission remain independent requirements.
 await db.query("insert into invoice_approvals(invoice_id,company_id,approver_user_id,position) values($1,$2,$3,2)",[inv,A,UV]);
 await db.query("update company_members set role='member' where company_id=$1 and user_id=$2",[A,UV]);
 await asActor(UV);const member=await workspace('invoice',inv,invSource);
 check(member.integration_required,false);check(member.unavailable_reason,'ordinary_assigned_approval');check(member.document_id,null);
 await db.exec("select set_config('test.invoice_view','false',false)");await deny(()=>workspace('invoice',inv,invSource),/permission/);await db.exec("select set_config('test.invoice_view','true',false)");
 await asActor(UA);const nonfinal=await workspace('invoice',inv,invSource);check(nonfinal.integration_required,false);check(nonfinal.document_id,null);
 check(await q('select count(*)::int v from trade_document_confirmation_api_private.parent_links where parent_id=$1',[inv]),0);
 await asActor(UV);check(await api('select public.approve_invoice($1) v',[inv]),false);
 check(await q("select status v from invoice_approvals where invoice_id=$1 and approver_user_id=$2",[inv,UV]),'approved');
 await db.query("update company_members set role='viewer' where company_id=$1 and user_id=$2",[A,UV]);
 await asActor(UV);await deny(()=>workspace('invoice',inv,invSource),/permission/);
 await asActor(UA);
 const iw=await workspace('invoice',inv,invSource),ip=await preview(iw),invBefore=await q('select to_jsonb(i) v from invoices i where id=$1',[inv]);
 const invoiceResult=await confirm(ip,id(8105));check(invoiceResult.operation,'invoice_final_approval_with_seal');check(invoiceResult.result.financial_approved,true);
 const invAfter=await q('select to_jsonb(i) v from invoices i where id=$1',[inv]);check(invAfter.grand_total,invBefore.grand_total);check(invAfter.tax,invBefore.tax);check(invAfter.invoice_seal_frozen,true);
 check(await q("select count(*)::int v from invoice_approval_audit where invoice_id=$1",[inv]),2);
 check(await confirm(ip,id(8105)),invoiceResult);check((await resolve('invoice',inv)).phase,'approved');
 const invoiceRender=await render(iw);if(c.confirmedTerms)check(invoiceRender.evidence.body.contract_terms,c.confirmedTerms);check(invoiceRender.evidence.body.kind,'acceptance');
 await asActor(UB);
 const invoiceReceivedWorkspace=await api('select public.received_trade_document_confirmation_workspace($1,$2,$3) v',[reverseTrade,iw.document_id,iw.document_revision]);
 const invoiceReceivedRender=await render(invoiceReceivedWorkspace);
 check(invoiceReceivedWorkspace.local_document_id===iw.local_document_id,false);check(invoiceReceivedRender.evidence,invoiceRender.evidence);
 await asActor(UA);
 if(process.env.SKO_TRADE_DOCUMENT_API_EXPORT){
  await fs.writeFile(process.env.SKO_TRADE_DOCUMENT_API_EXPORT,JSON.stringify({synthetic_fixture:true,ordinary_assigned_workspace:member,issued_workspace:w,issued_preview:p,confirmation:approved,received_list:list,received_workspace:rw,issued_render:issued,received_render:receivedRender,invoice_render:invoiceRender,invoice_received_workspace:invoiceReceivedWorkspace,invoice_received_render:invoiceReceivedRender,invoice_expected_command:ip.expected_command,invoice_confirmation:invoiceResult},null,2)+'\n');
 }
 if(c.openNativePeer)await (await import('./trade_document_confirmation_api_races.mjs')).verifyPublicConfirmationApiRaces(db,c);
 console.log('PASS public API candidate: current SQL session/role/issuer authority, idempotent parent and received workspaces, compact command, real invoice final approve, monthly unchanged parent, exact receipt replay, current/archive body, primitive bypass/session revocation refusals and registered PNG over 64KiB');
}

function largePng(){
 const crc32=bytes=>{let c=0xffffffff;for(const b of bytes){c^=b;for(let k=0;k<8;k++)c=(c>>>1)^((c&1)?0xedb88320:0);}return(c^0xffffffff)>>>0;};
 const chunk=(type,data)=>{const t=Buffer.from(type),size=Buffer.alloc(4),crc=Buffer.alloc(4);size.writeUInt32BE(data.length);crc.writeUInt32BE(crc32(Buffer.concat([t,data])));return Buffer.concat([size,t,data,crc]);};
 const h=Buffer.alloc(13);h.writeUInt32BE(256);h.writeUInt32BE(256,4);h[8]=8;h[9]=6;
 const raw=Buffer.alloc(256*(1+256*4));let seed=12345;
 for(let y=0;y<256;y++)for(let x=0;x<256;x++){const n=y*1025+1+x*4;for(let c=0;c<3;c++){seed=(Math.imul(seed,1664525)+1013904223)>>>0;raw[n+c]=seed>>>24;}raw[n+3]=255;}
 return Buffer.concat([Buffer.from('89504e470d0a1a0a','hex'),chunk('IHDR',h),chunk('IDAT',deflateSync(raw)),chunk('IEND',Buffer.alloc(0))]);
}
