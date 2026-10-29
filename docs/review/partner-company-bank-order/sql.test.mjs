import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
const {PGlite}=await import(process.argv[2]);const db=new PGlite();let passed=0;
const root=new URL('../../../',import.meta.url);
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
const count=async()=>{await db.exec('reset role');const n=(await db.query('select count(*)::int n from private.partner_company_bank_versions')).rows[0].n;await identity();return n;};
const readBank=async(c=company,p=partner)=>(await db.query('select public.partner_company_bank_read($1,$2) value',[c,p])).rows[0].value;
const saveBank=async(expected,fields=bank,id=request)=>(await db.query('select public.save_partner_company_bank($1,$2,$3,$4,$5) value',[company,partner,expected,id,fields])).rows[0].value;
const workspace=async(id=document,revision='1')=>(await db.query('select public.trade_document_attachment_workspace($1,$2,$3) value',['payment_certificate',id,revision])).rows[0].value;
const saveOrder=async(payload,version=0)=>(await db.query('select public.save_trade_document_attachment($1,$2,$3,$4,$5) value',['payment_certificate',document,'1',version,payload])).rows[0].value;
try {
 await identity();const baseline=await workspace();
 await db.exec('reset role');await db.exec(await read('docs/review/partner-company-bank-order/bank.sql.review-only'));
 await db.exec(await read('docs/review/partner-company-bank-order/order-snapshot.sql.review-only'));
 if(process.env.SKO_CONFIRMED_TERMS_HOOK==='content-v1')await db.exec(await read('docs/review/trade-document-terms/save-guard.sql.review-only'));
 await identity();assert.deepEqual(await workspace(),baseline);assert.equal((await readBank()).available,false);await assert.rejects(saveBank(0),/not released/);passed+=3;
 await db.exec('reset role;update private.partner_company_bank_rollout set enabled=true;');await identity();
 const first=await saveBank(0);assert.equal(first.account_number,'0000123');assert.equal(first.bank_version,1);assert.deepEqual(await saveBank(0),first);passed+=3;
 await assert.rejects(saveOrder({...baseline.defaults,issue_date:'2026-09-15',work_name:'工事',work_address:'東京',intro_text:'工事を発注',payment_conditions:'完了後支払い',notes:''}),e=>e.code==='40001');passed++;
 await assert.rejects(saveBank(0,{...bank,account_number:'0000999'}),/bound/);await assert.rejects(saveBank(0,bank,locked),/version changed/);passed+=2;
 for(const fields of [{...bank,account_number:'123'}, {...bank,account_number:'１２３４５６７'}, {...bank,bank_name:'x\ny'}, {...bank,unknown:'x'}, {bank_name:'partial'}]){await assert.rejects(saveBank(1,fields,locked));passed++;}
 for(const uid of [viewer,other]){await identity(uid,uid);await assert.rejects(readBank());await assert.rejects(saveBank(1));passed+=2;}
 for(const role of ['anon','service_role']){await identity(admin,session,role);await assert.rejects(readBank());passed++;}
 await identity();await db.exec("set test.blocked='true'");await assert.rejects(readBank());await db.exec("set test.blocked='false'");passed++;
 await db.exec('reset role');await db.query("update auth.users set banned_until=clock_timestamp()+interval '1 hour' where id=$1",[admin]);await identity();await assert.rejects(readBank());await assert.rejects(saveBank(1,bank,locked));passed+=2;
 await db.exec('reset role');await db.query('update auth.users set banned_until=null,is_anonymous=true where id=$1',[admin]);await identity();await assert.rejects(readBank());passed++;
 await db.exec('reset role');await db.query('update auth.users set is_anonymous=false where id=$1',[admin]);await identity();
 await db.exec('reset role');await db.query("update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id=$1",[session]);await identity();await assert.rejects(readBank());passed++;
 await db.exec('reset role');await db.query('update auth.sessions set not_after=null where id=$1',[session]);await identity();
 const second=await saveBank(1,{...bank,account_number:'0000456'},locked);assert.equal(second.bank_version,2);assert.equal(await count(),2);passed+=2;
 const w=await workspace();assert.equal(w.defaults.counterparty_bank.account_number,'0000456');passed++;
 const payload={...w.defaults,issue_date:'2026-09-15',work_name:'工事',work_address:'東京',intro_text:'工事を発注',payment_conditions:'完了後支払い',notes:'',counterparty_bank:w.defaults.counterparty_bank};
 await assert.rejects(saveOrder({...payload,counterparty_bank:{...first,account_number:'9999999'}}),/snapshot changed/);passed++;
 await saveBank(2,{...bank,account_number:'0000456'},document);await assert.rejects(saveOrder(payload),/snapshot changed/);passed+=2;
 payload.counterparty_bank=(await workspace()).defaults.counterparty_bank;
 const saved=await saveOrder(payload);assert.equal(saved.payload.counterparty_bank.account_number,'0000456');passed++;
 await assert.rejects(db.query('select private.save_trade_document_before_partner_bank($1,$2,$3,$4,$5)',['payment_certificate',document,'1',1,payload]),/permission denied/);passed++;
 await saveBank(3,{...bank,account_number:'0000789'},'10000000-0000-4000-8000-000000000013');
 const after=await workspace();assert.deepEqual(after.attachment.payload,saved.payload);assert.equal(after.source_changed,false);assert.equal(after.defaults.counterparty_bank,undefined);passed+=3;
 const edited=await saveOrder({...saved.payload,notes:'明示した下書き編集',counterparty_bank:first},1);assert.equal(edited.payload.counterparty_bank.account_number,'0000456');passed++;
 await identity(manager,otherSession);assert.equal((await readBank()).bank.account_number,'0000789');await assert.rejects(saveOrder(edited.payload,2),/管理者/);passed+=2;
 await saveBank(4,{...bank,branch_name:'管理者支店'},foreign);passed++;
 if(process.env.SKO_CONFIRMED_TERMS_HOOK==='content-v1'){
  await (await import('../../../tool/trade_document_terms_save_fixture.mjs')).verifyTermsSave(db,{id:n=>`10000000-0000-4000-8000-${String(n).padStart(12,'0')}`,company,partner,actor:()=>identity(),expectedDelegate:'b7711fe5caf45cf8afabc39856a86a0e'});
 }
 await db.exec('reset role');await db.query("update payment_certificates set status='approved',finalized_at=clock_timestamp() where id=$1",[document]);await db.query("update partner_companies set status='inactive' where id=$1",[partner]);await identity();
 assert.deepEqual((await workspace()).attachment.payload,edited.payload);assert.equal((await workspace(locked)).defaults.counterparty_bank,undefined);await assert.rejects(saveBank(5,bank,viewer));passed+=3;
 await db.exec('reset role');const immutable=(await db.query('select count(*)::int n from private.partner_company_bank_versions')).rows[0].n;
 for(const sql of ['update private.partner_company_bank_versions set bank_fields=bank_fields','delete from private.partner_company_bank_versions','truncate private.partner_company_bank_versions']){await assert.rejects(db.exec(sql),/immutable/);passed++;}
 assert.equal((await db.query('select count(*)::int n from private.partner_company_bank_versions')).rows[0].n,immutable);passed++;
 const originals=(await db.query("select proname,md5(prosrc) hash from pg_proc where pronamespace='private'::regnamespace and proname in ('trade_document_source_before_partner_bank','save_trade_document_before_partner_bank') order by proname")).rows;
 assert.equal(originals.find(x=>x.proname.startsWith('trade_')).hash,'ebcc70935938482054943560390038b2');assert.equal(originals.find(x=>x.proname.startsWith('save_')).hash,'82fa37936aea1e0199e1b359e1379d65');passed+=2;
 console.log(JSON.stringify({result:'PASS partner-bank isolated exact SQL',checks:passed,engine:process.env.PARTNER_BANK_TEST_DATABASE_URL?'native-postgres':'pglite',real_auth:false,production_changes:false,bank_values:'synthetic',original_bodies_preserved:true,default_off:true}));
} finally {await db.close();}
