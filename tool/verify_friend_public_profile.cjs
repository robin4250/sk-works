const fs=require('node:fs');
const {PGlite}=require(process.env.PGLITE_MODULE || '@electric-sql/pglite');
(async()=>{
const db=new PGlite();
await db.exec(`create role anon; create role authenticated;
create schema auth;create schema private;create schema storage;
create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
create table auth.users(id uuid primary key,deleted_at timestamptz,banned_until timestamptz);
create table private.account_deletion_access_restrictions(user_id uuid primary key);
create function private.account_access_allowed() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and not exists(
 select 1 from private.account_deletion_access_restrictions where user_id=auth.uid())$$;
revoke all on function private.account_access_allowed() from public,anon;
grant execute on function private.account_access_allowed() to authenticated;
create table private.sko_friends(user_a uuid,user_b uuid);
create table public.user_profiles(user_id uuid,display_name text,avatar_storage_path text,address text);
create table public.companies(id uuid,name text);
create table public.company_members(user_id uuid,company_id uuid);
create table storage.objects(name text,bucket_id text);alter table storage.objects enable row level security;
grant usage on schema public,private,auth,storage to authenticated;
grant select on storage.objects to authenticated;
`);
await db.exec(fs.readFileSync('supabase/migrations/20261015014752_friend_public_profile_and_direct_search.sql','utf8'));
const a='00000000-0000-0000-0000-000000000001',b='00000000-0000-0000-0000-000000000002',c='00000000-0000-0000-0000-000000000003';
await db.exec(`insert into auth.users(id) values('${a}'),('${b}'),('${c}');
insert into private.sko_friends values('${a}','${b}');
insert into public.user_profiles values('${b}','友達','${b}/photo.png','秘密住所'),('${c}','非友達','${c}/secret.png','秘密住所');
insert into storage.objects values('${b}/photo.png','profile-photos'),('${c}/secret.png','profile-photos');
set test.uid='${a}';set role authenticated;`);
let rows=(await db.query('select public.sko_friend_public_profiles() data')).rows[0].data;
if(rows.length!==1||rows[0].user_id!==b||JSON.stringify(Object.keys(rows[0]).sort())!==JSON.stringify(['avatar_storage_path','company_name','display_name','user_id']))throw Error('identity allowlist');
async function assertHidden(label){
 if((await db.query('select public.sko_friend_public_profiles() data')).rows[0].data.length)throw Error(label+' profile');
 if((await db.query('select * from storage.objects')).rows.length)throw Error(label+' photo');
}
// Deletion/access restrictions take effect before auth.users is removed or banned.
for(const user of [a,b]){
 await db.exec(`reset role;insert into private.account_deletion_access_restrictions values('${user}');set role authenticated;`);
 await assertHidden(user===a?'restricted actor':'restricted peer');
 await db.exec(`reset role;delete from private.account_deletion_access_restrictions;set role authenticated;`);
}
await db.exec(`reset role;set test.uid='${c}';set role authenticated;`);
await assertHidden('different actor');
await db.exec(`reset role;set test.uid='${a}';set role authenticated;`);
for(const user of [a,b]){
 await db.exec(`reset role;update auth.users set banned_until=now()+interval '1 day' where id='${user}';set role authenticated;`);
 await assertHidden(user===a?'banned actor':'banned peer');
 await db.exec(`reset role;update auth.users set banned_until=null;set role authenticated;`);
}

if((await db.query('select * from storage.objects')).rows.length!==1)throw Error('photo boundary');
await db.exec(`reset role;delete from private.sko_friends;set role authenticated;`);
if((await db.query('select public.sko_friend_public_profiles() data')).rows[0].data.length)throw Error('unfriend identity');
if((await db.query('select * from storage.objects')).rows.length)throw Error('unfriend photo');
await db.exec(`reset role;insert into private.sko_friends values('${a}','${b}');update auth.users set deleted_at=now() where id='${b}';set role authenticated;`);
if((await db.query('select public.sko_friend_public_profiles() data')).rows[0].data.length)throw Error('deleted user');
await db.exec(`reset role;set test.uid='';set role authenticated;`);
if((await db.query('select public.sko_friend_public_profiles() data')).rows[0].data.length)throw Error('no actor');
console.log('friend profile: exact identity allowlist, restriction before auth deletion (actor/peer), different actor, banned actor/peer, photo RLS, unfriend, deleted user, unauthenticated all passed');
await db.close();
})().catch(e=>{console.error(e);process.exit(1)});
