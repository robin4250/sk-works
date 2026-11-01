import fs from 'node:fs';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const dir='docs/candidates/expense_removal_inert_off_stage_a_20261101/';
const source=fs.readFileSync(dir+'candidate.sql.review-only','utf8');
const baseline=fs.readFileSync('docs/candidates/expense_manager_removal_20261101.sql.review-only','utf8');
assert.equal(createHash('sha256').update(baseline).digest('hex'),'b2584677c81e50fa44cfbbc544de9fb6a4377e089875b5db09701f26953252e2');
const sql=source.replace(/--[^\n]*/g,'');
assert.deepEqual([...sql.matchAll(/create table\s+([\w.]+)/gi)].map(x=>x[1]),['private.expense_manager_removal_state','private.expense_manager_removals']);
assert.deepEqual([...sql.matchAll(/create function\s+([\w.]+)/gi)].map(x=>x[1]),['private.expense_manager_removal_immutable']);
assert.deepEqual([...sql.matchAll(/create trigger\s+(\w+)[\s\S]*?\bon\s+([\w.]+)/gi)].map(x=>[x[1],x[2]]),[
 ['expense_manager_removal_immutable','private.expense_manager_removals'],['expense_manager_removal_truncate_guard','private.expense_manager_removals']]);
assert.deepEqual([...sql.matchAll(/alter table\s+([\w.]+)\s+([^;]+)/gi)].map(x=>[x[1],x[2].trim()]),[
 ['private.expense_manager_removal_state','enable row level security'],['private.expense_manager_removals','enable row level security']]);
assert.deepEqual([...sql.matchAll(/\binsert into\s+([\w.]+)\s+([^;]+)/gi)].map(x=>[x[1],x[2].trim()]),[['private.expense_manager_removal_state','values(true,false)']]);
assert.equal(/\b(update|delete from|truncate|create or replace|drop|grant)\s/i.test(sql.replace(/before update or delete|before truncate/gi,'')),false);
assert.equal(/\breferences\b/i.test(sql),false,'FK must not install existing-table RI triggers in stage A');
assert.equal(/\b(?:public|auth|storage)\./.test(sql),false);
assert.equal(/private\.(?:expense_claims|expense_receipts|expense_settlement_choices|expense_amount_consumptions|expense_document_claims)\b/.test(sql),false);
const immutable=text=>text.match(/create function private\.expense_manager_removal_immutable\(\)[\s\S]*?\$\$([\s\S]*?)\$\$;/)[1];
assert.equal(immutable(source),immutable(baseline));
for(const text of ['before_row jsonb not null','before_settlement jsonb','receipt_snapshot jsonb',"receipt_state text not null check(receipt_state in ('attached_metadata_only','reserved_not_attached','unrecorded'))", "receipt_snapshot is not null and jsonb_typeof(receipt_snapshot)='object'", "current_database()<>'sko_expense_manager_removal_fixture'", "a.grantee<>creator", "p.proname='expense_manager_removal_immutable'", "pg_has_role(role_name,'postgres','MEMBER')"])assert.ok(source.includes(text),text);
console.log(JSON.stringify({source_checks:'passed',new_tables:2,new_function:1,new_table_triggers:2,existing_table_triggers:0,foreign_key:'explicitly deferred',public_rpc:0,existing_business_writes:0,sql_runtime:'not executed',deployable:false}));
