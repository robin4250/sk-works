// Optional disposable GoTrue/PostgREST proof. No hosted endpoints or Auth mocks.
import assert from 'node:assert/strict';
import {randomUUID,randomBytes} from 'node:crypto';

export async function verifyCanonicalCommonPayrollAuth({db,fixture,read,rpc,request,users,tokens,apiUrl,setPhase}) {
 const api=new URL(apiUrl);
 assert.ok(process.env.CI&&['127.0.0.1','localhost','[::1]'].includes(api.hostname)&&api.protocol==='http:'&&api.port==='53961','owned isolated stack required');
 const cid='10000000-0000-0000-0000-000000000001',otherCid='10000000-0000-0000-0000-000000000002',wid='40000000-0000-0000-0000-000000000001';
 const originalIds=Object.values(users).map(user=>user.id);
 const originalAuth=async()=>(await db.query(`select jsonb_build_object(
  'users',(select jsonb_agg(to_jsonb(u) order by u.id) from auth.users u where u.id=any($1::uuid[])),
  'identities',(select jsonb_agg(to_jsonb(i) order by i.id) from auth.identities i where i.user_id=any($1::uuid[])),
  'sessions',(select jsonb_agg(to_jsonb(s) order by s.id) from auth.sessions s where s.user_id=any($1::uuid[])),
  'functions',(select jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'definition_md5',md5(pg_get_functiondef(p.oid))) order by p.oid::regprocedure::text) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='auth' and p.proname in ('uid','jwt','role'))
 ) v`,[originalIds])).rows[0].v;
 const authBefore=await originalAuth();
 const predicateInventory=async()=>(await db.query(`select p.oid::regprocedure::text signature,md5(p.prosrc) body_md5,to_jsonb(p)-'prosrc' attributes
  from pg_proc p where p.oid=any($1::regprocedure[]) order by p.oid::regprocedure::text`,[
  ['private.has_company_feature(uuid,text)','private.payroll_approver_ids(uuid)','private.payroll_allowed(uuid,text)','private.payroll_settings_allowed(uuid,uuid,text)','private.account_access_allowed()']])).rows;
 const predicatesBefore=await predicateInventory();
 const jsonRpc=async(name,body,token)=>{const response=await rpc(name,body,token);assert.equal(response.status,200,'canonical local RPC '+name);return response.json();};
 const business=async()=>(await db.query(`select jsonb_build_object(
  'salary',(select coalesce(jsonb_agg(to_jsonb(s) order by s.id),'[]') from public.payroll_statements s),
  'audit',(select coalesce(jsonb_agg(to_jsonb(a) order by to_jsonb(a)::text),'[]') from public.payroll_audit a),
  'attendance',(select coalesce(jsonb_agg(to_jsonb(a) order by a.id),'[]') from public.attendance_entries a),
  'settings',(select coalesce(jsonb_agg(to_jsonb(s) order by s.company_id,s.worker_id),'[]') from public.worker_payroll_settings s),
  'rates',(select coalesce(jsonb_agg(to_jsonb(r) order by r.company_id),'[]') from public.company_rate_settings r),
  'activation',(select coalesce(jsonb_agg(to_jsonb(a) order by a.company_id),'[]') from company_common_allowance_private.payroll_activation a),
  'activation_modes',(select coalesce(jsonb_agg(to_jsonb(a) order by a.company_id),'[]') from company_common_allowance_private.payroll_activation_modes a),
  'type_activation',(select coalesce(jsonb_agg(to_jsonb(a) order by to_jsonb(a)::text),'[]') from company_common_allowance_private.payroll_type_activation a),
  'type_activation_events',(select coalesce(jsonb_agg(to_jsonb(a) order by to_jsonb(a)::text),'[]') from company_common_allowance_private.payroll_type_activation_events a),
  'publications',(select coalesce(jsonb_agg(to_jsonb(p) order by p.company_id,p.version),'[]') from company_common_allowance_private.payroll_publications p),
  'receipts',(select coalesce(jsonb_agg(to_jsonb(r) order by r.company_id,r.request_id),'[]') from company_common_allowance_private.payroll_publication_receipts r)
 ) v`)).rows[0].v;
 async function rejected(name,body,token,code='42501') {
  const before=await business(),response=await rpc(name,body,token);
  assert.notEqual(response.status,200,'canonical RPC must reject '+name);
  if(token)assert.equal((await response.json()).code,code);else assert.ok([401,403].includes(response.status));
  assert.deepEqual(await business(),before,'refused request changes no business row');
 }
 async function install(label,sql,execute=value=>db.query(value)) {
  setPhase('install-'+label);
  try {await execute(sql);} catch(error) {
   await db.query('rollback').catch(()=>{});
   const safeMessages=new Set(['legacy allowance source baseline drift','attendance allowance unit source baseline drift','payroll common bridge prerequisite differs','payroll common read prerequisite differs','canonical payroll resolver prerequisite differs','canonical publisher prerequisite differs']);
   if(safeMessages.has(error.message))console.error('CANONICAL_PREREQUISITE '+error.message);
   const metadata=(await db.query(`select n.nspname||'.'||p.proname function_name,md5(p.prosrc) source_md5,pg_get_userbyid(p.proowner) owner
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='company_allowance_identity_private'
     or (n.nspname='payroll_unit_private' and p.proname in ('augment_settings','read_conditions','resolve_company_common','common_state'))
     or (n.nspname='public' and p.proname='my_attendance_allowance_units')
    order by n.nspname,p.proname`)).rows;
   console.error('CANONICAL_PREREQUISITE_FUNCTIONS '+JSON.stringify(metadata));
   throw error;
  }
 }

 setPhase('common-baseline');
 await db.query('reset role');
 await db.query("select set_config('request.jwt.claim.sub','',false),set_config('request.jwt.claims','{}',false)");
 assert.equal((await db.query("select to_regnamespace('company_common_allowance_private') v")).rows[0].v,null,'fresh common fixture only');
 await db.query('alter table public.companies add column if not exists default_welfare_rate numeric default 0,add column if not exists tax_rate numeric default 10,add column if not exists updated_at timestamptz');
 const source=await read('supabase/tests/company_allowance_identity_access_fixture.sql');
 const start=source.indexOf('create table public.company_rate_settings('),end=source.indexOf('create table public.payroll_statements');
 assert.ok(start>=0&&end>start,'known application-only common prerequisite');
 const tables=source.slice(start,end);
 assert.ok(!/\bauth\./i.test(tables),'no Auth table or function replacement');
 await db.query(tables);
 await db.query('insert into public.company_rate_settings(company_id) select id from public.companies');
 await db.query('alter table public.worker_payroll_settings add column if not exists allowance_name_2 text,add column if not exists allowance_2 numeric default 0,add column if not exists allowance_name_3 text,add column if not exists allowance_3 numeric default 0');
 for(const name of ['20260922020000_add_company_rate_settings_management.sql','20261003002700_add_attendance_allowance_display_units.sql','20261008043823_atomic_company_rate_and_allowance_units_save.sql','20261009201229_company_allowance_identity_lifecycle.sql'])await install(name,await read('supabase/migrations/'+name),value=>fixture.exec(value));
 setPhase('reviewed-legacy-unit-acl');
 // Supabase's real public-schema default privileges may explicitly grant anon
 // EXECUTE even though the old migration revokes PUBLIC. The candidate correctly
 // rejects that broader fixture baseline. Restrict only this fixture function;
 // preserve its reviewed body/owner/config and authenticated/service-role grants.
 const unitBefore=(await db.query("select md5(p.prosrc) source_md5,pg_get_userbyid(p.proowner) owner,p.prosecdef,p.proconfig,has_function_privilege('authenticated',p.oid,'EXECUTE') authenticated_execute,has_function_privilege('service_role',p.oid,'EXECUTE') service_execute from pg_proc p where p.oid='public.my_attendance_allowance_units()'::regprocedure")).rows[0];
 assert.deepEqual(unitBefore,{source_md5:'17310735021c3a953a093ed196261468',owner:'postgres',prosecdef:true,proconfig:['search_path=public, pg_temp'],authenticated_execute:true,service_execute:unitBefore.service_execute},'exact old unit baseline before restrictive fixture ACL');
 await db.query('revoke execute on function public.my_attendance_allowance_units() from anon');
 const unitAfter=(await db.query("select md5(p.prosrc) source_md5,pg_get_userbyid(p.proowner) owner,p.prosecdef,p.proconfig,has_function_privilege('authenticated',p.oid,'EXECUTE') authenticated_execute,has_function_privilege('service_role',p.oid,'EXECUTE') service_execute from pg_proc p where p.oid='public.my_attendance_allowance_units()'::regprocedure")).rows[0];
 assert.deepEqual(unitAfter,unitBefore,'restrictive fixture ACL preserves body owner configuration and existing trusted execution');
 assert.equal((await db.query("select has_function_privilege('anon','public.my_attendance_allowance_units()','EXECUTE') allowed")).rows[0].allowed,false);
 console.log('PASS isolated legacy-unit fixture removes only inherited anon execution; source guard, reviewed body and authenticated/trusted execution remain unchanged');
 for(const file of ['tool/staged_company_common_allowances.sql.review-only','docs/candidates/company_common_payroll_bridge_20261020.sql.review-only','docs/candidates/company_common_payroll_effective_20261020.sql.review-only'])await install(file.split('/').at(-1),await read(file));
 const strip=sql=>sql.replace(/^begin;$/m,'').replace(/commit;\s*$/,'');
 await install('canonical-atomic-bundle','begin;\n'+(await Promise.all(['snapshot','resolver','publisher'].map(async unit=>strip(await read('docs/candidates/company_common_canonical_'+unit+'_20261022.sql.review-only'))))).join('\n')+'\ncommit;');
 assert.deepEqual(await predicateInventory(),predicatesBefore,'five real access predicate definitions and permissions preserved');
 assert.deepEqual(await originalAuth(),authBefore,'application installation preserves original GoTrue users identities sessions and functions');
 assert.equal((await db.query('select count(*)::int n from company_common_allowance_private.payroll_activation_modes')).rows[0].n,0);
 assert.equal((await db.query('select count(*)::int n from company_common_allowance_private.payroll_type_activation')).rows[0].n,0);
 assert.equal((await db.query('select count(*)::int n from company_common_allowance_private.payroll_publications')).rows[0].n,0);
 setPhase('schema-cache');await db.query("notify pgrst,'reload schema'");
 for(let attempt=0;;attempt++) {
  const response=await rpc('company_common_payroll_publication_v2_contract_version',{},tokens.owner);
  if(response.status===200){assert.equal(await response.json(),3);break;}
  const error=await response.json();if(error.code!=='PGRST202'||attempt>=30)throw Error('canonical local schema cache unavailable');
  await new Promise(resolve=>setTimeout(resolve,250));
 }
 setPhase('real-admin-adoption');
 // Fixture application data only; never creates or updates any Auth row directly.
 await db.query("update public.company_rate_settings set allowance_1_name='Canonical travel',allowance_1_amount_yen=1200,allowance_2_name='Canonical work',allowance_2_amount_yen=800 where company_id=$1",[cid]);
 let state=await jsonRpc('read_company_common_allowances_admin',{p_company_id:cid},tokens.owner);
 state=await jsonRpc('save_company_common_allowances',{
  p_company_id:cid,p_payroll_type:'daily',p_expected_version:state.version,p_expected_source:state.expected_source,p_request_id:randomUUID(),p_items:[],
  p_legacy_slots:state.legacy_refs.map(({slot,id,generation,name,source_unit,amount_yen})=>({slot,id,generation,name,source_unit,amount_yen})),p_confirm_adoption:true
 },tokens.owner);
 const month=(await db.query("select date_trunc('month',current_timestamp at time zone 'Asia/Tokyo')::date::text v")).rows[0].v;
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[users.owner.id]);
 await db.query("insert into public.attendance_entries(id,company_id,worker_id,site_id,work_date,work_category,base_man_days,allowance_names) values(gen_random_uuid(),$1,$2,'20000000-0000-0000-0000-000000000001',$3,'day',1,array['Canonical travel'])",[cid,wid,month]);
 await db.query("select set_config('request.jwt.claim.sub','',false)");
 const timeline=await jsonRpc('read_company_common_payroll_publications',{p_company_id:cid},tokens.owner);
 const quantities=state.legacy_refs.filter(item=>item.name&&Number(item.amount_yen)>0).map(item=>({id:item.id,generation:item.generation,source_unit:item.source_unit,basis:'attendance_selected_distinct_dates',aliases:[item.name]}));
 const base={p_company_id:cid,p_payroll_type:'daily',p_starts_on:month,p_common_version:state.version,p_common_source:state.expected_source,p_timeline_version:timeline.timeline_version,p_legacy_quantities:quantities,p_individual_reconciliation:'inherit_absent_or_same_rate_otherwise_unresolved'};
 const previewName='preview_company_common_payroll_v2',publishName='publish_company_common_payroll_v2',receiptName='read_company_common_payroll_publish_receipt_v2';
 setPhase('real-owner-preview');const previewBefore=await business();
 const preview=await jsonRpc(previewName,base,tokens.owner);
 assert.equal(preview.contract_version,3);assert.equal(preview.ready,true);assert.equal(preview.activation_required,true);assert.equal(preview.activation_scope,'payroll_type');assert.ok(preview.target_count>=1);
 assert.deepEqual(await business(),previewBefore,'real JWT preview is read only');
 const command={...preview.command_base,p_request_id:randomUUID(),p_preview_token:preview.preview_token,p_approve_activation:true,p_activation_scope:preview.activation_scope};
 const receiptBody={p_company_id:cid,p_request_id:command.p_request_id,p_expected_command:command};
 setPhase('real-role-company-refusals');
 // Existing editor is a member with delegated payroll edit, not a company admin.
 assert.equal((await db.query('select role::text v from public.company_members where company_id=$1 and user_id=$2',[cid,users.editor.id])).rows[0].v,'member');
 for(const role of ['editor','viewer','outsider','manager']) {
  await rejected(previewName,base,tokens[role]);await rejected(publishName,command,tokens[role]);await rejected(receiptName,receiptBody,tokens[role]);
 }
 // The inherited payroll-view session is a company member in the old fixture.
 // Exercise the distinct company viewer role too, then restore that membership.
 const viewerRole=(await db.query('select role::text v from public.company_members where company_id=$1 and user_id=$2',[cid,users.viewer.id])).rows[0].v;
 try {
  await db.query("update public.company_members set role='viewer' where company_id=$1 and user_id=$2",[cid,users.viewer.id]);
  for(const [name,body] of [[previewName,base],[publishName,command],[receiptName,receiptBody]])await rejected(name,body,tokens.viewer);
 } finally {await db.query('update public.company_members set role=$3 where company_id=$1 and user_id=$2',[cid,users.viewer.id,viewerRole]);}
 for(const [name,body] of [[previewName,base],[publishName,command],[receiptName,receiptBody]])await rejected(name,body);
 await rejected(previewName,{...base,p_company_id:otherCid},tokens.owner);
 await rejected(publishName,{...command,p_company_id:otherCid},tokens.owner);
 await rejected(receiptName,{...receiptBody,p_company_id:otherCid},tokens.owner);
 setPhase('live-admin-access-refusals');
 const ownerRole=(await db.query('select role::text v from public.company_members where company_id=$1 and user_id=$2',[cid,users.owner.id])).rows[0].v;
 await db.query("update public.company_members set role='viewer' where company_id=$1 and user_id=$2",[cid,users.owner.id]);
 for(const [name,body] of [[previewName,base],[publishName,command],[receiptName,receiptBody]])await rejected(name,body,tokens.owner);
 await db.query('update public.company_members set role=$3 where company_id=$1 and user_id=$2',[cid,users.owner.id,ownerRole]);
 await db.query('insert into private.account_deletion_access_restrictions values($1)',[users.owner.id]);
 for(const [name,body] of [[previewName,base],[publishName,command],[receiptName,receiptBody]])await rejected(name,body,tokens.owner);
 await db.query('delete from private.account_deletion_access_restrictions where user_id=$1',[users.owner.id]);
 setPhase('real-source-confirmation-refusals');
 await rejected(previewName,{...base,p_common_version:state.version+1},tokens.owner,'40001');
 await rejected(publishName,{...command,p_common_version:state.version+1},tokens.owner,'40001');
 await rejected(publishName,{...command,p_common_source:{}},tokens.owner,'40001');
 await rejected(publishName,{...command,p_timeline_version:timeline.timeline_version+1},tokens.owner,'40001');
 await rejected(publishName,{...command,p_preview_token:'0'.repeat(64)},tokens.owner,'40001');
 await rejected(publishName,{...command,p_activation_scope:'legacy_company'},tokens.owner,'40001');
 setPhase('real-owner-publish');
 await rejected(publishName,{...command,p_approve_activation:false},tokens.owner,'55000');
 const absent=await jsonRpc(receiptName,receiptBody,tokens.owner);assert.equal(absent.found,false);
 const counts=async()=>(await db.query('select (select count(*)::int from company_common_allowance_private.payroll_publications where company_id=$1) publications,(select count(*)::int from company_common_allowance_private.payroll_publication_receipts where company_id=$1) receipts',[cid])).rows[0];
 const beforeConcurrentPublish=await counts();
 const [result,concurrentReplay]=await Promise.all([jsonRpc(publishName,command,tokens.owner),jsonRpc(publishName,command,tokens.owner)]);
 assert.deepEqual(concurrentReplay,result,'concurrent identical real-JWT commands return the same immutable receipt');
 assert.deepEqual(await counts(),{publications:beforeConcurrentPublish.publications+1,receipts:beforeConcurrentPublish.receipts+1},'concurrent identical commands create only one publication and one receipt');
 assert.equal(result.contract_version,3);assert.equal(result.activation_changed,true);assert.equal(result.activation_scope,'payroll_type');assert.equal(result.publication_version,1);
 const publication=(await db.query('select actor_id,request_id from company_common_allowance_private.payroll_publications where company_id=$1 and version=1',[cid])).rows[0];
 assert.equal(publication.actor_id,users.owner.id);assert.equal(publication.request_id,command.p_request_id);
 const afterPublish=await business();
 assert.deepEqual(await jsonRpc(publishName,command,tokens.owner),result,'same real actor and exact command uses receipt before stale timeline CAS');
 const found=await jsonRpc(receiptName,receiptBody,tokens.owner);assert.equal(found.found,true);assert.deepEqual(found.result,result);
 assert.deepEqual(await business(),afterPublish,'receipt lookup and exact replay never duplicate payroll or publication rows');
 await rejected(publishName,{...command,p_approve_activation:false},tokens.owner,'22023');
 await rejected(receiptName,{...receiptBody,p_expected_command:{...command,p_approve_activation:false}},tokens.owner);
 setPhase('owned-extra-actor');
 const password='canonical-fixture-'+randomBytes(20).toString('hex')+'!A1';
 const created=await request('/auth/v1/admin/users',{service:true,body:{email:'canonical-extra-'+randomUUID()+'@example.invalid',password,email_confirm:true}});assert.equal(created.status,200);
 const extra=await created.json();assert.ok(!originalIds.includes(extra.id));
 const login=await request('/auth/v1/token?grant_type=password',{body:{email:extra.email,password}});assert.equal(login.status,200);
 const session=await login.json(),claims=JSON.parse(Buffer.from(session.access_token.split('.')[1],'base64url').toString('utf8'));
 assert.equal(claims.sub,extra.id);assert.ok(claims.session_id);
 await db.query("insert into public.company_members values($1,$2,'admin')",[cid,extra.id]);
 await rejected(publishName,command,session.access_token,'22023');await rejected(receiptName,receiptBody,session.access_token);
 // Only this newly created actor's session is logged out. Original tokens remain live.
 const currentBase={...base,p_timeline_version:result.timeline.timeline_version};
 assert.equal((await jsonRpc(previewName,currentBase,session.access_token)).contract_version,3);
 const logout=await request('/auth/v1/logout?scope=local',{token:session.access_token});assert.ok([200,204].includes(logout.status));
 assert.equal((await db.query('select count(*)::int n from auth.sessions where id=$1 and user_id=$2',[claims.session_id,extra.id])).rows[0].n,0);
 await rejected(previewName,currentBase,session.access_token);await rejected(publishName,command,session.access_token);await rejected(receiptName,receiptBody,session.access_token);
 setPhase('original-auth-preserved');
 assert.equal((await jsonRpc(previewName,currentBase,tokens.owner)).contract_version,3,'original owner session remains usable');
 assert.deepEqual(await originalAuth(),authBefore,'original GoTrue users identities sessions and Auth functions remain unchanged');
 assert.deepEqual(await predicateInventory(),predicatesBefore,'real access predicate source and permissions remain unchanged');
 setPhase('concurrent-different-requests');
 const racePreview=await jsonRpc(previewName,currentBase,tokens.owner);
 assert.equal(racePreview.ready,true);
 const raceCommands=Array.from({length:2},()=>({...racePreview.command_base,p_request_id:randomUUID(),p_preview_token:racePreview.preview_token,p_approve_activation:true,p_activation_scope:racePreview.activation_scope}));
 const beforeRace=await counts();
 const raced=await Promise.all(raceCommands.map(async candidate=>{
  const response=await rpc(publishName,candidate,tokens.owner);
  return {status:response.status,body:await response.json(),command:candidate};
 }));
 const winners=raced.filter(item=>item.status===200),refused=raced.filter(item=>item.status!==200);
 assert.equal(winners.length,1,'only one distinct request may commit the same approved timeline');
 assert.equal(refused.length,1);assert.equal(refused[0].body.code,'40001','losing distinct request refuses changed source/timeline');
 assert.deepEqual(await counts(),{publications:beforeRace.publications+1,receipts:beforeRace.receipts+1},'distinct real-JWT race creates only one publication and receipt');
 assert.deepEqual(await jsonRpc(publishName,winners[0].command,tokens.owner),winners[0].body,'winning race request remains replayable');
 const losingReceipt=await jsonRpc(receiptName,{p_company_id:cid,p_request_id:refused[0].command.p_request_id,p_expected_command:refused[0].command},tokens.owner);
 assert.equal(losingReceipt.found,false,'losing request has no phantom committed receipt');
 assert.deepEqual(await jsonRpc(publishName,command,tokens.owner),result,'earlier receipt remains replayable after concurrent later publication');
 assert.deepEqual(await originalAuth(),authBefore,'concurrent HTTP requests preserve original Auth rows and functions');
 assert.deepEqual(await predicateInventory(),predicatesBefore,'concurrent HTTP requests preserve authorization predicates');
 console.log('PASS real isolated GoTrue JWT -> canonical contract 3 preview/publish/receipt; one canonical publication records the real actor; same request replays without mutation');
 console.log('PASS member-payroll-editor/viewer/other-company/manager/anonymous, live admin removal, restricted actor, mismatched command/admin and own logged-out extra session refused with unchanged business state');
 console.log('PASS original Auth functions/users/identities/sessions/tokens preserved; only an additional synthetic actor was created and its own session logged out');
 console.log('PASS concurrent real-JWT HTTP publishes: identical command returns one receipt twice; distinct request IDs sharing one preview yield one commit and one 40001 without duplicate publication');
 console.log('LIMIT canonical Auth hook: disposable application schema and real local Auth sessions; no production JWT/config/RLS, public attendance proxy, mixed attendance/settings/finalization writer races, OAuth or iPhone proof');
}
