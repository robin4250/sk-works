// Isolated database only; synthetic identities and no network or production writes.
import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const {PGlite}=await import(process.env.SKO_PGLITE_MODULE ?? './line_release_fixture_dependencies/node_modules/@electric-sql/pglite/dist/index.js');
const db=new PGlite();
try {
 await db.exec(`create role anon;create role authenticated;create schema auth;create schema private;
 create table auth.users(id uuid primary key);
 create table public.communication_groups(id uuid primary key,company_id uuid,group_type text,participants_only boolean);
 create table public.company_members(company_id uuid,user_id uuid,role text);
 create table public.communication_group_members(group_id uuid,user_id uuid);
 create table public.member_feature_permissions(company_id uuid,user_id uuid,can_manage_partner_chat boolean);
 create function auth.uid()returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
 create function public.is_current_user_master_admin()returns boolean language sql as $$select auth.uid() is not null and current_setting('test.master',true)='yes'$$;
 create function private.line_client_access_allowed()returns boolean language sql as $$select auth.uid() is not null and coalesce(current_setting('test.line',true),'yes')<>'no'$$;
 create function private.account_access_allowed()returns boolean language sql as $$select auth.uid() is not null and coalesce(current_setting('test.account',true),'yes')<>'no'$$;
 create function private.has_company_feature(uuid,text)returns boolean language sql as $$select $2<>'can_manage_invoices' or current_setting('test.edit',true)='yes'$$;
 create function public.can_manage_attendance_corrections(uuid)returns boolean language sql as $$select false$$;
 grant usage on schema public,private,auth to authenticated,anon;
 insert into auth.users values('00000000-0000-0000-0000-000000000002');
 insert into public.communication_groups values('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000010','company',false),('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000011','company',false);
 insert into public.company_members values('00000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000002','owner');`);
 // Use the actual access contracts, with synthetic auth and feature toggles only.
 const accessSql=await readFile(new URL('../supabase/migrations/20261014123518_line_general_release_capability.sql',import.meta.url),'utf8');
 const start=accessSql.indexOf('CREATE OR REPLACE FUNCTION private.line_import_access(');
 await db.exec(accessSql.slice(start,accessSql.indexOf('\n;',start)+2));
 const groupAccessSql=await readFile(new URL('../supabase/migrations/20261004190939_restore_site_chat_visibility_after_custom_groups.sql',import.meta.url),'utf8');
 await db.exec(groupAccessSql.slice(groupAccessSql.indexOf('create or replace function')));
 await db.exec(await readFile(new URL('../supabase/migrations/20261015021523_line_reading_rules.sql',import.meta.url),'utf8'));
 await db.exec(`set role authenticated;set test.uid='00000000-0000-0000-0000-000000000002';set test.edit='yes';set test.master='yes';`);
 const group='00000000-0000-0000-0000-000000000001';
 const rules=[{phrase:'新宿',kind:'site',value:'新宿ビル工事'}];
 const save=(revision,payload=rules,g=group)=>db.query('select public.save_line_reading_rules($1,$2,$3) result',[g,revision,JSON.stringify(payload)]);
 assert.equal((await save(0)).rows[0].result.revision,1);
 assert.deepEqual((await db.query('select public.line_reading_rules_workspace($1) result',[group])).rows[0].result.rules,rules);
 await assert.rejects(()=>save(0));
 await assert.rejects(()=>save(1,[...rules,...rules]));
 await assert.rejects(()=>save(1,rules,'00000000-0000-0000-0000-000000000003'));
 // Company invoice admins/managers satisfy the existing import helper, but
 // neither public wrapper nor private implementation may expose Master rules.
 await db.exec(`set test.master='no';reset role;`);
 for(const role of ['owner','admin','manager']) {
  await db.exec(`update public.company_members set role='${role}';set role authenticated;`);
  assert.equal((await db.query("select private.line_import_access($1,'invoice') result",[group])).rows[0].result.can_edit,true);
  for(const name of ['public.line_reading_rules_workspace','private.line_reading_rules_workspace']) {
   await assert.rejects(()=>db.query(`select ${name}($1)`,[group]),/master reading rules/);
  }
  for(const name of ['public.save_line_reading_rules','private.save_line_reading_rules']) {
   await assert.rejects(()=>db.query(`select ${name}($1,$2,$3)`,[group,1,JSON.stringify(rules)]),/master reading rules/);
  }
  await db.exec('reset role');
 }
 await db.exec(`set test.master='yes';set role authenticated;`);
 assert.deepEqual((await db.query('select public.line_reading_rules_workspace($1) result',[group])).rows[0].result.rules,rules);
 await db.exec(`set test.line='no'`);
 await assert.rejects(()=>db.query('select public.line_reading_rules_workspace($1)',[group]),/LINE is unavailable/);
 await db.exec(`set test.line='yes';set test.account='no'`);
 await assert.rejects(()=>db.query('select public.line_reading_rules_workspace($1)',[group]),/LINE workspace unavailable/);
 await db.exec(`set test.account='yes'`);
 await db.exec(`set test.edit='no'`);await assert.rejects(()=>save(1));
 await db.exec(`set role anon`);await assert.rejects(()=>db.query('select public.line_reading_rules_workspace($1)',[group]));
 console.log('line reading rules: save/load, stale revision, duplicate, cross-group, actual import access, Master-only admin/manager boundary, read-only and anonymous checks passed');
}finally{await db.close();}
