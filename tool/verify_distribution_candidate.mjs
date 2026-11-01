import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const {PGlite}=await import(process.env.PGLITE_PACKAGE||'@electric-sql/pglite');
const db=new PGlite();let assertions=0;
const eq=(a,b)=>{assert.deepEqual(a,b);assertions++;};
const q=async(s,args=[]) => (await db.query(s,args)).rows;
const scalar=async(s,args=[]) => Object.values((await q(s,args))[0])[0];
const deny=async(s,args=[])=>{await assert.rejects(()=>db.query(s,args));assertions++;};
const root=process.env.REFERRAL_SOURCE_ROOT||new URL('../',import.meta.url);
const oldSql=await readFile(new URL('supabase/migrations/20261015012003_app_referral_invites.sql',String(root).endsWith('/')?root:String(root)+'/'),'utf8');
const candidate=await readFile(process.env.DISTRIBUTION_SQL||new URL('../docs/candidates/app_distribution_channels_20261020.sql.review-only',import.meta.url),'utf8');
const owner='00000000-0000-0000-0000-000000000001',other='00000000-0000-0000-0000-000000000002',company='00000000-0000-0000-0000-000000000003';
async function as(actor,master=false){await db.exec(`reset role;set test.uid='${actor}';set test.master='${master}';set test.allowed='true';set role authenticated;`);}
try{
 await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create schema private;
 create table auth.users(id uuid primary key);create table public.companies(id uuid primary key,name text);
 create table public.company_members(user_id uuid,company_id uuid,role text);create table public.user_profiles(user_id uuid,display_name text);
 create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
 create function private.account_access_allowed() returns boolean language sql as $$select current_setting('test.allowed',true)='true'$$;
 create function public.is_current_user_master_admin() returns boolean language sql as $$select current_setting('test.master',true)='true'$$;
 grant usage on schema private,auth to authenticated;`);
 await db.exec(oldSql);
 await db.exec('create role fixture_default_grantee');
 for (const [grant,revoke,error] of [
  ['alter default privileges in schema private grant select on tables to fixture_default_grantee',
   'alter default privileges in schema private revoke select on tables from fixture_default_grantee',/unexpected distribution table ACL/],
  ['alter default privileges in schema private grant execute on functions to fixture_default_grantee',
   'alter default privileges in schema private revoke execute on functions from fixture_default_grantee',/unexpected distribution function ACL/],
  ['alter default privileges in schema public grant execute on functions to fixture_default_grantee',
   'alter default privileges in schema public revoke execute on functions from fixture_default_grantee',/unexpected distribution function ACL/],
 ]) {
  await db.exec(grant);await assert.rejects(()=>db.exec(candidate),error);assertions++;
  await db.exec('rollback');
  eq(await scalar("select to_regclass('private.app_distribution_links') is null"),true);
  eq(await scalar("select md5(prosrc) from pg_proc where oid='private.app_referral_dispatch(text,jsonb)'::regprocedure"),'3ccced6e2d9a82d715e07c6b3f25b490');
  await db.exec(revoke);
 }
 // Supabase's production-like public function defaults: explicitly revoke
 // anon/service_role while retaining only authenticated EXECUTE after install.
 await db.exec('alter default privileges in schema public grant execute on functions to anon,authenticated,service_role');
 await db.exec(candidate);
 const publicFunctions=['public.app_distribution_snapshot(boolean)','public.app_distribution_prepare(text,text,text,text)',
  'public.app_distribution_save_links(text,text,text)','public.app_referral_save_flags(boolean,boolean,boolean)'];
 for(const [apiRole,expected] of [['anon',false],['service_role',false],['authenticated',true]]) {
  const privileges=await Promise.all(publicFunctions.map(signature=>scalar('select has_function_privilege($1::text,$2::text,\'EXECUTE\')',[apiRole,signature])));
  eq(privileges.every(value=>value===expected),true);
 }
 await db.exec(`insert into auth.users values('${owner}'),('${other}');insert into companies values('${company}','Fixture company');
 insert into company_members values('${owner}','${company}','owner'),('${other}','${company}','employee');`);
 const snapshot='select public.app_distribution_snapshot($1::boolean)';
 const save='select public.app_distribution_save_links($1::text,$2::text,$3::text)';
 const flags='select public.app_referral_save_flags($1::boolean,$2::boolean,$3::boolean)';
 const prepare='select public.app_distribution_prepare($1::text,$2::text,$3::text,$4::text)';
 const tf='https://testflight.apple.com/join/FIXTURE1',web='https://fixture.example.com/',guide='https://guide.example.com/';
 await as(owner,true);
 let snap=await scalar(snapshot,[true]);eq(snap.enabled,false);eq(snap.distribution_channels.every(c=>c.ready===false),true);
 await q(save,['','','']);await deny(prepare,['Fixture','09012345678','testflight','employee']);
 await q(save,[tf,web,guide]);snap=await scalar(snapshot,[true]);eq(snap.enabled,false);eq(snap.public_enabled,false);
 eq(snap.distribution_channels.map(c=>c.ready),[true,true,false]);
 await q(flags,[true,false,true]);
 const tfInvite=await scalar(prepare,['Fixture','+81 90-1234-5678','testflight','employee']);
 eq(tfInvite.phone,'09012345678');eq(tfInvite.message.includes(tf),true);
 const betaFriend=await scalar(prepare,['Fixture','09012345678','testflight','friend']);eq(betaFriend.message.includes(tf),true);
 const webFriend=await scalar(prepare,['Fixture','09012345678','web','friend']);eq(webFriend.message.includes(web),true);
 await deny(prepare,['Fixture','09012345678','public','friend']);
 const webInvite=await scalar(prepare,['Fixture','09012345678','web','company']);eq(webInvite.message.includes(web),true);
 await deny(prepare,['Fixture','09012345678','unknown','app']);
 await deny(prepare,['Fixture','09012345678','web','unknown']);
 // Channel/flag saves must not overwrite the legacy URL, even when it changed
 // independently between page load and flag save.
 await db.exec(`reset role;update private.app_referral_settings set distribution_url='https://testflight.apple.com/join/NEWEST';set role authenticated;`);
 await q(flags,[true,false,false]);snap=await scalar(snapshot,[true]);eq(snap.distribution_url,'https://testflight.apple.com/join/NEWEST');
 eq(snap.distribution_links,{testflight:tf,web,public:guide});
 for(const invalid of [['http://testflight.apple.com/join/X','',''],['https://testflight.apple.com.evil.example/join/X','',''],
  ['', 'https://user:secret@example.com/',''],['','http://fixture.example.com/',''],['','','javascript:alert(1)'],
  ['','https://127.0.0.1/',''],['','https://localhost/','']]) await deny(save,invalid);
 await as(other);await deny(snapshot,[true]);await deny(save,[tf,web,guide]);await deny(flags,[true,true,true]);
 await deny(prepare,['Fixture','09012345678','testflight','employee']);
 snap=await scalar(snapshot,[false]);eq(snap.invitations.length,0);eq(snap.distribution_links,{});
 await deny('select * from private.app_distribution_links');await deny('select * from private.app_distribution_invitation_channels');
 await as(owner,true);await q(flags,[true,true,false]);await as(other);
 const friend=await scalar(prepare,['Fixture','09012345678','public','friend']);eq(friend.message.includes(guide),true);
 await deny(prepare,['Fixture','09012345678','testflight','friend']);
 await deny(prepare,['Fixture','09012345678','testflight','employee']);
 snap=await scalar(snapshot,[false]);eq(snap.invitations.length,1);eq(snap.invitations[0].distribution_label,'公開版の案内');
 eq(snap.distribution_channels.map(c=>c.ready),[false,false,true]);
 eq(snap.invitations[0].registered_user_id,null);eq(snap.invitations[0].points,null);
 await db.exec("set test.allowed='false'");await deny(snapshot,[false]);await deny(prepare,['Fixture','09012345678','public','friend']);
 await as(owner,true);snap=await scalar(snapshot,[true]);eq(snap.invitations.length,5);eq(snap.attribution_connected,false);
 eq(snap.invitations.find(r=>r.id===tfInvite.id).distribution_label,'TestFlight版');
 // Legacy callers cannot bypass the new public-only friend path or leak an
 // internal TestFlight URL through the old generic invitation method.
 await deny("select public.app_referral_prepare('Fixture','09012345678','friend_add')");
 await deny("select private.app_referral_dispatch('prepare','{\"name\":\"Fixture\",\"phone\":\"09012345678\",\"source\":\"friend_add\"}'::jsonb)");
 await as(other);await deny("select public.app_referral_prepare('Fixture','09012345678','app_invite')");
 await as(owner,true);
 await db.exec('begin');
 const legacy=await scalar("select public.app_referral_prepare('Fixture','09012345678','app_invite')");
 eq(legacy.message.includes('https://testflight.apple.com/join/NEWEST'),true);
 await db.exec('rollback');
 await q(save,['','','']);snap=await scalar(snapshot,[true]);eq(snap.distribution_channels.every(c=>c.ready===false),true);
 eq(snap.distribution_url_ready,false);
 await q(flags,[false,false,true]);
 await db.exec('reset role;set role anon');await deny(snapshot,[false]);await deny(save,[tf,web,guide]);
 await db.exec('reset role;set role service_role');await deny(prepare,['Fixture','09012345678','public','friend']);
 await db.exec('reset role');eq(await scalar('select count(*)::integer from private.app_referral_invitations'),5);
 eq(await scalar('select not enabled and not public_enabled from private.app_referral_settings where id'),true);
 await assert.rejects(()=>db.exec(candidate),/legacy referral dispatcher drift/);assertions++;
 await db.exec('rollback');
 eq(await scalar('select count(*)::integer from private.app_referral_invitations'),5);
 console.log(JSON.stringify({pass:true,assertions,production_changed:false,messages_sent:0,proof_of_real_delivery:false}));
}finally{await db.close();}
