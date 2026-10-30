import fs from 'node:fs/promises';
export async function verifySiteOrderPackageFlow(db,c){
 const {id,A,B,C,UA,UB,UC,actor,q}=c;let checks=0;
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
 console.log(JSON.stringify({status:'passed',checks,scope:'canonical original + nonfinancial legacy item atomic receive; prepared legacy approval guard; ordinary legacy OFF unchanged',production_applied:false,real_auth:false}));
}
