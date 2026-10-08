// Isolated PostgreSQL/PGlite verification, never connects to production.
import fs from 'node:fs';import path from 'node:path';import {fileURLToPath,pathToFileURL} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);
const read=p=>fs.readFileSync(path.join(root,p),'utf8');const db=new PGlite();
try {
 await db.exec(read('supabase/tests/invoice_stamp_approval_workflow.sql'));
 await db.exec(read('supabase/tests/payroll_private_bank_assertions.sql').split('-- ASSERTIONS')[0]);
 await db.exec(read('supabase/tests/payroll_pay_type_metadata_assertions.sql').split('-- ASSERTIONS')[0]);
 const [fixture,assertions]=read('supabase/tests/paid_leave_attendance_overlap_assertions.sql').split('-- ASSERTIONS');
 await db.exec(fixture);
 await db.exec(read('supabase/migrations/20261008042817_prevent_paid_leave_attendance_overlap.sql'));
 await db.exec(assertions);
 console.log('Paid leave attendance overlap assertions passed');
}finally{await db.close();}
