// Comparison design only. In-memory synthetic SQL, no Supabase credentials/connection.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
const {PGlite}=await import(pathToFileURL(path.resolve(process.argv[2])).href);
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const db=new PGlite();
try {
 await db.exec(fs.readFileSync(path.join(root,'supabase/tests/worker_document_insert_exception_candidate_assertions.sql'),'utf8'));
 const n=(await db.query('select count(*)::int n from fixture_checks')).rows[0].n;assert.equal(n,39,'Expected complete candidate matrix');
 console.log('PASS candidate-only restrictive INSERT scope: 39 synthetic storage policy checks, retained overwrite/delete unchanged');
} catch(e) {console.error(e.code,e.message,e.where??'');process.exitCode=1;}
finally {await db.close();}
