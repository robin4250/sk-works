import fs from 'node:fs/promises';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';

export async function verifyOutgoingObservation(db,{id,A,B,UA,UB,actor,q,openNativePeer}) {
 let checks=0,waits=0;
 const check=(a,b)=>{assert.deepEqual(a,b);checks++;};
 const deny=async(fn,p)=>{let error;try{await fn();}catch(e){error=e;}if(!error||!p.test(error.message))throw Error('expected '+p+' got '+error?.message);checks++;};
 const signed=async uid=>{await actor(uid);const sid=await q('select id v from auth.sessions where user_id=$1 order by id limit 1',[uid]);
  await db.query("select set_config('test.jwt',$1,false)",[JSON.stringify({sub:uid,role:'authenticated',session_id:sid})]);return sid;};
 // Exact existing public-candidate helper body, not a permissive replacement.
 const profile=await fs.readFile('docs/candidates/partner_company_profile_20261020.sql.review-only','utf8');
 const declaration=profile.match(/create function private\.partner_company_profile_value\([\s\S]*?as \$\$([\s\S]*?)\$\$;/);
 if(!declaration||createHash('md5').update(declaration[1]).digest('hex')!=='06ce79748602c8ca5aebda226bc7f742')throw Error('profile source changed');
 await db.exec(`alter table public.companies add column if not exists address text,
  add column if not exists phone text,add column if not exists fax text,
  add column if not exists email text,add column if not exists corporate_number text;
  alter table public.trade_companies add column if not exists name text,add column if not exists address text,
  add column if not exists representative_name text,add column if not exists phone text,
  add column if not exists corporate_number text;`);
 const present=await q("select to_regprocedure('private.partner_company_profile_value(uuid)') is not null v");
 if(!present){
  if(!await q("select to_regclass('private.partner_company_profile_extensions') is not null v")){
   const table=profile.slice(profile.indexOf('create table private.partner_company_profile_extensions'),profile.indexOf('create table private.partner_company_profile_audit'));
   await db.exec(table);
  }
  // The old surrounding fixture held only two extension fields. Add the actual
  // captured nonfinancial column types without dropping its retained rows.
  await db.exec(`alter table private.partner_company_profile_extensions
   add column if not exists version bigint not null default 1,
   add column if not exists updated_by uuid not null default '${UA}',
   add column if not exists updated_at timestamptz not null default clock_timestamp();
   alter table private.partner_company_profile_extensions enable row level security;
   revoke all on private.partner_company_profile_extensions from public,anon,authenticated,service_role;`);
  await db.exec(declaration[0]);
  await db.exec('revoke all on function private.partner_company_profile_value(uuid) from public,anon,authenticated,service_role');
 }
 check(await q("select md5(prosrc) v from pg_proc where oid='private.partner_company_profile_value(uuid)'::regprocedure"),'06ce79748602c8ca5aebda226bc7f742');
 // The protected legacy harness installs the exact C body but owner-only ACL.
 // Match the real canonical C invoker-wrapper contract only after old guards run.
 await db.exec('grant execute on function private.require_standalone_trade_document_access() to authenticated');
 await signed(UA);
 await db.query("update public.companies set address='登録自社住所',phone='03-0000-0000',fax='03-0000-0001',email='must-not-leak@example.invalid',corporate_number='1234567890123' where id=$1",[A]);
 await db.query(`insert into private.partner_company_profile_extensions(company_id,representative_name,updated_by)
  values($1,'合成代表者',$2) on conflict(company_id) do update set representative_name=excluded.representative_name`,[A,UA]);
 const site=id(9301),trade=id(2100);
 await db.query("update trade_companies t set name=c.name,address='登録相手住所',representative_name='相手代表者',phone='03-0000-0002',corporate_number='9876543210123' from companies c where t.id=$1 and c.id=t.linked_company_id",[trade]);
 const sql=await fs.readFile('docs/review/site-order-outgoing/source-and-prepare-observation.sql.review-only','utf8');
 const functions=()=>q(`select jsonb_agg(to_jsonb(p) order by p.oid) v from pg_proc p
  where p.pronamespace in('site_order_package_private'::regnamespace,'site_order_manager_private'::regnamespace,'trade_document_consent_private'::regnamespace)
   and p.proname not in('outgoing_context','observe_prepare')`);
 const beforeFunctions=await functions();
 await db.exec("do $$ begin if not exists(select 1 from pg_roles where rolname='outgoing_observation_untrusted') then create role outgoing_observation_untrusted;end if;end $$");
 for(const [change,pattern] of [
  ['grant execute on function private.partner_company_profile_value(uuid) to authenticated',/outgoing_observation_dependency_changed/],
  ['revoke execute on function private.require_standalone_trade_document_access() from authenticated',/outgoing_observation_dependency_changed/],
  ['grant execute on function private.require_standalone_trade_document_access() to outgoing_observation_untrusted',/outgoing_observation_dependency_changed/],
  ['alter function private.partner_company_profile_value(uuid) security invoker',/outgoing_observation_dependency_changed/],
  ['grant select on private.partner_company_profile_extensions to authenticated',/outgoing_profile_relation_changed/],
  ['alter default privileges in schema site_order_manager_private grant execute on functions to outgoing_observation_untrusted',/outgoing_observation_seal_changed/],
 ]) {
  await db.exec('begin');
  try{await db.exec(change);await deny(()=>db.exec(sql),pattern);}finally{await db.exec('rollback');}
  check(await q("select to_regprocedure('site_order_manager_private.outgoing_context(uuid,uuid)') is null v"),true);
  check(await functions(),beforeFunctions);
 }
 await db.exec(sql);check(await functions(),beforeFunctions);
 const context=()=>q('select site_order_manager_private.outgoing_context($1,$2) v',[site,trade]);
 const snapshot=()=>q(`select jsonb_build_object('scopes',(select count(*) from site_order_manager_private.document_scopes),
  'documents',(select count(*) from trade_document_consent_private.documents),
  'revisions',(select count(*) from trade_document_consent_private.revisions),
  'consents',(select count(*) from trade_document_consent_private.consents),
  'events',(select count(*) from trade_document_consent_private.events),
  'receipts',(select count(*) from trade_document_consent_private.receipts),
  'jobs',(select count(*) from site_order_artifact_private.render_jobs)) v`);
 const before=await snapshot(),source=await context();check(await snapshot(),before);
 check(source.issuer.representative_name,'合成代表者');check(source.issuer.fax,'03-0000-0001');
 check(Object.keys(source.issuer).sort(),['name','address','representative_name','corporate_number','phone','fax'].sort());
 check(Object.keys(source.counterparty).sort(),['name','address','representative_name','corporate_number','phone'].sort());
 check(JSON.stringify(source).includes('must-not-leak'),false);check(source.can_send,false);check(source.records_consent,false);
 check(JSON.stringify(source).includes('99999'),false);
 check(Object.keys(source.site).sort(),['name','address','period_start','period_end'].sort());
 const observe=(doc,local,connection=db)=>connection.query('select site_order_manager_private.observe_prepare($1,$2,$3,$4) v',[site,doc,local,trade]).then(r=>r.rows[0].v);
 const sample=JSON.parse(await fs.readFile('tool/canonical_renderer/synthetic-evidence.json','utf8')).body;
 const prepare=async(doc,local)=>{
  const current=await context(),body={...sample,transaction_id:doc,issuer_company_id:A,counterparty_company_id:B,
   issuer:current.issuer,counterparty:current.counterparty};
  await db.query("select site_order_manager_private.prepare_site_document($1,$2,$3,'order',$4,0,$5::jsonb)",[site,doc,trade,current.connection_fingerprint,JSON.stringify(body)]);
  await db.query('select site_order_manager_private.bind_local($1,$2,$3)',[doc,A,local]);
  return body;
 };
 const doc=id(194000),local=id(194001),initial=await snapshot();
 const unknown=await observe(doc,local);check(unknown.operation_state,'not_observed');
 check(unknown.journal_clearable,false);check(unknown.may_prepare_again,false);check(unknown.can_send,false);check(await snapshot(),initial);
 // A delayed original prepare remains possible after the earlier read: no
 // permanent cancellation, automatic retry, or journal clear is implied.
 const body=await prepare(doc,local),preparedBefore=await snapshot();
 const observed=await observe(doc,local);check(observed.operation_state,'prepared_review_required');
 check(observed.body,body);check(observed.may_request_fresh_preview,true);check(observed.reuses_previous_consent,false);
 check(observed.journal_clearable,false);check(observed.may_prepare_again,false);check(await snapshot(),preparedBefore);
 check(observed.body_hash,await q('select body_hash v from trade_document_consent_private.revisions where document_id=$1 and revision=1',[doc]));
 await db.query("update private.partner_company_profile_extensions set representative_name='変更代表者' where company_id=$1",[A]);
 check((await observe(doc,local)).operation_state,'changed');
 await db.query("update private.partner_company_profile_extensions set representative_name='合成代表者' where company_id=$1",[A]);
 check((await observe(doc,id(194002))).operation_state,'not_a_pending_prepare');
 const own=await q('select site_order_manager_private.preview_own($1,1,$2) v',[doc,A]);
 await db.query("select site_order_manager_private.decide($1,1,$2,$3,$4,'approve',$5,true,$6)",[doc,A,own.epoch,own.body_hash,own.own_seal.seal_hash,id(194003)]);
 const approved=await observe(doc,local);check(approved.operation_state,'not_a_pending_prepare');check(Object.hasOwn(approved,'body'),false);
 await signed(UB);await deny(()=>observe(doc,local),/registered_direction|unavailable/);await signed(UA);
 await db.query("update private.master_feature_settings set enabled=false where feature_key='site_order_documents'");
 await deny(context,/master_feature_disabled/);await deny(()=>observe(doc,local),/master_feature_disabled/);
 await db.query("update private.master_feature_settings set enabled=true where feature_key='site_order_documents'");
 await db.query("update company_members set role='worker' where user_id=$1",[UA]);
 await deny(context,/management_required/);await deny(()=>observe(doc,local),/management_required/);
 await db.query("update company_members set role='manager' where user_id=$1",[UA]);
 for(const role of ['authenticated','anon','service_role']){
  await db.exec('set role '+role);await deny(context,/permission denied/);await deny(()=>observe(doc,local),/permission denied/);await db.exec('reset role');
 }
 if(openNativePeer){
  const peer=await openNativePeer();
  try{
   const sid=await signed(UA);
   await peer.query("select set_config('test.uid',$1,false),set_config('test.jwt',$2,false)",[UA,JSON.stringify({sub:UA,role:'authenticated',session_id:sid})]);
   const pendingDoc=id(194010),pendingLocal=id(194011);
   await db.exec('begin');
   try{
    await prepare(pendingDoc,pendingLocal);
    const pid=await q('select pg_backend_pid() v');
    const pending=observe(pendingDoc,pendingLocal,peer).then(value=>({value}),error=>({error}));
    let waited=false;
    for(let n=0;n<200&&!waited;n++){
     waited=await q("select exists(select 1 from pg_stat_activity where pid=$1 and wait_event_type='Lock' and $2=any(pg_blocking_pids(pid))) v",[peer.processID,pid]);
     if(!waited)await new Promise(r=>setTimeout(r,5));
    }
    check(waited,true);waits++;
    await db.exec('commit');const result=await pending;
    check(result.error,undefined);check(result.value.operation_state,'prepared_review_required');
   }finally{await db.exec('rollback');}
  }finally{await peer.end();}
 }
 check(await functions(),beforeFunctions);
 console.log(JSON.stringify({outgoing_observation_checks:checks,native_observed_waits:waits,
  current_profile_body_md5:'06ce79748602c8ca5aebda226bc7f742',synthetic_auth:true,production_applied:false}));
}
