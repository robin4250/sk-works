const {PGlite}=require('@electric-sql/pglite');
const fs=require('fs');const assert=require('assert');
(async()=>{const db=new PGlite();
await db.exec(`create role anon;create role authenticated;create schema auth;create schema private;
create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
create table public.companies(id uuid primary key,name text,address text,phone text,corporate_number text);
create table public.company_members(company_id uuid,user_id uuid,role text);
create table private.company_connections(parent_company_id uuid,child_company_id uuid,status text,requested_by uuid,responded_by uuid,updated_at timestamptz,unique(parent_company_id,child_company_id));
create table public.app_notifications(company_id uuid,recipient_user_id uuid,kind text,title text,body text,action_key text,action_id uuid);
create function private.current_company_admin_id() returns uuid language sql as $$select company_id from public.company_members where user_id=auth.uid() and role in('owner','admin') limit 1$$;
create table public.customers(id uuid primary key default gen_random_uuid(),company_id uuid,name text,billing_name text,billing_address text,created_at timestamptz default now());
create table public.partner_companies(id uuid primary key default gen_random_uuid(),company_id uuid,name text,phone text,email text,address text,postal_code text,trade_role text,status text,created_at timestamptz default now());
create table public.trade_companies(id uuid primary key default gen_random_uuid(),company_id uuid,name text,address text,phone text,email text,postal_code text,corporate_number text,trade_role text,linked_company_id uuid,link_status text,created_by uuid,updated_by uuid,updated_at timestamptz,customer_id uuid,partner_company_id uuid);
insert into public.companies values('00000000-0000-0000-0000-000000000001','Alpha','A','1','111'),('00000000-0000-0000-0000-000000000002','Beta','B','2','222');
insert into public.company_members values('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','admin'),('00000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','admin');`);
await db.exec(fs.readFileSync('supabase/migrations/20261015005238_company_link_requests.sql','utf8'));
const login=async n=>db.exec(`set test.uid='10000000-0000-0000-0000-00000000000${n}'`);
await login(1);await db.exec('select public.set_trade_company_link_enabled(true)');
await login(2);await db.exec('select public.set_trade_company_link_enabled(true)');await login(1);
const r=await db.query(`select public.request_trade_company_link('00000000-0000-0000-0000-000000000002','customer','2026-10-01') id`);const id=r.rows[0].id;
assert.equal((await db.query('select * from public.trade_companies')).rows.length,0);
await assert.rejects(db.query(`select public.respond_trade_company_link('${id}','accept')`));
await login(2);await db.query(`select public.respond_trade_company_link('${id}','accept')`);
const rows=(await db.query('select company_id,trade_role from public.trade_companies order by company_id')).rows;
assert.equal(rows.length,2);assert.equal(rows[0].trade_role,'customer');assert.equal(rows[1].trade_role,'subcontractor');
assert.equal((await db.query('select * from public.customers')).rows.length,1);
assert.equal((await db.query('select * from public.partner_companies')).rows.length,1);
assert.equal((await db.query('select * from private.company_connections')).rows[0].status,'accepted');
await assert.rejects(db.query(`select public.respond_trade_company_link('${id}','accept')`));
await assert.rejects(db.query(`select private.confirm_trade_company_link(null,null)`));
await db.exec('select public.set_trade_company_link_enabled(false)');
await assert.rejects(db.query(`select public.search_trade_company_links('Alpha')`));
await login(9);await assert.rejects(db.query('select public.trade_company_link_workspace()'));
// Existing named legacy IDs must remain stable; ambiguous matches must never
// choose an arbitrary record, including when the second reciprocal attach fails.
async function legacyFixture(localRole, duplicateTable) {
 await db.exec(`truncate public.trade_companies,public.customers,public.partner_companies,private.trade_company_link_requests,private.company_connections,public.app_notifications;`);
 await login(2);await db.exec('select public.set_trade_company_link_enabled(true)');
 const customerOwner=localRole==='customer'?1:2;
 const partnerOwner=customerOwner===1?2:1;
 const ownerId=n=>`00000000-0000-0000-0000-00000000000${n}`;
 const otherName=n=>n===1?'Beta':'Alpha';
 const customerId='20000000-0000-0000-0000-000000000001';
 const partnerId='30000000-0000-0000-0000-000000000001';
 await db.query(`insert into public.customers(id,company_id,name,billing_name,billing_address) values('${customerId}','${ownerId(customerOwner)}',' ${otherName(customerOwner).toUpperCase()} ','Original billing','Original address')`);
 await db.query(`insert into public.partner_companies(id,company_id,name,phone,status) values('${partnerId}','${ownerId(partnerOwner)}',' ${otherName(partnerOwner).toUpperCase()} ','Original phone','active')`);
 if(duplicateTable==='customers') await db.query(`insert into public.customers(company_id,name) values('${ownerId(customerOwner)}','${otherName(customerOwner)}')`);
 if(duplicateTable==='partner_companies') await db.query(`insert into public.partner_companies(company_id,name) values('${ownerId(partnerOwner)}','${otherName(partnerOwner)}')`);
 const beforeCustomers=(await db.query('select * from public.customers order by id')).rows;
 const beforePartners=(await db.query('select * from public.partner_companies order by id')).rows;
 await login(1);
 const request=(await db.query(`select public.request_trade_company_link('${ownerId(2)}','${localRole}','2026-10-01') id`)).rows[0].id;
 const noticeCount=(await db.query('select count(*)::int n from public.app_notifications')).rows[0].n;
 await login(2);
 if(duplicateTable) {
  await assert.rejects(db.query(`select public.respond_trade_company_link('${request}','accept')`),/同名.*複数/);
  assert.equal((await db.query('select count(*)::int n from public.trade_companies')).rows[0].n,0,'neither directory side may remain attached');
  assert.equal((await db.query('select count(*)::int n from private.company_connections')).rows[0].n,0);
  assert.equal((await db.query(`select status from private.trade_company_link_requests where id='${request}'`)).rows[0].status,'pending');
  assert.equal((await db.query('select count(*)::int n from public.app_notifications')).rows[0].n,noticeCount,'no success notice on rolled-back approval');
 } else {
  await db.query(`select public.respond_trade_company_link('${request}','accept')`);
  const linked=(await db.query('select * from public.trade_companies')).rows;
  assert.equal(linked.length,2);
  assert.equal(linked.find(row=>row.company_id===ownerId(customerOwner)).customer_id,customerId);
  assert.equal(linked.find(row=>row.company_id===ownerId(partnerOwner)).partner_company_id,partnerId);
 }
 assert.deepEqual((await db.query('select * from public.customers order by id')).rows,beforeCustomers);
 assert.deepEqual((await db.query('select * from public.partner_companies order by id')).rows,beforePartners);
}
for(const role of ['customer','subcontractor']) {
 await legacyFixture(role,null);
 await legacyFixture(role,'customers');
 await legacyFixture(role,'partner_companies');
}
console.log('PASS: existing named legacy IDs preserved; ambiguous customer/partner matches atomically roll back both directions and retain pending requests; SQL migration executes; SQL migration executes; no preapproval changes; recipient-only atomic reciprocal approval; repeat and legacy bypass rejected; OFF and unauthorized access rejected.');await db.close();})();
