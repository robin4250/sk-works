const {PGlite}=require('@electric-sql/pglite');const fs=require('fs');const assert=require('assert');
(async()=>{const db=new PGlite();await db.exec(`
create role anon;create role authenticated;create schema private;create schema auth;
create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
create table public.companies(id uuid primary key,name text,address text,phone text,email text,corporate_number text);
create type public.app_role as enum('owner','admin','manager','worker','viewer');
create table public.company_members(company_id uuid,user_id uuid,role public.app_role);
create table private.account_deletion_access_restrictions(user_id uuid primary key);
CREATE OR REPLACE FUNCTION private.current_company_admin_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select cm.company_id
  from public.company_members cm
  where cm.user_id=auth.uid()
    and cm.role::text in ('owner','admin','manager')
  limit 1
$function$;
CREATE OR REPLACE FUNCTION private.account_access_allowed()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select auth.uid() is not null and not exists(
  select 1 from private.account_deletion_access_restrictions where user_id=auth.uid())
$function$;
create table public.trade_companies(id uuid primary key,company_id uuid,name text,address text,phone text,email text,corporate_number text,linked_company_id uuid,link_status text,updated_by uuid,updated_at timestamptz);
create table public.app_notifications(company_id uuid,recipient_user_id uuid,kind text,title text,body text,action_key text,action_id uuid);
insert into public.companies values('00000000-0000-0000-0000-000000000001','Alpha','Old source','1','a','111'),('00000000-0000-0000-0000-000000000002','Beta','B','2','b','222');
insert into public.company_members values('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','admin'),('00000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','admin');
insert into public.trade_companies(id,company_id,name,address,phone,email,corporate_number,linked_company_id,link_status) values('20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','Alpha local','Local old address','1','a','111','00000000-0000-0000-0000-000000000001','linked');
`);await db.exec(fs.readFileSync('supabase/migrations/20261015012352_company_profile_update_review.sql','utf8'));
const login=async n=>db.exec(`set test.uid='10000000-0000-0000-0000-00000000000${n}'`);
await login(1);await db.exec('select public.set_company_profile_review_enabled(true)');await login(2);await db.exec('select public.set_company_profile_review_enabled(true)');await login(1);
await db.exec(`update public.companies set address='New source' where name='Alpha'`);
assert.equal((await db.query('select address from public.trade_companies')).rows[0].address,'Local old address');
assert.equal((await db.query('select count(*) n from public.app_notifications')).rows[0].n,1);
const id=(await db.query('select id from private.company_profile_reviews')).rows[0].id;
const notice=(await db.query('select * from public.app_notifications')).rows[0];
assert.equal(notice.action_id,id);
assert.equal(notice.action_key,'company_profile_review');
assert.equal(notice.company_id,'00000000-0000-0000-0000-000000000002');
assert.equal(notice.recipient_user_id,'10000000-0000-0000-0000-000000000002');
await assert.rejects(db.query(`select public.respond_company_profile_review('${id}',true)`));
await login(2);await db.query(`select public.respond_company_profile_review('${id}',true)`);
assert.equal((await db.query('select address from public.trade_companies')).rows[0].address,'New source');
assert.deepEqual((await db.query('select old_value from private.company_profile_reviews')).rows[0].old_value,
 {name:'Alpha local',address:'Local old address',phone:'1',email:'a',corporate_number:'111'});
await assert.rejects(db.query(`select public.respond_company_profile_review('${id}',true)`));
await login(1);await db.exec(`update public.companies set address='Next source' where name='Alpha'`);
const pending=(await db.query("select id from private.company_profile_reviews where status='pending'")).rows[0].id;
await login(2);await db.exec("update public.trade_companies set address='Locally edited'");await assert.rejects(db.query(`select public.respond_company_profile_review('${pending}',true)`));
assert.equal((await db.query('select address from public.trade_companies')).rows[0].address,'Locally edited');
await db.exec('select public.set_company_profile_review_enabled(false)');await assert.rejects(db.query(`select public.respond_company_profile_review('${pending}',true)`));
await db.exec(`insert into public.company_members values
 ('00000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000003','manager'),
 ('00000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000004','admin');
 insert into private.account_deletion_access_restrictions values('10000000-0000-0000-0000-000000000004');
 grant usage on schema public,private,auth to authenticated;`);
for(const actor of [3,4]) {
 await login(actor);
 assert.equal((await db.query('select private.current_company_admin_id() id')).rows[0].id,'00000000-0000-0000-0000-000000000002');
 await db.exec('set role authenticated');
 for(const sql of [
  'select public.company_profile_review_workspace()',
  'select public.set_company_profile_review_enabled(true)',
  `select public.respond_company_profile_review('${pending}',true)`,
 ]) await assert.rejects(db.query(sql),/管理者のみ/);
 await db.exec('reset role');
}
assert.equal((await db.query(`select status from private.company_profile_reviews where id='${pending}'`)).rows[0].status,'pending');
console.log('PASS production role/account boundary; manager/restricted admin denied all profile RPCs; profile SQL: no silent overwrite; exact company authorization; old address kept; notification; accept; replay/local edit/OFF rejection');await db.close();})();
