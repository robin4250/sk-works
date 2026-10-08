// Disposable PostgreSQL verification. Never connects to production.
import fs from 'node:fs';import path from 'node:path';import {fileURLToPath,pathToFileURL} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);
const read=p=>fs.readFileSync(path.join(root,p),'utf8');const db=new PGlite();
try {
 await db.exec(read('supabase/tests/invoice_stamp_approval_workflow.sql'));
 await db.exec(`alter table public.companies add column tax_rate numeric default 10,
 add column default_welfare_rate numeric default 3,add column updated_at timestamptz;`);
 const schema=read('supabase/migrations/20260922013000_add_admin_initial_setup_wizard.sql');
 await db.exec(schema.slice(schema.indexOf('create table if not exists public.company_rate_settings'),schema.indexOf('-- Existing production companies')));
 await db.exec(read('supabase/migrations/20260922020000_add_company_rate_settings_management.sql'));
 await db.exec(read('supabase/migrations/20261003002700_add_attendance_allowance_display_units.sql'));
 for(const fn of JSON.parse(read('docs/recovery/pre_company_rate_atomic_20261008.json'))) await db.exec(fn.definition);
 await db.exec(read('supabase/migrations/20261008043823_atomic_company_rate_and_allowance_units_save.sql'));
 await db.exec(read('supabase/tests/company_rate_atomic_assertions.sql'));
 console.log('Company rate atomic rollback and permissions assertions passed');
}finally{await db.close();}
