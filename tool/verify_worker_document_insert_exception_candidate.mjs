// Comparison design only. In-memory synthetic SQL, no Supabase credentials/connection.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
import {validatePaidLeaveFixtureUrl} from './paid_leave_pg17_database_guard.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
let db;
if(process.argv[3]==='--pg17') {
 const mod=await import(pathToFileURL(path.resolve(process.argv[2])).href);
 const Client=mod.Client??mod.default?.Client;
 db=new Client({connectionString:validatePaidLeaveFixtureUrl(process.env.SKO_PAID_LEAVE_FIXTURE_URL)});
 await db.connect();db.exec=q=>db.query(q);db.close=()=>db.end();
 assert.equal((Number((await db.query('show server_version_num')).rows[0].server_version_num)/10000)|0,17);
 assert.equal((await db.query("select count(*)::int n from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','auth','storage') and c.relkind in ('r','v','m')")).rows[0].n,0,'Only empty disposable fixture accepted');
} else {
 const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);db=new PGlite();
}
try {
 await db.exec(fs.readFileSync(path.join(root,'supabase/tests/worker_document_insert_exception_candidate_assertions.sql'),'utf8'));
 const n=(await db.query('select count(*)::int n from fixture_checks')).rows[0].n;assert.equal(n,59,'Expected complete candidate matrix');
 console.log('PASS candidate-only restrictive INSERT scope: 59 synthetic storage policy checks, retained overwrite/delete unchanged');
} catch(e) {console.error(e.code,e.message,e.where??'');process.exitCode=1;}
finally {await db.close();}
