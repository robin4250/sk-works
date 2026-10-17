import assert from 'node:assert/strict';
import fs from 'node:fs';
import {pathToFileURL} from 'node:url';

const {PGlite} = await import(pathToFileURL(process.argv[2]).href);
const db = new PGlite();
try {
  await db.exec(`
    create schema auth; create schema private;
    create role policy_only; create role capsule_parent; create role capsule_grantor;
    grant capsule_parent to capsule_grantor with admin option;
    set role capsule_grantor;
    grant capsule_parent to policy_only;
    reset role;
    create table public.worker_personnel_profiles(id uuid);
    create table public.worker_family_members(id uuid);
    create policy only_policy on public.worker_personnel_profiles to policy_only using(true);
    create function public.employee_personnel_view(p integer) returns boolean
      language sql as 'select true';
    create function public.employee_personnel_view(p text) returns boolean
      language sql as 'select true';
  `);
  const sql = fs.readFileSync(new URL('./role_dependency_inventory.sql.review-only', import.meta.url), 'utf8');
  const result = await db.query(sql);
  const capsule = result.rows[0].protected_catalog_capsule;
  assert.ok(capsule.objects.some(x => x.type === 'policy'));
  const names = capsule.roles.map(x => x.name);
  for (const name of ['policy_only', 'capsule_parent', 'capsule_grantor']) assert.ok(names.includes(name));
  assert.ok(capsule.memberships.some(x => x.member === 'policy_only' && x.role === 'capsule_parent' && x.grantor === 'capsule_grantor'));
  const functions = capsule.owner_acl.filter(x => x.kind === 'function').map(x => x.name);
  assert.ok(functions.includes('employee_personnel_view(p integer)'));
  assert.ok(functions.includes('employee_personnel_view(p text)'));
  assert.equal(new Set(functions).size, functions.length);
  assert.ok(!JSON.stringify(capsule).includes('rolpassword'));
  assert.ok(capsule.not_verified.includes('column ACL'));
  console.log('PASS: synthetic policy-only role, parent/grantor closure, overloaded function identities and explicit incomplete ACL scope. Production connections/writes: 0.');
} finally {
  await db.close();
}
