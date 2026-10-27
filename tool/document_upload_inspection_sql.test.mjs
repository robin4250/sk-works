import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
const modulePath = process.env.SKO_PGLITE_MODULE ?? 'tool/security/fixture_dependencies/node_modules/@electric-sql/pglite/dist/index.js';
const { PGlite } = await import(pathToFileURL(resolve(modulePath)));
const db = new PGlite();
try {
 await db.exec(`create role anon; create role authenticated; create role service_role;
 create schema private; create schema storage;
 create table storage.objects(bucket_id text,name text,version text,is_delete_marker boolean default false);`);
 await db.exec(await readFile(new URL('./document_upload_inspection.sql.review-only',import.meta.url),'utf8'));
 await db.exec(`insert into storage.objects values ('worker-documents','document-change/test','v1',false);
 insert into private.document_upload_inspection_candidates(id,actor_id,company_id,worker_id,requirement_id,request_id,object_path,object_version,status,expires_at)
 values ('00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-000000000006','document-change/test','v1','awaiting_inspection',clock_timestamp()+interval '2 minutes');`);
 const inspect = async (actor,version,sha='a'.repeat(64)) => (await db.query(`select private.commit_document_upload_inspection('00000000-0000-4000-8000-000000000001',$1,'00000000-0000-4000-8000-000000000006',$2,$3,16,'application/pdf') ok`,[actor,version,sha])).rows[0].ok;
 assert.equal(await inspect('00000000-0000-4000-8000-000000000009','v1'),false);
 assert.equal(await inspect('00000000-0000-4000-8000-000000000002','v2'),false);
 assert.equal(await inspect('00000000-0000-4000-8000-000000000002','v1',null),false);
 assert.equal(await inspect('00000000-0000-4000-8000-000000000002','v1'),true);
 assert.equal(await inspect('00000000-0000-4000-8000-000000000002','v1'),false);
 const perms=await db.query(`select has_function_privilege('authenticated','private.commit_document_upload_inspection(uuid,uuid,uuid,text,text,bigint,text)','execute') permitted`);
 assert.equal(perms.rows[0].permitted,false);
 console.log('isolated SQL: foreign actor/version/null/replay denied; authenticated cannot execute');
} finally { await db.close(); }
