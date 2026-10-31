import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {verifyConsentHttp} from './http.mjs';
const ownRoot=path.resolve(new URL('../../../',import.meta.url).pathname);
export async function verifyConsent(db,{q,check,sourceContract}){
 const authRoot=process.env.SKO_ACTUAL_AUTH_SOURCE_ROOT;
 if(!authRoot||!path.isAbsolute(authRoot))throw Error('pinned actual Auth source root required');
 const auth=await fs.readFile(path.join(authRoot,'docs/review/atomic-document-evidence/actual-generic-helper-fixture.sql'),'utf8');
 assert.equal(createHash('sha256').update(auth).digest('hex'),'06a08a6b0d66269780045e8bb5740c9358e8afd5b630cc23a532db8b6d87e594');
 const raw=await fs.readFile(path.join(authRoot,'docs/review/atomic-document-evidence/helper-contracts.json'),'utf8');
 assert.equal(createHash('sha256').update(raw).digest('hex'),'e8bf4bb4c665078f7f41ceef5a4fb6fe7a044dec67ad73a794b3c923cd810aa2');
 const catalog=()=>q('select jsonb_agg(to_jsonb(p)order by p.oid)v from pg_proc p where p.oid=any($1::regprocedure[])',[[...sourceContract.functions.map(f=>f.signature),'private.require_standalone_trade_document_access()']]);
 const before=await catalog();
 const boundary=auth.indexOf('CREATE OR REPLACE FUNCTION private.account_access_allowed()');
 if(boundary<0)throw Error('Auth extraction boundary changed');await db.exec(auth.slice(0,boundary));
 const contracts=JSON.parse(raw).filter(x=>['auth.uid()','auth.jwt()'].includes(x.signature));check(contracts.length,2);
 for(const c of contracts){
  check(await q('select md5(prosrc)v from pg_proc where oid=to_regprocedure($1)',[c.signature]),c.body_md5);
  await db.exec(`alter function ${c.signature} owner to supabase_auth_admin;revoke all on function ${c.signature} from public,postgres,supabase_auth_admin,dashboard_user,anon,authenticated,service_role;set role supabase_auth_admin`);
  try{for(const a of c.acl){if(!/^(PUBLIC|postgres|supabase_auth_admin|dashboard_user|anon|authenticated|service_role)$/.test(a.grantee)||a.grantor!=='supabase_auth_admin'||a.privilege!=='EXECUTE'||a.grant_option)throw Error('Auth ACL changed');await db.exec(`grant execute on function ${c.signature} to ${a.grantee}`);}}finally{await db.exec('reset role');}
 }
 check(await catalog(),before);
 const read=p=>fs.readFile(path.join(ownRoot,p),'utf8');
 await db.exec('alter table private.partner_company_profile_extensions enable row level security;revoke all on private.partner_company_profile_extensions from public,anon,authenticated,service_role');
 await db.exec(await read('docs/review/site-order-outgoing/source-and-prepare-observation.sql.review-only'));
 await db.exec(await read('docs/review/site-order-outgoing/prepare-operation.sql.review-only'));
 const sql=await read('docs/review/site-order-outgoing-consent/coordinator.sql.review-only');
 const denied=async(fn,pattern)=>{let e;try{await fn();}catch(x){e=x;}if(!e||!pattern.test(e.message))throw Error('expected '+pattern+' got '+e?.message);check(true,true);};
 await db.exec(sql);check(await catalog(),before);
 const id=n=>'91000000-0000-4000-8000-'+n.toString(16).padStart(12,'0');
 const A=id(1),B=id(2),UA=id(3),UB=id(4),sid=id(5),sid2=id(6),site=id(7),trade=id(8);
 await db.query('insert into auth.users(id)values($1),($2)',[UA,UB]);
 await db.query('insert into auth.sessions(id,user_id)values($1,$2),($3,$2)',[sid,UA,sid2]);
 await db.query("insert into public.companies(id,name,address,phone,fax,company_seal_style,company_seal_enabled)values($1,'株式会社','住所','03-1','03-2','legacy',true),($2,'有限会社','相手住所','03-3','03-4','legacy',true)",[A,B]);
 await db.query("insert into public.company_members values($1,$2,'manager'),($3,$4,'manager')",[A,UA,B,UB]);
 await db.query("insert into public.sites(id,company_id,name)values($1,$2,'Fixture site')",[site,A]);
 await db.query("insert into public.trade_companies(id,company_id,name,trade_role,linked_company_id,link_status)values($1,$2,'有限会社','subcontractor',$3,'linked')",[trade,A,B]);
 await db.query("insert into private.company_connections(parent_company_id,child_company_id,status,requested_by)values($1,$2,'accepted',$3)",[A,B,UA]);
 const saved=await q("select jsonb_build_object('claims',current_setting('request.jwt.claims',true),'sub',current_setting('request.jwt.claim.sub',true),'claim',current_setting('request.jwt.claim',true))v");
 const previousFeature=await q("select enabled v from private.master_feature_settings where feature_key='site_order_documents'");
 const claims=(u=UA,s=sid)=>JSON.stringify({sub:u,session_id:s,role:'authenticated',is_anonymous:false});
 const use=async(s=sid)=>db.query("select set_config('request.jwt.claim.sub','',false),set_config('request.jwt.claim','',false),set_config('request.jwt.claims',$1,false)",[claims(UA,s)]);
 const sample=JSON.parse(await read('tool/canonical_renderer/synthetic-evidence.json')).body;
 const make=async n=>{const context=await q('select site_order_manager_private.outgoing_context($1,$2)v',[site,trade]);const x={doc:id(n),local:id(n+1),request:id(n+2),decision:id(n+3),context};x.body={...sample,transaction_id:x.doc,issuer_company_id:A,counterparty_company_id:B,issuer:context.issuer,counterparty:context.counterparty};return x;};
 const params=x=>[site,x.doc,x.local,trade,x.request];
 const prepare=x=>q('select site_order_outgoing_private.prepare_order($1,$2,$3,$4,$5,$6,$7::jsonb)v',[...params(x),x.context.connection_fingerprint,JSON.stringify(x.body)]);
 const preview=x=>q('select site_order_outgoing_private.preview_unsigned($1,$2,$3,$4,$5)v',params(x));
 const confirm=(x,p,yes=true)=>q('select site_order_outgoing_private.confirm_unsigned($1,$2,$3,$4,$5,$6,$7,$8)v',[...params(x),p.preview_id,x.decision,yes]);
 const status=(x,p)=>q('select site_order_outgoing_private.decision_status($1,$2,$3,$4,$5,$6,$7)v',[...params(x),p.preview_id,x.decision]);
 try{
  await use();await db.query("insert into private.master_feature_settings(feature_key,enabled)values('site_order_documents',true)on conflict(feature_key)do update set enabled=true");
  const x=await make(100);await prepare(x);const p=await preview(x);
  check(p.preview_only,true);check(p.can_send,false);check(Object.hasOwn(p,'consents'),false);
  await denied(()=>confirm(x,p,false),/explicit_confirmation/);
  const first=await confirm(x,p);check(first.operation_state,'decision_job_prepared');check(first.sent,false);check(first.original_registered,false);check(first.journal_clearable,false);
  check(await confirm(x,p),first);check((await status(x,p)).read_only,true);
  check(await q('select count(*)::int v from site_order_artifact_private.render_jobs where request_id=$1',[x.decision]),1);
  await denied(()=>confirm({...x,decision:id(109)},p),/not_unsigned/);
  await db.query("update private.master_feature_settings set enabled=false where feature_key='site_order_documents'");
  await denied(()=>confirm(x,p),/master_feature_disabled/);check((await status(x,p)).job_id,first.job_id);
  await use(sid2);check((await status(x,p)).same_session,false);
  await db.query("update private.master_feature_settings set enabled=true where feature_key='site_order_documents'");
  await denied(()=>confirm(x,p),/identity_changed/);await use();
  const roll=await make(120);await prepare(roll);const rp=await preview(roll);
  await db.exec("create function pg_temp.reject_decision_receipt()returns trigger language plpgsql as $$begin raise exception 'fixture_receipt_failure';end$$;create trigger fixture_reject_decision before insert on site_order_outgoing_private.decision_receipts for each row execute function pg_temp.reject_decision_receipt()");
  await denied(()=>confirm(roll,rp),/fixture_receipt_failure/);
  check(await q('select state v from trade_document_consent_private.revisions where document_id=$1',[roll.doc]),'open');
  check(await q('select count(*)::int v from trade_document_consent_private.receipts where request_id=$1',[roll.decision]),0);
  check(await q('select count(*)::int v from site_order_artifact_private.render_jobs where request_id=$1',[roll.decision]),0);
  await db.exec('drop trigger fixture_reject_decision on site_order_outgoing_private.decision_receipts');
  const wrong=await make(140);await prepare(wrong);const wp=await preview(wrong);
  await db.query("insert into trade_document_consent_private.receipts(request_id,actor_id,payload,result)values($1,$2,'{}','{}')",[wrong.decision,UA]);
  await denied(()=>confirm(wrong,wp),/request_already_used/);
  const borrowed=await make(160);await prepare(borrowed);const bp=await preview(borrowed);
  await db.query(`insert into site_order_artifact_private.render_jobs(id,company_id,counterparty_company_id,counterparty_name,
   counterparty_trade_company_id,counterparty_connection_fingerprint,site_id,document_id,document_revision,request_id,
   actor_id,session_id,render_hash,body_hash,evidence,layout_contract)
   select gen_random_uuid(),company_id,counterparty_company_id,counterparty_name,counterparty_trade_company_id,
   counterparty_connection_fingerprint,site_id,document_id,document_revision,$1,actor_id,session_id,render_hash,body_hash,evidence,layout_contract
   from site_order_artifact_private.render_jobs where id=$2`,[borrowed.decision,first.job_id]);
  await denied(()=>confirm(borrowed,bp),/request_already_used/);
  check(await q('select count(*)::int v from trade_document_consent_private.receipts where request_id=$1',[borrowed.decision]),0);
  for(const role of ['anon','authenticated','service_role']){await db.exec('set role '+role);try{await denied(()=>status(x,p),/permission denied/);}finally{await db.exec('reset role');}}
  await verifyConsentHttp(db,{q,check,UA,A,sid,sid2,make,prepare,params});
  let nativeWaits=0;
  if(process.argv[3]==='postgres'){
   const pg=(await import(process.argv[2])).default;
   const peer=new pg.Client({connectionString:process.env.SKO_CONSENT_FIXTURE_URL,application_name:'sko-consent-peer'});
   await peer.connect();
   try{
    await peer.query("select set_config('request.jwt.claim.sub','',false),set_config('request.jwt.claim','',false),set_config('request.jwt.claims',$1,false)",[claims()]);
    const blocked=async()=>{for(let n=0;n<100;n++){if(await q("select exists(select 1 from pg_stat_activity where application_name='sko-consent-peer' and wait_event_type='Lock')v")){nativeWaits++;return;}await new Promise(r=>setTimeout(r,10));}throw Error('Native peer did not really wait');};
    const peerConfirm=(x,p)=>peer.query('select site_order_outgoing_private.confirm_unsigned($1,$2,$3,$4,$5,$6,$7,true)v',[...params(x),p.preview_id,x.decision]);
    const peerRetire=x=>peer.query('select site_order_outgoing_private.retire_prepare($1,$2,$3,$4,$5,true)v',params(x));
    const retireFirst=await make(200);await prepare(retireFirst);const rfp=await preview(retireFirst);
    await db.exec('begin');
    await q('select site_order_outgoing_private.retire_prepare($1,$2,$3,$4,$5,true)v',params(retireFirst));
    const waitingConfirm=peerConfirm(retireFirst,rfp).then(()=>({ok:true}),error=>({error}));
    await blocked();await db.exec('commit');
    const refused=await waitingConfirm;check(Boolean(refused.error&&/retired/.test(refused.error.message)),true);
    check(await q('select count(*)::int v from site_order_artifact_private.render_jobs where request_id=$1',[retireFirst.decision]),0);
    const consentFirst=await make(220);await prepare(consentFirst);const cfp=await preview(consentFirst);
    await db.exec('begin');await confirm(consentFirst,cfp);
    const waitingRetire=peerRetire(consentFirst).then(r=>r.rows[0].v);
    await blocked();await db.exec('commit');
    const preserved=await waitingRetire;check(preserved.operation_state,'advanced');check(preserved.retired,false);
    check(await q('select count(*)::int v from site_order_outgoing_private.prepare_retirements where request_id=$1',[consentFirst.request]),0);
    check(await q('select count(*)::int v from site_order_artifact_private.render_jobs where request_id=$1',[consentFirst.decision]),1);
    const drifts=[
     [240,"update private.master_feature_settings set enabled=false where feature_key='site_order_documents'","update private.master_feature_settings set enabled=true where feature_key='site_order_documents'",/master_feature_disabled/],
     [260,"update public.company_members set role='worker' where user_id='"+UA+"'","update public.company_members set role='manager' where user_id='"+UA+"'",/management_required/],
     [280,"update public.companies set fax='changed-source' where id='"+A+"'","update public.companies set fax='03-2' where id='"+A+"'",/source_changed/],
     [340,"update public.companies set company_seal_style='aoyagi_reisho' where id='"+A+"'","update public.companies set company_seal_style='legacy' where id='"+A+"'",/source_changed/],
    ];
    for(const [n,change,restore,pattern]of drifts){
     const drift=await make(n);await prepare(drift);const dp=await preview(drift);
     await db.exec('begin');await db.exec(change);
     const pending=peerConfirm(drift,dp).then(()=>({ok:true}),error=>({error}));
     await blocked();await db.exec('commit');const refused=await pending;
     check(Boolean(refused.error&&pattern.test(refused.error.message)),true);
     check(await q('select count(*)::int v from trade_document_consent_private.receipts where request_id=$1',[drift.decision]),0);
     check(await q('select count(*)::int v from site_order_artifact_private.render_jobs where request_id=$1',[drift.decision]),0);
     check(await q('select count(*)::int v from site_order_outgoing_private.decision_receipts where request_id=$1',[drift.decision]),0);
     await db.exec(restore);
    }
    check(nativeWaits,6);
   }finally{await db.exec('rollback');await peer.end();}
  }
  check(await catalog(),before);
  console.log(JSON.stringify({consent_source_only:true,native_real_waits:nativeWaits,exact_eight_c_unchanged:true,actual_public_uid_jwt_bodies:2,consent_and_job_atomic:true,original_registered:false,sent:false,production_changed:false}));
 }finally{
  if(previousFeature===undefined)await db.query("delete from private.master_feature_settings where feature_key='site_order_documents'");else await db.query("update private.master_feature_settings set enabled=$1 where feature_key='site_order_documents'",[previousFeature]);
  await db.query("select set_config('request.jwt.claims',$1,false),set_config('request.jwt.claim.sub',$2,false),set_config('request.jwt.claim',$3,false)",[saved.claims??'',saved.sub??'',saved.claim??'']);
 }
}
