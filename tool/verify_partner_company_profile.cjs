const {PGlite}=require(process.env.PGLITE_PACKAGE || '@electric-sql/pglite');
const fs=require('node:fs'),assert=require('node:assert/strict'),path=require('node:path');
(async()=>{
const db=new PGlite(); let n=0;
try {
const id=x=>`00000000-0000-4000-8000-${String(x).padStart(12,'0')}`;
await db.exec(`create role anon; create role authenticated; create schema private; create schema auth;
 create function auth.uid() returns uuid language sql as $$select nullif(current_setting('fixture.actor',true),'')::uuid$$;
 create table public.companies(id uuid primary key,name text,address text,phone text,email text,corporate_number text,updated_at timestamptz default now());
 create table public.company_members(company_id uuid,user_id uuid,role text);
 create table private.company_connections(parent_company_id uuid,child_company_id uuid,status text);
 create function private.account_access_allowed() returns boolean language sql as $$select coalesce(current_setting('fixture.blocked',true),'')<>'true'$$;
 grant usage on schema private,auth to authenticated;
 insert into public.companies(id,name,address,phone,email,corporate_number) values
 ('${id(1)}','A','A secret address','A secret phone','A secret email','1111111111111'),
 ('${id(2)}','B',null,'B phone',null,null),('${id(3)}','C','C secret','C phone',null,null);
 insert into public.company_members values('${id(1)}','${id(11)}','owner'),('${id(2)}','${id(12)}','admin'),
 ('${id(1)}','${id(13)}','viewer'),('${id(1)}','${id(14)}','manager');
 insert into private.company_connections values('${id(1)}','${id(2)}','accepted');`);
// Execute the unchanged real contact writer against the synthetic company schema.
await db.exec('alter table companies add column fax text,add column bank_name text,add column bank_branch text,add column bank_account_number text,add column bank_account_holder text');
await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/migrations/20261003003500_add_company_data_profile.sql'),'utf8'));
await db.exec(fs.readFileSync(path.join(__dirname,'../docs/candidates/partner_company_profile_20261020.sql.review-only'),'utf8'));
const query=async(sql,args=[])=> (await db.query(sql,args)).rows[0]?.v;
const check=(a,b)=>{assert.deepEqual(a,b);n++;};
const deny=async fn=>{await assert.rejects(fn);n++;};
const actor=async x=>db.exec(`set fixture.actor='${id(x)}'`);
const read=cid=>query('select public.read_partner_company_profile($1) v',[id(cid)]);
const save=(cid,expected,name)=>query('select public.save_partner_company_representative($1,$2,$3) v',[id(cid),expected,name]);
check(await query('select private.partner_company_profile_ready($1) v',[id(1)]),false);
check(await query('select private.partner_company_profile_ready($1) v',[id(999)]),false);
await actor(11);await db.exec('set role authenticated');
let first=await read(1);check(first.ready,false);
let saved=await save(1,first,' A representative ');check(saved.profile.representative_name,'A representative');check(saved.ready,true);
// Match the document's 80-character contract after whitespace normalization.
const contactsBefore=await query('select public.company_data_state() v');
saved=await save(1,saved,'代'.repeat(80));check(saved.profile.representative_name,'代'.repeat(80));
saved=await save(1,saved,'  '+'代'.repeat(80)+'  ');check(saved.profile.representative_name,'代'.repeat(80));
let boundarySnapshot=await read(1);
let auditBoundary=await query('select count(*)::int v from private.partner_company_profile_audit');
await deny(()=>save(1,boundarySnapshot,'代'.repeat(81)));
check(await read(1),boundarySnapshot);
check(await query('select count(*)::int v from private.partner_company_profile_audit'),auditBoundary);
saved=await save(1,boundarySnapshot,' \t\n ');check(saved.profile.representative_name,null);check(saved.ready,false);
saved=await save(1,saved,'A representative');
check(await query('select public.company_data_state() v'),contactsBefore);
// Real legacy writer changes contacts only; it must not overwrite the extension.
let beforeContactWrite=await read(1);
await db.query('select public.save_company_data($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)',
 ['A','A changed address','1111111111111','A secret phone','','A secret email','','','','']);
check((await read(1)).profile.representative_name,'A representative');
await deny(()=>save(1,beforeContactWrite,'stale contact form'));
saved=await read(1);
await deny(()=>save(1,first,'stale overwrite'));
await deny(()=>save(1,saved,null));await deny(()=>save(1,saved,'x'.repeat(81)));
await deny(()=>db.query('select * from private.partner_company_profile_extensions'));
await deny(()=>db.query('select private.partner_company_profile_value($1)',[id(3)]));
await deny(()=>read(2));
await db.exec('reset role');await actor(12);await db.exec('set role authenticated');
let b=await save(2,await read(2),'B representative');check(b.ready,false);
await db.exec('reset role');
let visible=await query('select private.partner_company_profile_visible($1,$2) v',[id(2),id(1)]);
check(visible,{name:'A',phone:'A secret phone',representative_name:'A representative'});
check(JSON.stringify(visible).includes('secret address'),false);check(Object.hasOwn(visible,'email'),false);
await deny(()=>query('select private.partner_company_profile_visible($1,$2) v',[id(2),id(3)]));
await deny(()=>query('select private.partner_company_profile_visible($1,$2) v',[id(1),id(2)]));
check(await query('select private.partner_company_profile_label($1) v',[id(1)]),{name:'A',representative_name:'A representative'});
await db.exec(`update private.company_connections set status='disabled'`);
await deny(()=>query('select private.partner_company_profile_visible($1,$2) v',[id(2),id(1)]));
await db.exec(`update private.company_connections set status='accepted';update public.companies set address='B registered' where id='${id(2)}'`);
check(await query('select private.partner_company_profile_ready($1) v',[id(2)]),true);
check((await query('select private.partner_company_profile_visible($1,$2) v',[id(2),id(1)]) ).address,'A changed address');
await actor(11);let old=await read(1);
await db.exec(`update public.companies set phone='changed',updated_at=clock_timestamp() where id='${id(1)}'`);
await deny(()=>save(1,old,'stale contact snapshot'));
let before=await read(1),count=await query('select count(*)::int v from private.partner_company_profile_audit');
await db.exec(`create function private.fixture_fail() returns trigger language plpgsql as $$begin raise exception 'fixture'; end$$;
 create trigger fixture_fail before insert on private.partner_company_profile_audit for each row execute function private.fixture_fail()`);
await deny(()=>save(1,before,'rollback representative'));
check(await read(1),before);check(await query('select count(*)::int v from private.partner_company_profile_audit'),count);
await db.exec('drop trigger fixture_fail on private.partner_company_profile_audit');
for(const who of [13,14,99]){await actor(who);await db.exec('set role authenticated');await deny(()=>read(1));await deny(()=>save(1,before,'forbidden'));await db.exec('reset role');}
await actor(11);await db.exec("set fixture.blocked='true';set role authenticated");await deny(()=>read(1));await db.exec("reset role;set fixture.blocked='false';set fixture.actor='';set role authenticated");await deny(()=>read(1));
await db.exec('reset role;set role anon');await deny(()=>read(1));
console.log(`PASS ${n} profile readiness/visibility/CAS/ACL/rollback/80-char/real-writer checks`);
} finally { await db.close(); }
})().catch(e=>{console.error(e);process.exitCode=1;});
