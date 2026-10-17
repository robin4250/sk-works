import assert from 'node:assert/strict';
import fs from 'node:fs';
import {pathToFileURL} from 'node:url';
const {PGlite} = await import(pathToFileURL(process.argv[2]).href);
const db = new PGlite();
try {
  await db.exec(`
    create schema auth; create schema private;
    create role selected_reader;
    create table public.worker_personnel_profiles(id uuid primary key);
    create table public.worker_family_members(id uuid references public.worker_personnel_profiles(id));
    alter table public.worker_personnel_profiles enable row level security;
    create policy selected on public.worker_personnel_profiles to selected_reader using(true);
    create function public.employee_personnel_view(p integer) returns boolean language sql as 'select true';
    create function public.employee_personnel_view(p text) returns text language sql as $$select 'synthetic@example.invalid'$$;
    create function public.unrelated_secret() returns text language sql as $$select 'excluded'$$;
    begin read only;
  `);
  const sql=fs.readFileSync(new URL('./entry_definitions.sql.review-only',import.meta.url),'utf8');
  const data=(await db.query(sql)).rows[0].entry_definition_payload;
  assert.equal(data.read_only,true);
  assert.ok(data.relations.some(x=>x.name==='worker_personnel_profiles' && x.rls));
  assert.ok(data.policies.some(x=>x.name==='selected' && x.using==='true'));
  assert.ok(data.constraints.some(x=>x.type==='f'));
  const clean=data.functions.find(x=>x.identity==='p integer');
  assert.ok(clean.definition.includes('CREATE OR REPLACE FUNCTION'));
  const sensitive=data.functions.find(x=>x.identity==='p text');
  assert.equal(sensitive.definition,null);
  assert.equal(sensitive.literal_review_required,true);
  assert.ok(!data.functions.some(x=>x.name==='unrelated_secret'));
  assert.ok(!JSON.stringify(data).includes('synthetic@example.invalid'));
  assert.ok(!JSON.stringify(data).includes('rolpassword'));
  await db.exec('rollback');
  console.log('PASS: fixed metadata scope, strict read-only evidence, RLS/FK definitions, unrelated function exclusion, email-literal function omission. Synthetic only.');
} finally { await db.close(); }
