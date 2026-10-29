import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
const {PGlite}=await import(process.argv[2]);const db=new PGlite();let passed=0;
const root=new URL('../',import.meta.url);
const read=path=>fs.readFile(new URL(path,root),'utf8');
const old=await read('tool/verify_trade_document_attachment.mjs');
// Reuse the existing exact monthly-appendix fixture schema, not a mirror of new authorization.
await db.exec(old.match(/await db\.exec\(`([\s\S]*?)`\);/)[1]);
await db.exec(`create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
create table auth.users(id uuid primary key,is_anonymous boolean default false,banned_until timestamptz);
create function private.account_deletion_barrier_key(uuid)returns bigint language sql as $$select hashtextextended('account-deletion:'||$1::text,0)$$;
create function auth.jwt()returns jsonb language sql as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
alter table partner_companies add column status text default 'active';
create table trade_companies(company_id uuid,partner_company_id uuid,customer_id uuid,trade_role text,address text,corporate_number text,representative_name text);
create table private.partner_company_profile_extensions(company_id uuid,representative_name text);`);
await db.exec(await read('docs/review/company-work-category-policy/require_session.fixture.sql'));
await db.exec('revoke all on function private.require_reauthentication_session() from public,anon,authenticated,service_role');
await db.exec(await read('supabase/migrations/20261014124714_monthly_trade_document_attachment.sql'));
await db.exec(await read('docs/review/partner-company-bank-order/original-trade-document-source.sql.review-only'));
const [company,foreign,admin,manager,viewer,other,partner,document,locked,session,otherSession,request]=Array.from({length:12},(_,i)=>`10000000-0000-4000-8000-${String(i+1).padStart(12,'0')}`);
await db.query('insert into auth.users(id) values($1),($2),($3),($4)',[admin,manager,viewer,other]);
const bank={bank_name:'検証銀行',branch_name:'本店',account_type:'普通',account_number:'0000123',account_holder:'テストカイシャ'};
await db.query(`insert into companies values($1,'発注会社','東京','1234567890123',false,'legacy'),($2,'他社','大阪','9876543210987',false,'legacy')`,[company,foreign]);
await db.query(`insert into company_members values($1,$2,'admin'),($1,$3,'manager'),($1,$4,'viewer'),($5,$6,'admin')`,[company,admin,manager,viewer,foreign,other]);
await db.query(`insert into partner_companies(id,company_id,name,address,president_name) values($1,$2,'受注会社','東京','代表')`,[partner,company]);
await db.query(`insert into auth.sessions values($1,$2,null),($3,$4,null),($5,$5,null),($6,$6,null)`,[session,admin,otherSession,manager,viewer,other]);
await db.query(`insert into payment_certificates values($1,$2,$3,'2026-10-01','2026-10-31',1,'draft',null,110000,'{"tax":10000}',false),($4,$2,$3,'2026-11-01','2026-11-30',1,'approved',now(),110000,'{"tax":10000}',false)`,[document,company,partner,locked]);
const identity=async(uid=admin,sid=session,role='authenticated')=>{
 await db.exec(`reset role;set role ${role};`);
 await db.query(`select set_config('test.uid',$1,false),set_config('request.jwt.claims',$2,false)`,[uid,JSON.stringify({sub:uid,session_id:sid,role:'authenticated',is_anonymous:false})]);
};
const branch=process.argv[3];if(!['core','bank'].includes(branch))throw Error('core/bank fixture required');
process.on('uncaughtException',error=>{console.error(JSON.stringify({message:error.message,code:error.code,position:error.position,where:error.where}));process.exit(1)});
const q=async(sql,args)=>(await db.query(sql,args)).rows[0]?.v;
const pin=()=>q("select jsonb_agg(jsonb_build_object('oid',oid,'name',proname,'body',md5(prosrc),'owner',pg_get_userbyid(proowner),'acl',proacl::text,'config',proconfig,'secdef',prosecdef,'volatility',provolatile) order by oid) v from pg_proc where oid in (to_regprocedure('private.trade_document_source(text,uuid,text)'),to_regprocedure('private.save_trade_document_before_confirmed_terms(text,uuid,text,integer,jsonb)'),to_regprocedure('private.require_reauthentication_session()'),to_regprocedure('private.trade_document_source_before_partner_bank(text,uuid,text)'),to_regprocedure('private.save_trade_document_before_partner_bank(text,uuid,text,integer,jsonb)'))");
const deny=async(fn,code)=>{await assert.rejects(fn,error=>error.code===code);passed++;};
const fresh=()=>({schema:1,work_content:'明示した工事',issuer_phone:'',issuer_fax:'',payments:Object.fromEntries(['advance','partial','completion'].map(k=>[k,{choice:'unspecified',date:null,amount_yen:null}])),progress_cutoff_day:null,invoice_cutoff_day:null,payment_day:null,payment_month_offset:null,cash_ratio_percent:null,bill_ratio_percent:null,bill_months:null,supplies:'',rows:Array.from({length:9},()=>({item:'',quantity:'',unit:'',unit_price_yen:null,amount_yen:null,note:''}))});
const reference={schema:1,version:1,title:'[ 工事請負契約条項 ]',source_sha256:'3acf9090f2c027840bba43351f4d9e173759baa8b7c0340c05db9e28731f0d1f',renderer_contract:'sko-original-form-20261029-v1',design_sha256:'942bad918b696b4c2c527dbf2fca9d050e4fb38a3674cff115eb0755793b8a18'};
try{
 if(branch==='bank'){
  await db.exec(await read('docs/review/partner-company-bank-order/bank.sql.review-only'));
  await db.exec(await read('docs/review/partner-company-bank-order/order-snapshot.sql.review-only'));
  await db.exec('update private.partner_company_bank_rollout set enabled=true');
  await identity();await db.query('select public.save_partner_company_bank($1,$2,0,$3,$4::jsonb)',[company,partner,request,JSON.stringify(bank)]);await db.exec('reset role');
 }
 await db.exec(await read('docs/review/trade-document-terms/save-guard.sql.review-only'));
 const before=await pin();
 await db.exec(await read('docs/review/trade-document-form-input/server-save.sql.review-only'));
 assert.deepEqual(await pin(),before);passed++;
 await identity();
 const w=await q("select public.trade_document_attachment_workspace('payment_certificate',$1,'1') v",[document]);
 const payload={...w.defaults,issue_date:'2026-09-15',work_name:'明示工事',work_address:'東京',intro_text:'工事を発注',payment_conditions:'完了後支払い',notes:'',contract_terms:reference,form_fields:fresh()};
 const save=(p,version=0,rev='1')=>q("select public.save_trade_document_attachment('payment_certificate',$1,$2,$3,$4::jsonb) v",[document,rev,version,JSON.stringify(p)]);
 const mutations=[null,{...fresh(),extra:true},{...fresh(),schema:2},{...fresh(),rows:[]},{...fresh(),payment_day:32},{...fresh(),payment_month_offset:3},{...fresh(),cash_ratio_percent:'100.01'},{...fresh(),issuer_phone:3},{...fresh(),work_content:'x'.repeat(241)}];
 let f=fresh();f.rows[0].unit_price_yen='10';mutations.push(f);f=fresh();f.rows[0].amount_yen=-1;mutations.push(f);f=fresh();f.rows[0].quantity='1e3';mutations.push(f);f=fresh();f.rows[0].quantity='1.1234';mutations.push(f);
 f=fresh();f.payments.advance={choice:'no',date:'2026-10-01',amount_yen:null};mutations.push(f);f=fresh();f.payments.advance={choice:'yes',date:'2026-02-30',amount_yen:1};mutations.push(f);
 f=fresh();f.payments.advance.amount_yen=2147483648;mutations.push(f);f=fresh();f.rows[8].note='x'.repeat(81);mutations.push(f);f=fresh();f.bill_months=121;mutations.push(f);
 for(const fields of mutations)await deny(()=>save({...payload,form_fields:fields}),'22023');
 f=fresh();f.rows[0]={item:'明細',quantity:'1.250',unit:'m2',unit_price_yen:800,amount_yen:999,note:'積を推測しない'};f.rows[8].item='第九行';f.payments.advance={choice:'yes',date:'2028-02-29',amount_yen:0};f.payment_day=31;f.payment_month_offset=2;f.cash_ratio_percent='100.00';
 for(const uid of [viewer,other]){await identity(uid,uid);await deny(()=>save({...payload,form_fields:null}),'42501');}await identity();
 await deny(()=>db.query("select private.validate_trade_document_form_fields($1::jsonb)",[JSON.stringify(fresh())]),'42501');
 const first=await save({...payload,form_fields:f});assert.equal(first.payload.total_amount_yen,110000);assert.equal(first.payload.form_fields.rows[0].amount_yen,999);assert.deepEqual(first.payload.contract_terms,reference);passed++;
 const removed={...first.payload};delete removed.form_fields;await deny(()=>save(removed,1),'40001');
 await deny(()=>save({...first.payload,total_amount_yen:120000},1),'22023');
 await deny(()=>save({...first.payload,contract_terms:null},1),'40001');
 await deny(()=>save({...first.payload,form_fields:fresh(),unrelated_blob:'x'.repeat(16384)},1),'22023');
 const edited=await save({...first.payload,form_fields:{...f,supplies:'明示更新'}},1);assert.equal(edited.version,2);passed++;
 if(branch==='bank'){
  const alternative='90000000-0000-4000-8000-000000000001';await db.exec('reset role');
  await db.query('insert into public.partner_companies(id,company_id,name,address,president_name) select $1,company_id,name,address,president_name from public.partner_companies where id=$2',[alternative,partner]);
  await db.query('update public.payment_certificates set partner_company_id=$1,revision=2 where id=$2',[alternative,document]);await identity();
  await deny(()=>save(edited.payload,2,'2'),'40001'); // same name, different canonical ID
  await db.exec('reset role');await db.query('update public.payment_certificates set partner_company_id=$1 where id=$2',[partner,document]);await identity();
  const same=await save({...edited.payload,notes:'同じ正規相手への明示更新'},2,'2');assert.deepEqual(same.payload.counterparty_bank,first.payload.counterparty_bank);passed++;
 }else{
  await db.exec('reset role');await db.query('update public.payment_certificates set revision=2,gross_amount=120000 where id=$1',[document]);await identity();
  await deny(()=>save({...edited.payload,total_amount_yen:120000},2,'2'),'40001');
 }
 await db.exec('reset role');assert.deepEqual(await pin(),before);passed++;
 await deny(async()=>db.exec(await read('docs/review/trade-document-form-input/server-save.sql.review-only')),'55000');await db.exec('rollback');
 console.log(JSON.stringify({result:'PASS exact form server guard',branch,checks:passed,production_changes:false,real_auth:false}));
}finally{await db.close();}
