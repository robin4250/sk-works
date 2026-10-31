// Disposable table-parity fixture only. Never a production installer.
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const root=path.resolve(new URL('../../',import.meta.url).pathname);
const read=name=>fs.readFile(path.join(root,name),'utf8');
const hash=s=>createHash('sha256').update(s).digest('hex');
const canonical=value=>Array.isArray(value)?value.map(canonical):value&&typeof value==='object'?Object.fromEntries(Object.keys(value).sort().map(k=>[k,canonical(value[k])])):value;
function tableComparable(raw){
 const value=structuredClone(raw),owned=(value.triggers??[]).filter(t=>t.constraint==='site_order_package_private.packages_data_item_id_fkey');
 assert.equal(owned.length,2,'exact two canonical package reference triggers');
 assert.deepEqual(owned.sort((a,b)=>a.attrs.tgtype-b.attrs.tgtype),[{"name": "internal:site_order_package_private.packages_data_item_id_fkey:9", "attrs": {"tgargs": "\\x", "tgattr": [], "tgtype": 9, "tgnargs": 0, "tgenabled": "O", "tgnewtable": null, "tgoldtable": null, "tgdeferrable": false, "tgisinternal": true, "tginitdeferred": false}, "function": "\"RI_FKey_noaction_del\"()", "constraint": "site_order_package_private.packages_data_item_id_fkey", "constraint_relation": "site_order_package_private.packages", "constraint_index": "private.company_data_delivery_items_pkey", "definition": null, "qualification": null}, {"name": "internal:site_order_package_private.packages_data_item_id_fkey:17", "attrs": {"tgargs": "\\x", "tgattr": [], "tgtype": 17, "tgnargs": 0, "tgenabled": "O", "tgnewtable": null, "tgoldtable": null, "tgdeferrable": false, "tgisinternal": true, "tginitdeferred": false}, "function": "\"RI_FKey_noaction_upd\"()", "constraint": "site_order_package_private.packages_data_item_id_fkey", "constraint_relation": "site_order_package_private.packages", "constraint_index": "private.company_data_delivery_items_pkey", "definition": null, "qualification": null}]);
 value.triggers=(value.triggers??[]).filter(t=>!owned.includes(t)).sort((a,b)=>JSON.stringify(canonical(a)).localeCompare(JSON.stringify(canonical(b))));
 if(process.argv[3]!=='postgres'){
  const timestamp=value.columns.find(c=>c.attname==='created_at'&&c.attnum>0);
  assert.equal(timestamp.type,'timestamp with time zone');assert.equal(timestamp.attlen,8);assert.equal(timestamp.attbyval,false);
  timestamp.attbyval=true; // comparison projection only; raw catalog retained below.
 }
 return value;
}
function expectedComparable(raw){const value=structuredClone(raw);value.triggers=(value.triggers??[]).sort((a,b)=>JSON.stringify(canonical(a)).localeCompare(JSON.stringify(canonical(b))));return value;}
export async function installCombinedFixture(db,{q,check}){
 const migration=await read('supabase/migrations/20260930054000_add_structured_company_qualification_exchange.sql');
 assert.equal(hash(migration),'1d7fe33b6f527a552a60c6ba0ce08a45cfd456f0e8374297aa37ae3f1a539bf3');
 const prefix=migration.slice(0,migration.indexOf('CREATE OR REPLACE FUNCTION private.company_document_exchange'));
 assert.equal(hash(prefix),'9e084bce04ac89a953e7bd6bd59f82a79db9a722954108012cdda61a5c832c18');
 const inboxMigration=await read('supabase/migrations/20261002104447_add_site_share_approval_flow.sql');
 assert.equal(hash(inboxMigration),'1d4a29c80894648e9098fc960c213cc1a4ca438d5e2a8a85bb10883ac0e6f052');
 check(await q('select count(*)::int v from private.company_data_delivery_items'),0);
 // Shape the empty surrounding fixture into the captured deployed table. No
 // canonical module, Auth helper, or original fixture source is replaced.
 await db.exec(`alter table private.company_data_delivery_items
 alter column id set default gen_random_uuid(),alter column delivery_id set not null,
 add column source_item_id uuid references private.company_data_delivery_items(id) on delete set null,
 add column created_at timestamptz not null default now(),
 add constraint company_data_delivery_items_payload_kind_check check(payload_kind in ('qualification','personnel')),
 add constraint company_data_delivery_items_payload_check check(jsonb_typeof(payload)='object' and octet_length(payload::text)<=65536),
 add constraint company_data_delivery_items_company_path_check check(jsonb_typeof(company_path)='array');
 alter table private.company_data_delivery_items drop constraint company_data_delivery_items_delivery_id_fkey;
 alter table private.company_data_delivery_items add constraint company_data_delivery_items_delivery_id_fkey foreign key(delivery_id) references private.document_deliveries(id) on delete cascade;
 alter table private.site_share_inbox add column created_at timestamptz not null default now();
 alter table private.site_share_inbox drop constraint site_share_inbox_data_item_id_fkey;
 alter table private.site_share_inbox add constraint site_share_inbox_data_item_id_fkey foreign key(data_item_id) references private.company_data_delivery_items(id) on delete cascade;
 alter table private.company_data_delivery_items alter column created_at type timestamptz using(created_at+interval '0 seconds');`);
 await db.exec(prefix.slice(prefix.indexOf('alter table private.company_data_delivery_items enable')));
 const captured=await read('docs/review/site-order-combined-readiness/target-table-catalog.json');
 assert.equal(hash(captured),'d50df63fc34cf96db243276006fbf13076416c0e6f474720e584d5bc93f648d6');
 const expected=JSON.parse(captured);
 const sql=await fs.readFile(path.join(process.env.SKO_EXACT_EIGHT_SOURCE_ROOT,'docs/review/site-order-private-baseline/existing_catalog_normalized.sql'),'utf8');
 assert.equal(hash(sql),'48c1d865d43763678fdcbed3b697fe1ca8a8d837573e0f9cdd2b2c6003b544b8');
 const output=process.env.SKO_COMBINED_CATALOG_DIRECTORY;
 if(!output||!path.isAbsolute(output))throw Error('new private raw catalog output required');
 await fs.mkdir(output,{mode:0o700});let captureNumber=0;
 const catalog=async()=>{
  const raw=(await q(sql,[['private']])).relations['private.company_data_delivery_items'];
  const compared=tableComparable(raw);
  const artifact={raw,comparison:compared,package_reference_triggers_excluded:2,
   pglite_single_abi_projection:process.argv[3]!=='postgres'?{column:'created_at',type:'timestamp with time zone',attlen:8,field:'attbyval',from:false,to:true,reason:'ABI interpretation is an inference; Native comparison does not project this bit'}:null};
  await fs.writeFile(path.join(output,'table-'+captureNumber++ +'.json'),JSON.stringify(artifact,null,2)+'\n',{flag:'wx',mode:0o600});
  return compared;
 };
 check(await catalog(),expectedComparable(expected.relation));
 const consumerSource=await read('docs/review/site-order-compatibility/pinned-consumers.json');
 assert.equal(hash(consumerSource),'b514d67f2c848c04e94ce84df8671c26f3842b5a67719a980190ed86c2ba45a7');
 const saveMigration=await read('supabase/migrations/20261001214248_add_company_delivery_save_state.sql');
 assert.equal(hash(saveMigration),'69fcaeda74bc8805d3a10d47746ea4f90f48990455d44b2208f8431dce74e8fd');
 await db.exec(saveMigration.slice(0,saveMigration.indexOf('create or replace function private.company_delivery_saved_keys')));
 // The receive-code relation is a synthetic surrounding fixture, not claimed
 // as a full deployed-table parity contract.
 await db.exec(`create table private.document_receive_codes(code uuid primary key,company_id uuid not null references public.companies(id),created_by uuid not null,expires_at timestamptz not null default now()+interval '7 days',used_at timestamptz);alter table private.document_receive_codes enable row level security`);
 let brokenKind;
 await db.exec('begin');
 try{
  const a=await q('select gen_random_uuid()v'),b=await q('select gen_random_uuid()v'),d=await q('select gen_random_uuid()v');
  await db.query('insert into public.companies(id,name)values($1,$2),($3,$4)',[a,'CHECK sender',b,'CHECK recipient']);
  await db.query('insert into private.document_deliveries(id,sender_company_id,recipient_company_id,sender_name,recipient_name,note)values($1,$2,$3,$4,$5,$6)',[d,a,b,'CHECK sender','CHECK recipient','bounded unpatched CHECK reproduction']);
  try{await db.query("insert into private.company_data_delivery_items(delivery_id,payload_kind,payload)values($1,'site_share','{}')",[d]);}catch(error){brokenKind=error;}
 }finally{await db.exec('rollback');}
 assert.equal(brokenKind?.code,'23514');assert.equal(brokenKind.constraint,'company_data_delivery_items_payload_kind_check');check(true,true);
 check(await q('select count(*)::int v from private.company_data_delivery_items'),0);
 const consumers=JSON.parse(consumerSource);
 for(const f of consumers){
  check(await q('select to_regprocedure($1) is null v',[f.signature]),true);
  await db.exec(f.definition);
 }
 await db.exec(`revoke all on function private.company_document_exchange(text,jsonb) from public;
 grant execute on function private.company_document_exchange(text,jsonb) to authenticated;
 revoke all on function private.site_payment_pair(uuid,uuid) from public;
 revoke all on function private.site_payment_agreement_targets(uuid) from public;
 grant execute on function private.site_payment_agreement_targets(uuid) to authenticated;`);
 const proc=()=>q('select jsonb_agg(to_jsonb(p)order by oid)v from pg_proc p');
 const beforeFunctions=await proc(),beforeTable=await catalog();
 const bodies=new Map(consumers.map(f=>[f.signature,null]));
 for(const f of consumers)bodies.set(f.signature,await q('select prosrc v from pg_proc where oid=to_regprocedure($1)',[f.signature]));
 const dataDigest=async()=>{
  const tables=(await db.query(`select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where c.relkind='r' and (n.nspname in ('trade_document_consent_private','trade_document_confirmation_api_private','site_order_artifact_private','site_order_manager_private','site_order_package_private','site_order_outgoing_private')
   or n.nspname||'.'||c.relname=any($1::text[])) order by n.nspname,c.relname`,[['auth.users','auth.sessions','public.companies','public.company_members','public.trade_companies','public.sites','public.app_notifications','private.company_connections','private.master_feature_settings','private.document_deliveries','private.company_data_delivery_items','private.site_share_inbox','private.company_delivery_saved_items','private.document_receive_codes']])).rows;
  const values={};
  for(const t of tables){
   if(!/^[a-z_][a-z_0-9]*$/.test(t.nspname)||!/^[a-z_][a-z_0-9]*$/.test(t.relname))throw Error('fixture catalog identifier rejected');
   values[t.nspname+'.'+t.relname]=await q(`select encode(sha256(convert_to(coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text),'[]')::text,'UTF8')),'hex')v from "${t.nspname}"."${t.relname}" t`);
  }
  return values;
 };
 const beforeRows=await dataDigest();
 const compatibility=await read('docs/review/site-order-compatibility/consumer-boundary.sql.review-only');
 assert.equal(hash(compatibility),'81a4458d6106e3a128badaab8659165b10c37b6d8e63f16f4e95508db398d836');
 check(await q("select coalesce(bool_or(enabled),false)v from private.master_feature_settings where feature_key='site_order_documents'"),false);
 const end='end $compatibility$;';assert.equal(compatibility.split(end).length,2);
 let lateFailure;
 try{await db.exec(compatibility.replace(end,"raise exception 'combined_fixture_late_failure';\n"+end));}catch(error){lateFailure=error;}
 assert.equal(lateFailure?.message,'combined_fixture_late_failure');await db.exec('rollback');
 check(await proc(),beforeFunctions);check(await catalog(),beforeTable);check(await dataDigest(),beforeRows);
 await db.exec(compatibility);
 check(await dataDigest(),beforeRows);
 check(await q("select coalesce(bool_or(enabled),false)v from private.master_feature_settings where feature_key='site_order_documents'"),false);
 const afterFunctions=await proc(),changed=[];
 assert.equal(beforeFunctions.length,afterFunctions.length);
 const normalizedAfter=[];
 for(let i=0;i<beforeFunctions.length;i++){
  const before=beforeFunctions[i],after=afterFunctions[i];
  if(before.prosrc!==after.prosrc){
   const signature=await q('select oid::regprocedure::text v from pg_proc where oid=$1',[after.oid]);
   assert.equal(bodies.has(signature),true);changed.push(signature);
  }
  normalizedAfter.push({...after,prosrc:before.prosrc});
 }
 check(normalizedAfter,beforeFunctions);
 check(changed.sort(),[...bodies.keys()].sort());
 const afterTable=await catalog(),newCheck=afterTable.constraints.find(c=>c.name==='company_data_delivery_items_payload_kind_check');
 assert.ok(newCheck.definition.includes("'site_share'::text"));
 newCheck.definition=beforeTable.constraints.find(c=>c.name===newCheck.name).definition;
 check(afterTable,beforeTable);
 console.log(JSON.stringify({combined_compatibility_installed:true,target_table_comparison_parity:true,native_raw_abi_comparison:process.argv[3]==='postgres',pglite_single_abi_projection:process.argv[3]!=='postgres',legacy_consumers_materialized:6,broad_financial_rpc_bundle_installed:false,only_six_function_bodies_and_named_check_changed:true,late_compat_failure_rolled_back:true,staged_off_is_only_a_design_candidate:true,original_helpers_replaced:false,real_gotrue:false,full_production_schema:false,production_changed:false}));
 return async({UA,UB,A,B,sid,id,claims})=>{
  const beforeSmoke=await dataDigest(),beforeSmokeFunctions=await proc();
  await db.exec('begin');
  try{
   await db.query("update public.company_members set role='admin' where user_id=any($1::uuid[])",[[UA,UB]]);
   await db.query('insert into auth.sessions(id,user_id)values($1,$2)',[id(99000),UB]);
   await db.query("select set_config('request.jwt.claims',$1,true),set_config('request.jwt.claim.sub','',true),set_config('request.jwt.claim','',true)",[claims(UB,id(99000))]);
   const active=await q('select private.require_standalone_trade_document_access()v');check(active.actor_id,UB);check(active.company_id,B);check(active.session_id,id(99000));
   const packet=await q('select jsonb_build_object(\'item\',p.data_item_id,\'delivery\',i.delivery_id)v from site_order_package_private.packages p join private.company_data_delivery_items i on i.id=p.data_item_id where p.sender_company_id=$1 and p.recipient_company_id=$2 order by p.created_at,p.id limit 1',[A,B]);
   assert.ok(packet?.item);
   check(await q("select private.company_document_exchange('data_items',jsonb_build_object('id',$1::uuid))v",[packet.delivery]),[]);
   const expect=async(action,message)=>{
    await db.exec('savepoint expected_negative');let error;
    try{await action();}catch(e){error=e;}finally{await db.exec('rollback to savepoint expected_negative;release savepoint expected_negative');}
    assert.equal(error?.code,'22023');assert.ok(error.message.includes(message));check(true,true);
   };
   await expect(()=>db.query('select private.save_company_delivery_items($1::text[])',[[`data:${packet.item}`]]),'個別の承認画面');
   await expect(()=>db.query('select private.site_payment_pair($1,$2)',[packet.item,B]),'専用の承認経路');
   check(await q('select private.site_share_inbox()v'),[]);
   await db.query('insert into private.document_deliveries(id,sender_company_id,recipient_company_id,sender_name,recipient_name,sent_by,note)values($1,$2,$3,$4,$5,$6,$7)',[id(99010),A,B,'fixture sender','fixture recipient',UA,'old supported data']);
   await db.query("insert into private.company_data_delivery_items(id,delivery_id,payload_kind,payload)values($1,$2,'qualification','{\"name\":\"Q\"}'),($3,$2,'personnel','{\"name\":\"P\"}')",[id(99011),id(99010),id(99012)]);
   const legacy=await q("select private.company_document_exchange('data_items',jsonb_build_object('id',$1::uuid))v",[id(99010)]);check(legacy.length,2);
   await db.query('select private.save_company_delivery_items($1::text[])',[[`data:${id(99011)}`,`data:${id(99012)}`]]);
   check(await q('select count(*)::int v from private.company_delivery_saved_items where company_id=$1',[B]),2);
   await expect(()=>db.query('select private.save_company_delivery_items($1::text[])',[[`data:${id(99011)}`,`data:${packet.item}`]]),'個別の承認画面');
   check(await q('select count(*)::int v from private.company_delivery_saved_items where company_id=$1',[B]),2);
   await db.query('insert into private.document_receive_codes(code,company_id,created_by)values($1,$2,$3)',[id(99021),A,UA]);
   const mixed={request_id:id(99020),code:id(99021),items:[{kind:'received_data',id:id(99011)},{kind:'received_data',id:packet.item}]};
   await expect(()=>db.query("select private.company_document_exchange('send',$1::jsonb)",[JSON.stringify(mixed)]),'個別の承認画面');
   check(await q('select used_at is null v from private.document_receive_codes where code=$1',[id(99021)]),true);
   mixed.items=[{kind:'received_data',id:id(99011)},{kind:'received_data',id:id(99012)}];
   await db.query("select private.company_document_exchange('send',$1::jsonb)",[JSON.stringify(mixed)]);
   check(await q('select count(*)::int v from private.company_data_delivery_items where delivery_id=$1',[id(99020)]),2);

   console.log(JSON.stringify({actual_public_jwt_bodies_and_fixture_live_sid_consumer_smoke:true,recipient_actor_checked:true,new_order_hidden_from_legacy_read_save_pair_inbox:true,old_qualification_personnel_read_save_retransfer:true,mixed_batches_denied_without_mutation:true,real_gotrue:false,full_production_schema:false,production_changed:false}));
  }finally{await db.exec('rollback');}
  check(await dataDigest(),beforeSmoke);check(await proc(),beforeSmokeFunctions);
 };
}
