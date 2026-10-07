// Disposable PostgreSQL verification; never connects to Supabase or production.
// npm install --prefix /tmp/sko-sql-runtime --save-exact @electric-sql/pglite@0.3.14
// node tool/verify_invoice_approval_sql.mjs /tmp/sko-sql-runtime/node_modules/@electric-sql/pglite/dist/index.js
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
if(!process.argv[2]) throw Error('Pass installed PGlite module path; see script comments.');
const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const db=new PGlite();
try {
 await db.exec(read('supabase/tests/invoice_stamp_approval_workflow.sql'));
 await db.exec(read('supabase/migrations/20261005081500_invoice_approval_workflow.sql'));
 await db.exec(read('supabase/migrations/20261007221757_invoice_stamp_policy_and_approval_history.sql'));
 await db.exec(read('supabase/tests/invoice_stamp_approval_assertions.sql'));
 console.log('Invoice approval assertions passed');
 const [fixture,assertions]=read('supabase/tests/payroll_private_bank_assertions.sql').split('-- ASSERTIONS');
 await db.exec(fixture);
 await db.exec(read('supabase/migrations/20261007222051_payroll_statement_private_bank_details.sql'));
 await db.exec(assertions);
 console.log('Payroll private bank assertions passed');
} finally {await db.close();}
