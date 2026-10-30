import fs from 'node:fs/promises';
import {createCanonicalSiteOrderRenderer,registerManagerCanonicalSiteOrderJob} from './site_order_canonical_renderer.mjs';
export async function verifySiteOrderPackageFlow(db,c){
 const {id,A,B,C,UA,UB,UC,actor,q,openNativePeer}=c;let checks=0;
 const check=(a,b)=>{if(JSON.stringify(a)!==JSON.stringify(b))throw Error('package fixture mismatch '+JSON.stringify(a)+' != '+JSON.stringify(b));checks++;};
 const deny=async(fn,p)=>{let error;try{await fn();}catch(e){error=e;}if(!error||!p.test(error.message))throw Error('Expected '+p+' got '+error?.message);checks++;};
 const signed=async uid=>{await actor(uid);const sid=await q('select id v from auth.sessions where user_id=$1',[uid]);await db.query("select set_config('test.jwt',$1,false)",[JSON.stringify({sub:uid,role:'authenticated',session_id:sid})]);};
 // Disposable surrounding tables match the metadata-only deployed column types.
 await db.exec(`alter table sites alter column id set default gen_random_uuid();
 alter table sites add column if not exists customer_id uuid,
 add column if not exists formal_name text,add column if not exists address text,
 add column if not exists nearest_station text,add column if not exists representative_name text,
 add column if not exists representative_phone text,add column if not exists notes text,
 add column if not exists status text not null default 'preparation',
 add column if not exists latitude double precision,add column if not exists longitude double precision,
 add column if not exists starts_at date,add column if not exists ends_at date,
 add column if not exists created_by uuid,add column if not exists updated_at timestamptz default now();
 create table private.document_deliveries(id uuid primary key,sender_company_id uuid not null,
 recipient_company_id uuid not null,sender_name text not null,recipient_name text not null,sent_by uuid,note text not null);
 create table private.company_data_delivery_items(id uuid primary key,delivery_id uuid not null references private.document_deliveries(id),
 payload_kind text not null,payload jsonb not null,company_path jsonb not null default '[]');
 create table private.site_share_inbox(data_item_id uuid primary key references private.company_data_delivery_items(id),
 recipient_company_id uuid not null,status text not null default 'pending',responded_by uuid,responded_at timestamptz,accepted_site_id uuid);
 create table public.app_notifications(company_id uuid,action_key text,action_id uuid,read_at timestamptz);
 grant usage on schema private to authenticated;
 `);
 await db.exec(await fs.readFile('tool/fixtures/site_order_legacy_private_respond.fixture.sql','utf8'));
 await db.exec(await fs.readFile('tool/fixtures/site_order_legacy_public_respond.fixture.sql','utf8'));
 await db.exec('revoke all on function public.respond_site_share(uuid,boolean) from public,anon;grant execute on function public.respond_site_share(uuid,boolean) to authenticated,service_role');
 const legacyMeta=()=>q(`select jsonb_agg(jsonb_build_object('oid',p.oid,'attrs',to_jsonb(p)-'prosrc','source',md5(p.prosrc))order by p.oid) v from pg_proc p where oid in('private.respond_site_share(uuid,boolean)'::regprocedure,'public.respond_site_share(uuid,boolean)'::regprocedure)`);
 const before=await legacyMeta();
 await db.exec('create temporary table site_order_legacy_expected(signature text primary key,attrs jsonb)');
 await db.exec(`insert into site_order_legacy_expected select case when p.oid='private.respond_site_share(uuid,boolean)'::regprocedure then 'private.respond_site_share(uuid,boolean)' else 'public.respond_site_share(uuid,boolean)' end,to_jsonb(p)-'prosrc' from pg_proc p
 where oid in('private.respond_site_share(uuid,boolean)'::regprocedure,'public.respond_site_share(uuid,boolean)'::regprocedure)`);
 // The exact legacy wrapper is prepared and invoked before body replacement.
 await db.exec('prepare before_package_guard(uuid,boolean) as select public.respond_site_share($1,$2)');
 await db.exec(await fs.readFile('docs/review/site-order-package-flow/foundation.sql.review-only','utf8'));
 await signed(UA);await db.query("update company_members set role='manager' where user_id=$1",[UA]);
 await db.query("update private.master_feature_settings set enabled=true where feature_key='site_order_documents'");
 await db.query("update sites set notes='非公開単価99999',address='共有現場住所' where id=$1",[id(9301)]);
 const source=await q(`select jsonb_build_object('job',j.id,'receipt',r.receipt_id) v from site_order_artifact_private.render_jobs j
 join site_order_artifact_private.pdf_records r on r.job_id=j.id where j.document_id=$1 and j.request_id=$2`,[id(10500),id(10503)]);
 const sitesBefore=await q('select count(*)::int v from sites');
 const send=(request=id(12000),job=source.job,receipt=source.receipt)=>q('select site_order_package_private.send_order($1,$2,$3) v',[job,receipt,request]);
 const received=await send();check(received.status,'received');check(received.recipient_company_id,B);
 check(await send(),received);check(await q('select count(*)::int v from site_order_package_private.packages'),1);
 check(await q('select count(*)::int v from site_order_package_private.notice_intents'),2);
 check(await q('select count(*)::int v from sites'),sitesBefore);
 const projection=await q('select payload v from private.company_data_delivery_items where id=$1',[received.data_item_id]);
 check(Object.keys(projection).sort(),['source_site_id','name','formal_name','address','nearest_station','representative_name','representative_phone','latitude','longitude','starts_on','ends_on','status'].sort());
 check(JSON.stringify(projection).includes('99999'),false);check(Object.hasOwn(projection,'notes'),false);
 await deny(()=>send(id(12001),source.job,id(999999)),/registered_original/);
 await deny(()=>send(id(12000),id(999999),source.receipt),/request_changed/);
 await db.query("update private.master_feature_settings set enabled=false where feature_key='site_order_documents'");
 await deny(()=>send(id(12002)),/master_feature_disabled/);
 await signed(UB);await db.query("update company_members set role='manager' where user_id=$1",[UB]);
 const packet=received.data_item_id;
 // Reproduce old partial approval, then roll it back: no original is altered.
 await db.exec('begin');
 try{
  const oldResult=(await db.query(`execute before_package_guard('${packet}',true)`)).rows[0].respond_site_share;
  check(typeof oldResult,'string');check(await q('select count(*)::int v from sites'),sitesBefore+1);
 }finally{await db.exec('rollback');}
 check(await q('select status v from private.site_share_inbox where data_item_id=$1',[packet]),'pending');
 const guard=await fs.readFile('docs/review/site-order-package-flow/legacy-response-guard.sql.review-only','utf8');
 // Full captured attributes, not only source, must stop a changed definition.
 await deny(async()=>{
  await db.exec("begin;alter function private.respond_site_share(uuid,boolean) set search_path='public'");
  try{await db.exec(guard);}finally{await db.exec('rollback');}
 },/source_or_attributes_changed/);
 await db.exec(guard);
 const after=await legacyMeta();check(after.map(x=>x.oid),before.map(x=>x.oid));
 check(after.map(x=>x.attrs),before.map(x=>x.attrs));
 await deny(()=>db.query(`execute before_package_guard('${packet}',true)`),/site_order_package_response_required/);
 check(await q('select count(*)::int v from sites'),sitesBefore);
 check(await q('select status v from private.site_share_inbox where data_item_id=$1',[packet]),'pending');
 // An ordinary legacy item continues working with new master flag OFF.
 const delivery=id(12100),ordinary=id(12101);
 await db.query("insert into private.document_deliveries values($1,$2,$3,'甲','乙',$4,'通常共有')",[delivery,A,B,UA]);
 await db.query("insert into private.company_data_delivery_items values($1,$2,'site_share',$3::jsonb,'[]')",[ordinary,delivery,JSON.stringify({name:'通常現場',address:'通常住所',notes:'通常説明'})]);
 await db.query("insert into private.site_share_inbox(data_item_id,recipient_company_id) values($1,$2)",[ordinary,B]);
 const ordinarySite=(await db.query(`execute before_package_guard('${ordinary}',true)`)).rows[0].respond_site_share;
 check(await q('select notes v from sites where id=$1',[ordinarySite]),'通常説明');
 check(await q('select status v from private.site_share_inbox where data_item_id=$1',[ordinary]),'accepted');
 await signed(UC);
 await deny(()=>db.query(`execute before_package_guard('${packet}',true)`),/受信した現場データが見つかりません/);
 for(const role of ['authenticated','service_role']){
  await db.exec('set role '+role);await deny(()=>q('select site_order_package_private.send_order($1,$2,$3) v',[source.job,source.receipt,id(12005)]),/permission denied/);await db.exec('reset role');
 }
 await deny(()=>db.exec('truncate site_order_package_private.packages cascade'),/immutable/);
 await db.exec(await fs.readFile('docs/review/site-order-package-flow/approval.sql.review-only','utf8'));
 await signed(UB);await db.query("update private.master_feature_settings set enabled=true where feature_key='site_order_documents'");
 const recipientTrade=id(12200);
 await db.query("insert into trade_companies select (jsonb_populate_record(null::trade_companies,to_jsonb(t)||jsonb_build_object('id',$1::uuid,'company_id',$2::uuid,'linked_company_id',$3::uuid,'trade_role','customer'))).* from trade_companies t where id=$4",[recipientTrade,B,A,id(2100)]);
 const recipientPeer=await q("select site_order_manager_private.counterparty_context($1,$2,'acceptance') v",[B,recipientTrade]);
 const approve=(request=id(12201),fp=recipientPeer.connection_fingerprint)=>q('select site_order_package_private.approve_order($1,$2,$3,$4) v',[received.package_id,recipientTrade,fp,request]);
 await deny(()=>approve(id(12201),'0'.repeat(64)),/exact_sender_connection/);
 const beforeApproval=await q('select count(*)::int v from sites');
 // A late reply-intent failure must roll back the site and inbox together.
 await db.exec("create function pg_temp.reject_reply()returns trigger language plpgsql as $$begin raise exception 'fixture_late_reply_failure';end$$;create trigger fixture_late_reply before insert on site_order_package_private.reply_intents for each row execute function pg_temp.reject_reply()");
 await deny(()=>approve(),/fixture_late_reply_failure/);
 check(await q('select count(*)::int v from sites'),beforeApproval);
 check(await q('select status v from private.site_share_inbox where data_item_id=$1',[packet]),'pending');
 await db.exec('drop trigger fixture_late_reply on site_order_package_private.reply_intents');
 const approved=await approve();check(approved.status,'approved_reply_awaiting_consent');
 check(await approve(),approved);check(await q('select count(*)::int v from sites'),beforeApproval+1);
 const actualSite=await q('select to_jsonb(s) v from sites s where id=$1',[approved.site_id]);
 check(actualSite.company_id,B);check(actualSite.notes,null);
 check(await q('select accepted_site_id v from private.site_share_inbox where data_item_id=$1',[packet]),approved.site_id);
 const reply=await q('select to_jsonb(i) v from site_order_package_private.reply_intents i where id=$1',[approved.reply_intent_id]);
 const originalBody=await q("select evidence->'body' v from site_order_artifact_private.render_jobs where id=$1",[source.job]);
 check(await q('select count(*)::int v from site_order_package_private.approval_notice_intents'),2);
 check(reply.body.kind,'acceptance');check(reply.body.issuer_company_id,B);check(reply.body.counterparty_company_id,A);
 check(reply.body.issuer,originalBody.counterparty);check(reply.body.counterparty,originalBody.issuer);
 const terms=b=>Object.fromEntries(Object.entries(b).filter(([k])=>!['kind','transaction_id','issuer_company_id','counterparty_company_id','issuer','counterparty'].includes(k)));
 check(terms(reply.body),terms(originalBody));check(reply.status,'awaiting_explicit_consent');
 await deny(()=>approve(id(12202)),/approval_request_changed/);
 await signed(UC);await deny(()=>approve(),/received_package_not_found/);
 await signed(UB);await db.query("update private.master_feature_settings set enabled=false where feature_key='site_order_documents'");
 await deny(()=>approve(),/master_feature_disabled/);
 check(await q('select count(*)::int v from site_order_package_private.reply_intents'),1);


 const reviewedApprovalSql=await fs.readFile('docs/review/site-order-package-flow/approval-consent.sql.review-only','utf8');
 await deny(async()=>{
 await db.exec("begin;alter function trade_document_consent_private.own_seal(uuid) set search_path='public'");
 try{await db.exec(reviewedApprovalSql);}finally{await db.exec('rollback');}
 },/seal_source_changed/);
 await db.exec(reviewedApprovalSql);
 await signed(UA);await db.query("update private.master_feature_settings set enabled=true where feature_key='site_order_documents'");
 const second=await send(id(12300));await signed(UB);
 const siteCount=await q('select count(*)::int v from sites');
 const documentCount=await q('select count(*)::int v from trade_document_consent_private.documents');
 const review=await q('select site_order_package_private.preview_approval($1,$2,$3,$4) v',[second.package_id,recipientTrade,recipientPeer.connection_fingerprint,id(12301)]);
 check(review.creates_site,false);check(review.consent_recorded,false);
 check(await q('select count(*)::int v from sites'),siteCount);
 check(await q('select count(*)::int v from trade_document_consent_private.documents'),documentCount);
 const confirm=(confirmed=true,hash=review.body_hash)=>q('select site_order_package_private.approve_with_consent($1,$2,$3,$4,$5) v',[review.preview_id,hash,review.own_seal.seal_hash,confirmed,id(12302)]);
 await deny(()=>confirm(false),/explicit_reviewed_consent/);
 await deny(()=>confirm(true,'0'.repeat(64)),/explicit_reviewed_consent/);
 await db.exec("create function pg_temp.reject_ready()returns trigger language plpgsql as $$begin raise exception 'fixture_late_ready_failure';end$$;create trigger fixture_late_ready before insert on site_order_package_private.ready_reply_jobs for each row execute function pg_temp.reject_ready()");
 await deny(()=>confirm(),/fixture_late_ready_failure/);
 check(await q('select count(*)::int v from sites'),siteCount);
 check(await q('select count(*)::int v from trade_document_consent_private.documents'),documentCount);
 check(await q('select status v from private.site_share_inbox where data_item_id=$1',[second.data_item_id]),'pending');
 await db.exec('drop trigger fixture_late_ready on site_order_package_private.ready_reply_jobs');
 const queued=await confirm();check(queued.status,'approved_reply_queued');check(await confirm(),queued);
 check(await q('select count(*)::int v from sites'),siteCount+1);
 check(await q('select count(*)::int v from trade_document_consent_private.documents'),documentCount+1);
 const canonicalReply=await q('select evidence v from site_order_artifact_private.render_jobs where id=$1',[queued.job_id]);
 check(canonicalReply.body,review.body);check(canonicalReply.render_seal_company_id,B);
 // The worker is called after the approval statement committed, on a fresh TX.
 const renderer=await createCanonicalSiteOrderRenderer({dartExecutable:process.env.SKO_CANONICAL_DART,repositoryRoot:process.cwd()});
 const originalReply=await registerManagerCanonicalSiteOrderJob(db,queued.job_id,renderer);
 check(originalReply.document_id,review.body.transaction_id);
 check(await registerManagerCanonicalSiteOrderJob(db,queued.job_id,()=>{throw Error('Reply original must be reused');}),originalReply);

 await db.exec(await fs.readFile('docs/review/site-order-package-flow/archive-read.sql.review-only','utf8'));
 await db.query("update private.master_feature_settings set enabled=false where feature_key='site_order_documents'");
 for(const user of [UA,UB])for(const role of ['owner','admin','manager']){
 await signed(user);await db.query('update company_members set role=$1 where user_id=$2',[role,user]);
 const status=await q('select site_order_package_private.package_status($1) v',[second.package_id]);
 check(status.approved,true);check(status.reply_original_registered,true);check(status.reply_delivered,false);
 for(const kind of ['order','acceptance']){
 const bytes=await q('select site_order_package_private.archive_original($1,$2) v',[second.package_id,kind]);
 check(Buffer.from(bytes).subarray(0,5).toString(),'%PDF-');
 }
 }
 await signed(UB);await deny(()=>confirm(),/master_feature_disabled/);
 await deny(()=>registerManagerCanonicalSiteOrderJob(db,queued.job_id,renderer),/registration_rejected/);
 await signed(UC);await deny(()=>q('select site_order_package_private.package_status($1) v',[second.package_id]),/archive_not_found/);
 await signed(UB);await db.query("update company_members set role='worker' where user_id=$1",[UB]);
 await deny(()=>q("select site_order_package_private.archive_original($1,'order') v",[second.package_id]),/archive_management/);
 await db.query("update company_members set role='manager' where user_id=$1",[UB]);
 await (await import('./site_order_http_jwt_fixture.mjs')).verifySiteOrderHttpJwt(db,{id,UA,UB,UC,q,check,second,queued,renderer,openNativePeer});

 await db.exec(`alter table public.app_notifications add column if not exists id uuid default gen_random_uuid(),
 add column if not exists recipient_user_id uuid,add column if not exists kind text,
 add column if not exists title text,add column if not exists body text,add column if not exists created_at timestamptz default now()`);
 await db.exec(`alter table public.app_notifications rename to fixture_legacy_notifications;
 create table public.app_notifications(id uuid primary key default gen_random_uuid(),company_id uuid not null,
 recipient_user_id uuid not null,kind text not null default 'info',title text not null,body text,action_key text,action_id uuid,
 read_at timestamptz,created_at timestamptz not null default now());
 alter table public.app_notifications enable row level security`);
 await db.exec(await fs.readFile('docs/review/site-order-package-flow/delivery.sql.review-only','utf8'));
 await signed(UA);await deny(()=>q("select site_order_package_private.archive_original($1,'acceptance') v",[second.package_id]),/original_not_registered/);
 await signed(UB);await deny(()=>q('select site_order_package_private.deliver_acceptance($1,$2,$3) v',[second.package_id,id(999999),id(12302)]),/registered_original/);
 // Force the notification stage to fail after recipient receipt insertion.
 // The outer delivery transaction must roll both stages back together.
 await db.exec("create function pg_temp.reject_order_notice()returns trigger language plpgsql as $$begin raise exception 'fixture_notice_failure';end$$;create trigger fixture_notice_failure before insert on public.app_notifications for each row execute function pg_temp.reject_order_notice()");
 const {processCanonicalSiteOrderReply}=await import('./site_order_canonical_core.mjs');
 const ubSid=await q('select id v from auth.sessions where user_id=$1',[UB]);
 const verifiedClaims={sub:UB,role:'authenticated',session_id:ubSid};
 await deny(()=>processCanonicalSiteOrderReply(db,second.package_id,renderer,verifiedClaims),/reply_rejected/);
 check(await q('select count(*)::int v from site_order_package_private.acceptance_deliveries'),0);
 check(await q('select count(*)::int v from site_order_package_private.notification_receipts'),0);
 await db.exec('drop trigger fixture_notice_failure on public.app_notifications');
 const delivered=await processCanonicalSiteOrderReply(db,second.package_id,renderer,verifiedClaims);
 check(delivered.status,'recipient_stored');check(delivered.notifications.app_inbox_inserted>0,true);
 await db.query("update private.master_feature_settings set enabled=false where feature_key='site_order_documents'");
 await (await import('./site_order_http_jwt_fixture.mjs')).verifySiteOrderHttpJwt(db,{id,UA,UB,UC,q,check,second,queued,renderer,openNativePeer,processReply:true});
 const storedCount=await q('select count(*)::int v from public.app_notifications');
 const replay=await processCanonicalSiteOrderReply(db,second.package_id,()=>{throw Error('Do not rerender delivered reply');},verifiedClaims);
 check(replay.status,'recipient_stored');check(replay.notifications.app_inbox_inserted,0);
 check(await q('select count(*)::int v from public.app_notifications'),storedCount);
 check(await q("select count(*)::int v from public.app_notifications where action_key<>'site_order_package' or body like '%99999%' or title like '%99999%'"),0);
 await db.query("update private.master_feature_settings set enabled=false where feature_key='site_order_documents'");
 for(const user of [UA,UB])for(const role of ['owner','admin','manager']){
 await signed(user);await db.query('update company_members set role=$1 where user_id=$2',[role,user]);
 check((await q('select site_order_package_private.delivery_status($1) v',[second.package_id])).reply_recipient_stored,true);
 const original=await q("select site_order_package_private.archive_original($1,'acceptance') v",[second.package_id]);
 check(Buffer.from(original).subarray(0,5).toString(),'%PDF-');
 }
 await signed(UB);await deny(()=>q('select site_order_package_private.dispatch_notifications($1) v',[second.package_id]),/master_feature_disabled/);

 await db.exec(await fs.readFile('docs/review/site-order-package-flow/read-surfaces.sql.review-only','utf8'));
 await signed(UA);
 const detail=await q('select site_order_package_private.package_detail($1) v',[second.package_id]);
 check(detail.reply_recipient_stored,true);check(detail.can_write,false);check(detail.body.work_name,originalBody.work_name);
 const firstPage=await q('select site_order_package_private.package_list(null,null,1) v');check(firstPage.length,1);
 const nextPage=await q('select site_order_package_private.package_list($1,$2,1) v',[firstPage[0].created_at,firstPage[0].package_id]);
 check(nextPage.length,1);check(nextPage[0].package_id===firstPage[0].package_id,false);
 await signed(UC);await deny(()=>q('select site_order_package_private.package_detail($1) v',[second.package_id]),/archive_not_found/);
 console.log(JSON.stringify({status:'passed',checks,scope:'canonical original + sanitized receive + real site/acceptance intent approval atomicity; prepared legacy guard; ordinary legacy OFF unchanged',production_applied:false,real_auth:false}));
}
