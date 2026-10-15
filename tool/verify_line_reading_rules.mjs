// Isolated database only; synthetic identities and no network or production writes.
import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const {PGlite}=await import(process.env.SKO_PGLITE_MODULE ?? './line_release_fixture_dependencies/node_modules/@electric-sql/pglite/dist/index.js');
const db=new PGlite();
try {
 await db.exec(`create role anon;create role authenticated;create schema auth;create schema private;
 create table auth.users(id uuid primary key);create table public.communication_groups(id uuid primary key);
 create function auth.uid()returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
 create function private.line_import_access(uuid,text)returns jsonb language plpgsql as $$begin
 if auth.uid() is null or $1<>'00000000-0000-0000-0000-000000000001'::uuid then raise exception 'denied' using errcode='42501';end if;
 return jsonb_build_object('can_edit',current_setting('test.edit',true)='yes');end$$;
 grant usage on schema public,private,auth to authenticated,anon;
 insert into auth.users values('00000000-0000-0000-0000-000000000002');
 insert into public.communication_groups values('00000000-0000-0000-0000-000000000001'),('00000000-0000-0000-0000-000000000003');`);
 await db.exec(await readFile(new URL('../supabase/migrations/20261015021523_line_reading_rules.sql',import.meta.url),'utf8'));
 await db.exec(`set role authenticated;set test.uid='00000000-0000-0000-0000-000000000002';set test.edit='yes';`);
 const group='00000000-0000-0000-0000-000000000001';
 const rules=[{phrase:'新宿',kind:'site',value:'新宿ビル工事'}];
 const save=(revision,payload=rules,g=group)=>db.query('select public.save_line_reading_rules($1,$2,$3) result',[g,revision,JSON.stringify(payload)]);
 assert.equal((await save(0)).rows[0].result.revision,1);
 assert.deepEqual((await db.query('select public.line_reading_rules_workspace($1) result',[group])).rows[0].result.rules,rules);
 await assert.rejects(()=>save(0));
 await assert.rejects(()=>save(1,[...rules,...rules]));
 await assert.rejects(()=>save(1,rules,'00000000-0000-0000-0000-000000000003'));
 await db.exec(`set test.edit='no'`);await assert.rejects(()=>save(1));
 await db.exec(`set role anon`);await assert.rejects(()=>db.query('select public.line_reading_rules_workspace($1)',[group]));
 console.log('line reading rules: save/load, stale revision, duplicate, cross-group, read-only and anonymous checks passed');
}finally{await db.close();}
